@tool
class_name Ground
extends MeshInstance3D
## Procedural base plate - the surface rails snap onto and trackside models stand on.
##
## Stand-in for whatever terrain solution the real game uses. Heights come from
## one of two places: a gently rolling analytic function, or a [member heightmap]
## baked for one particular level. Either way the result is a regular grid split
## into triangles along the same diagonal, and [SurfaceSnapper] can read those
## triangles like any other mesh's - but it asks [method surface_height_at]
## instead, which answers for exactly the same triangles without walking them.

@export var size := Vector2(220.0, 180.0): set = _set_size
## Quads along each axis. Higher is smoother but slows snapping down, since
## snapping walks the triangles. Ignored with a [member heightmap], whose
## resolution is the grid.
@export_range(2, 400, 1) var subdivisions := 90: set = _set_subdivisions
@export var hill_height := 2.2: set = _set_hill_height
## Baked heights in metres, one per grid vertex, spread over [member size]:
## [constant Image.FORMAT_RF], the first row at -Z, the first column at -X.
## Replaces the analytic hills when set.
@export var heightmap: Image: set = _set_heightmap
@export_tool_button("Rebuild") var _rebuild_button := rebuild

@export_group("Colour")
## Colour of the lowest ground, blending into [member high_color] with height.
@export var low_color := Color(0.30, 0.42, 0.24): set = _set_low_color
@export var high_color := Color(0.55, 0.52, 0.35): set = _set_high_color
## Colour of bare faces, blended in by slope - rock where the ground is too
## steep to hold grass or sand.
@export var steep_color := Color(0.55, 0.52, 0.35): set = _set_steep_color
## How much of [member steep_color] a vertical face gets. Zero leaves slope out
## of the colouring altogether.
@export_range(0.0, 1.0) var steep_amount := 0.0: set = _set_steep_amount

## Heights of the grid the mesh was built from, row by row, kept so that
## [method surface_height_at] can answer without the mesh.
var _heights := PackedFloat32Array()
var _columns := 0
var _rows := 0
var _step := Vector2.ONE


func _ready() -> void:
	if mesh == null:
		rebuild()


## The mesh is generated, so it is never saved: an editor save would otherwise
## write every vertex into the scene, which for a baked heightmap is megabytes.
func _validate_property(property: Dictionary) -> void:
	if property.name == "mesh":
		property.usage &= ~PROPERTY_USAGE_STORAGE


## Height of the analytic terrain at a local XZ position.
static func height_at(x: float, z: float, amplitude: float) -> float:
	return amplitude * (sin(x * 0.06) * cos(z * 0.05) + 0.4 * sin(x * 0.13 + 1.3))


func rebuild() -> void:
	_fill_heights()
	if _columns < 2 or _rows < 2:
		mesh = null
		return
	var lowest := -hill_height
	var highest := hill_height
	if heightmap != null:
		lowest = INF
		highest = -INF
		for height in _heights:
			lowest = minf(lowest, height)
			highest = maxf(highest, height)

	var half := size * 0.5
	var count := _columns * _rows
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	vertices.resize(count)
	normals.resize(count)
	colors.resize(count)
	for row in _rows:
		for column in _columns:
			var index := row * _columns + column
			var height := _heights[index]
			var normal := _grid_normal(column, row)
			vertices[index] = Vector3(-half.x + float(column) * _step.x, height,
					-half.y + float(row) * _step.y)
			normals[index] = normal
			colors[index] = _color_for(height, lowest, highest, normal)

	# Two triangles per quad, wound so their normals point up, split along the
	# diagonal from the quad's -X-Z corner to its +X+Z one - surface_height_at
	# relies on that split. Get the winding backwards and the terrain is
	# invisible from above: still solid to the snapper, but culled as backfaces.
	var indices := PackedInt32Array()
	indices.resize((_columns - 1) * (_rows - 1) * 6)
	var at := 0
	for row in _rows - 1:
		for column in _columns - 1:
			var a := row * _columns + column
			var b := a + 1
			var c := a + _columns
			var d := c + 1
			indices[at] = a
			indices[at + 1] = d
			indices[at + 2] = c
			indices[at + 3] = a
			indices[at + 4] = b
			indices[at + 5] = d
			at += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var built := ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = built
	if material_override == null:
		material_override = _make_material()


#region Height queries
## True when [method surface_height_at] can be trusted: there is a grid, and the
## node stands upright, so that straight down in local space is straight down
## in the world too.
func answers_heights() -> bool:
	if _columns < 2 or _rows < 2 or not is_inside_tree():
		return false
	var basis := global_basis
	return is_zero_approx(basis.x.y) and is_zero_approx(basis.z.y) and basis.y.y > 0.0


## Global height of the mesh surface straight below global [param x]/[param z],
## or [code]null[/code] off the grid. Exactly what a ray cast down onto the
## triangles would find, only without walking them - see [method answers_heights]
## for when it applies.
func surface_height_at(x: float, z: float) -> Variant:
	var local := global_transform.affine_inverse() * Vector3(x, 0.0, z)
	var half := size * 0.5
	var u := (local.x + half.x) / _step.x
	var v := (local.z + half.y) / _step.y
	if u < 0.0 or v < 0.0 or u > float(_columns - 1) or v > float(_rows - 1):
		return null
	var column := mini(int(u), _columns - 2)
	var row := mini(int(v), _rows - 2)
	var across := u - float(column)
	var down := v - float(row)
	var index := row * _columns + column
	var h00 := _heights[index]
	var h10 := _heights[index + 1]
	var h01 := _heights[index + _columns]
	var h11 := _heights[index + _columns + 1]
	# The quad's two triangles meet along its h00-h11 diagonal.
	var height: float
	if down >= across:
		height = h00 + across * (h11 - h01) + down * (h01 - h00)
	else:
		height = h00 + across * (h10 - h00) + down * (h11 - h10)
	return (global_transform * Vector3(local.x, height, local.z)).y
#endregion


## Samples whichever height source is in use onto the grid.
func _fill_heights() -> void:
	if heightmap != null and not heightmap.is_empty():
		_columns = heightmap.get_width()
		_rows = heightmap.get_height()
	else:
		_columns = subdivisions + 1
		_rows = subdivisions + 1
	if _columns < 2 or _rows < 2:
		_heights = PackedFloat32Array()
		return
	_step = size / Vector2(float(_columns - 1), float(_rows - 1))
	_heights.resize(_columns * _rows)
	var half := size * 0.5
	var source: Image = heightmap if heightmap != null and not heightmap.is_empty() else null
	for row in _rows:
		for column in _columns:
			var height: float
			if source != null:
				height = source.get_pixel(column, row).r
			else:
				height = height_at(-half.x + float(column) * _step.x,
						-half.y + float(row) * _step.y, hill_height)
			_heights[row * _columns + column] = height


func _grid_height(column: int, row: int) -> float:
	return _heights[clampi(row, 0, _rows - 1) * _columns + clampi(column, 0, _columns - 1)]


func _grid_normal(column: int, row: int) -> Vector3:
	var slope_x := (_grid_height(column + 1, row) - _grid_height(column - 1, row)) / (2.0 * _step.x)
	var slope_z := (_grid_height(column, row + 1) - _grid_height(column, row - 1)) / (2.0 * _step.y)
	return Vector3(-slope_x, 1.0, -slope_z).normalized()


func _color_for(height: float, lowest: float, highest: float, normal: Vector3) -> Color:
	var color := low_color
	if highest > lowest:
		color = low_color.lerp(high_color, clampf(inverse_lerp(lowest, highest, height), 0.0, 1.0))
	if steep_amount > 0.0:
		# 0 on the flat, 1 on a vertical face; most of the change happens between
		# a gentle bank and a cliff.
		var steepness := smoothstep(0.15, 0.6, 1.0 - normal.y)
		color = color.lerp(steep_color, steepness * steep_amount)
	return color


func _make_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	# Vertex colours are consumed as linear unless this is set, which renders
	# anything authored by eye far darker and greyer than intended.
	material.vertex_color_is_srgb = true
	material.roughness = 0.95
	return material


## Setters rebuild only inside the tree. Loading a scene assigns every exported
## property in turn, and rebuilding on each would build a baked terrain several
## times over before [method _ready] builds it once more anyway.
func _changed() -> void:
	if is_inside_tree():
		rebuild()


func _set_size(value: Vector2) -> void:
	size = Vector2(maxf(value.x, 1.0), maxf(value.y, 1.0))
	_changed()


func _set_subdivisions(value: int) -> void:
	subdivisions = maxi(value, 2)
	_changed()


func _set_hill_height(value: float) -> void:
	hill_height = value
	_changed()


func _set_heightmap(value: Image) -> void:
	heightmap = value
	_changed()


func _set_low_color(value: Color) -> void:
	low_color = value
	_changed()


func _set_high_color(value: Color) -> void:
	high_color = value
	_changed()


func _set_steep_color(value: Color) -> void:
	steep_color = value
	_changed()


func _set_steep_amount(value: float) -> void:
	steep_amount = value
	_changed()
