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

@export var size := Vector2(220.0, 180.0):
	set(value):
		size = Vector2(maxf(value.x, 1.0), maxf(value.y, 1.0))
		_changed()
## Quads along each axis. Higher is smoother but slows snapping down, since
## snapping walks the triangles. Ignored with a [member heightmap], whose
## resolution is the grid.
@export_range(2, 400, 1) var subdivisions := 90:
	set(value):
		subdivisions = maxi(value, 2)
		_changed()
@export var hill_height := 2.2:
	set(value):
		hill_height = value
		_changed()
## Baked heights in metres, one per grid vertex, spread over [member size]:
## [constant Image.FORMAT_RF], the first row at -Z, the first column at -X.
## Replaces the analytic hills when set.
@export var heightmap: Image:
	set(value):
		heightmap = value
		_changed()
@export_tool_button("Rebuild") var _rebuild_button := rebuild

@export_group("Colour")
## Colour of the lowest ground, blending into [member high_color] with height.
@export var low_color := Color(0.30, 0.42, 0.24):
	set(value):
		low_color = value
		_changed()
@export var high_color := Color(0.55, 0.52, 0.35):
	set(value):
		high_color = value
		_changed()
## Colour of bare faces, blended in by slope - rock where the ground is too
## steep to hold grass or sand.
@export var steep_color := Color(0.55, 0.52, 0.35):
	set(value):
		steep_color = value
		_changed()
## How much of [member steep_color] a vertical face gets. Zero leaves slope out
## of the colouring altogether.
@export_range(0.0, 1.0) var steep_amount := 0.0:
	set(value):
		steep_amount = value
		_changed()

## Heights of the grid as authored - the terrain itself - row by row. Snapping
## reads these ([method terrain_height_at]), so that nothing the track does to
## the ground can move the track.
var _heights := PackedFloat32Array()
## The same grid with every cut asked for by [constant SHAPER_GROUP] made in
## it: what the mesh is built from and [method surface_height_at] answers.
var _surface := PackedFloat32Array()
## [member _surface] lowered further round each tunnel mouth, used inside the
## mouth's apron only - see [method _lower_apron].
var _apron_surface := PackedFloat32Array()
var _columns := 0
var _rows := 0
var _step := Vector2.ONE
## The height range the colours were blended over, kept for
## [method surface_color_at].
var _lowest := 0.0
var _highest := 0.0
## The tunnel mouths the mesh is opened for.
var _holes: Array[Hole] = []
## What [constant SHAPER_GROUP] asked for at the last build.
var _shapes: Array = []

## Nodes in this group shape the mesh round themselves. Each answers either or
## both of these, given this ground:
##
## - [code]ground_cuts(ground)[/code]: lines along which the ground must lie no
##   higher than the line itself - the track's bed. Each a dictionary:
##   [code]"line"[/code], a [PackedVector3Array] in global space;
##   [code]"half_width"[/code], how far either side of it has to be clear
##   (the grid's cell diagonal is added, so that no triangle reaching into that
##   width can rise above the line). Points past either end of a line are left
##   alone.
## - [code]ground_holes(ground)[/code]: tunnel mouths. Each a dictionary:
##   [code]"line"[/code], the bore's centre line at bed level from the portal's
##   face inward, global; [code]"half_width"[/code] of the bore's outside;
##   [code]"roof"[/code], the height of the bore's outside above the line. The
##   ground inside that box is cut out of the mesh exactly - the bore's own
##   shell fills the hole - and in front of the face, for
##   [method apron_length] metres, the ground is levelled with the bed so the
##   cell straddling the face cannot rise into the opening.
##
## Both shape only the mesh and [method surface_height_at]:
## [method terrain_height_at] still answers the ground as authored.
const SHAPER_GROUP := &"ground_shapers"
## Nodes in this group stand on the ground and measured it to do so - a
## signal's mast, a turnout's marker. Each has [code]ground_changed()[/code]
## called once the ground has been shaped anew, to measure it again.
const STANDING_GROUP := &"ground_standing"
## The cut under a bore stops this far under its roof, so the shell's roof
## always covers the cut's edge.
const _ROOF_GAP := 0.02
## Shapes that have moved less than this are not built again (see
## [method refresh_shapes]). The track's bed is cut 6 cm under its ballast,
## so a stale cut this far out still never shows.
const _SHAPE_TOLERANCE := 0.05



## A tunnel mouth's [code]ground_holes[/code] entry in local space, with what
## cutting it needs (see [method _local_hole]).
class Hole:
	## The bore's centre line at bed level, from the face inward.
	var line: PackedVector3Array
	## The bore's footprint in plan, and its bounds.
	var polygon: PackedVector2Array
	var bounds: Rect2
	## The levelled ground in front of the face, and its bounds.
	var apron: PackedVector2Array
	var apron_bounds: Rect2
	## The bore's outside above [member line].
	var roof: float
	var half_width: float
	## The face's own frame in plan, and its height.
	var face: Vector2
	var outward: Vector2
	var across: Vector2
	var bed: float


func _ready() -> void:
	if mesh == null:
		rebuild()
	# Built before the rails it is shaped round have settled: they snap, and
	# turnouts weld their branches on, as they become ready themselves.
	refresh_shapes.call_deferred()


## The mesh is generated, so it is never saved: an editor save would otherwise
## write every vertex into the scene, which for a baked heightmap is megabytes.
func _validate_property(property: Dictionary) -> void:
	if property.name == "mesh":
		property.usage &= ~PROPERTY_USAGE_STORAGE


## Height of the analytic terrain at a local XZ position.
static func _hill_height_at(x: float, z: float, amplitude: float) -> float:
	return amplitude * (sin(x * 0.06) * cos(z * 0.05) + 0.4 * sin(x * 0.13 + 1.3))


func rebuild() -> void:
	_fill_heights()
	if _columns < 2 or _rows < 2:
		mesh = null
		return
	_find_height_range()
	_shapes = _collect_shapes()
	_apply_shapes(_shapes)
	var grid := _grid_vertices()
	var cut := MeshSurface.new()
	grid.indices = _grid_indices(grid, cut)
	# The cut-up triangles go on the end, three fresh vertices each.
	var count := grid.vertices.size()
	for i in cut.vertices.size():
		grid.indices.append(count + i)
	grid.vertices.append_array(cut.vertices)
	grid.normals.append_array(cut.normals)
	grid.colors.append_array(cut.colors)
	var built := ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, grid.arrays())
	mesh = built
	if material_override == null:
		material_override = TrackMaterials.vertex_coloured(0.95)


## The height range the colours blend over: the analytic hills' amplitude, or
## whatever a heightmap spans.
func _find_height_range() -> void:
	_lowest = -hill_height
	_highest = hill_height
	if heightmap != null:
		_lowest = INF
		_highest = -INF
		for height in _heights:
			_lowest = minf(_lowest, height)
			_highest = maxf(_highest, height)


## One vertex per grid point of [member _surface], coloured by height and slope.
func _grid_vertices() -> MeshSurface:
	var normals := _normals_in(_surface)
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	vertices.resize(_columns * _rows)
	colors.resize(_columns * _rows)
	for row in _rows:
		for column in _columns:
			var index := row * _columns + column
			var height := _surface[index]
			var xz := _grid_xz(column, row)
			vertices[index] = Vector3(xz.x, height, xz.y)
			colors[index] = _color_for(height, _lowest, _highest, normals[index])
	var grid := MeshSurface.new()
	grid.vertices = vertices
	grid.normals = normals
	grid.colors = colors
	return grid


## Two triangles per quad, wound so their normals point up, split along the
## diagonal from the quad's -X-Z corner to its +X+Z one - surface_height_at
## relies on that split. Get the winding backwards and the terrain is invisible
## from above: still solid to the snapper, but culled as backfaces. Quads near a
## tunnel mouth are cut up exactly instead, onto [param cut] (see
## [method _add_clipped]).
func _grid_indices(grid: MeshSurface, cut: MeshSurface) -> PackedInt32Array:
	var apron_normals := _normals_in(_apron_surface) if not _holes.is_empty() \
			else PackedVector3Array()
	var indices := PackedInt32Array()
	indices.resize((_columns - 1) * (_rows - 1) * 6)
	var at := 0
	for row in _rows - 1:
		for column in _columns - 1:
			var a := row * _columns + column
			var b := a + 1
			var c := a + _columns
			var d := c + 1
			if not _holes.is_empty() and _near_hole(Rect2(grid.vertices[a].x, grid.vertices[a].z,
					_step.x, _step.y)):
				_add_clipped(PackedInt32Array([a, d, c]), grid, apron_normals, cut)
				_add_clipped(PackedInt32Array([a, b, d]), grid, apron_normals, cut)
				continue
			indices[at] = a
			indices[at + 1] = d
			indices[at + 2] = c
			indices[at + 3] = a
			indices[at + 4] = b
			indices[at + 5] = d
			at += 6
	indices.resize(at)
	return indices


## Rebuilds if what [constant SHAPER_GROUP] asks for has changed since the last
## build - called once everything is ready, and by the shapers themselves once
## they have moved - and tells [constant STANDING_GROUP] so.
func refresh_shapes() -> void:
	if not is_inside_tree() or _columns < 2 or _rows < 2:
		return
	if _same_shapes(_collect_shapes(), _shapes):
		return
	rebuild()
	get_tree().call_group(STANDING_GROUP, &"ground_changed")


## Whether two collections of shapes are the same to [constant _SHAPE_TOLERANCE]:
## a turnout welding its branch on moves a rail by millimetres, which is no
## reason to build the whole ground again.
static func _same_shapes(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	match typeof(a):
		TYPE_ARRAY:
			var left: Array = a
			var right: Array = b
			if left.size() != right.size():
				return false
			for i in left.size():
				if not _same_shapes(left[i], right[i]):
					return false
			return true
		TYPE_DICTIONARY:
			var left: Dictionary = a
			var right: Dictionary = b
			if left.size() != right.size():
				return false
			for key: Variant in left:
				if not right.has(key) or not _same_shapes(left[key], right[key]):
					return false
			return true
		TYPE_PACKED_VECTOR3_ARRAY:
			var left: PackedVector3Array = a
			var right: PackedVector3Array = b
			if left.size() != right.size():
				return false
			for i in left.size():
				if left[i].distance_squared_to(right[i]) > _SHAPE_TOLERANCE * _SHAPE_TOLERANCE:
					return false
			return true
		TYPE_FLOAT:
			return absf(float(a) - float(b)) <= _SHAPE_TOLERANCE
	return a == b


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
## for when it applies. Inside a tunnel mouth, where the mesh is cut away, it
## still answers the ground that was there.
func surface_height_at(x: float, z: float) -> Variant:
	var local := global_transform.affine_inverse() * Vector3(x, 0.0, z)
	var field := _surface
	var point := Vector2(local.x, local.z)
	for hole in _holes:
		if hole.apron_bounds.has_point(point) \
				and Geometry2D.is_point_in_polygon(point, hole.apron):
			field = _apron_surface
			break
	return _height_in(field, local)


## Global height of the terrain as authored below global [param x]/[param z], or
## [code]null[/code] off the grid: [method surface_height_at] before any
## [constant SHAPER_GROUP] cut was made. What rails snap to - the track cuts its
## bed into the ground, and must not then follow its own cut down.
func terrain_height_at(x: float, z: float) -> Variant:
	return _height_in(_heights, global_transform.affine_inverse() * Vector3(x, 0.0, z))


## Length of a grid cell's diagonal - the furthest one vertex of a triangle can
## be from another, so the margin a cut needs to hold everywhere in between.
func cell_diagonal() -> float:
	return _step.length()


## How far in front of a tunnel mouth's face the ground is levelled with the
## bed (see [constant SHAPER_GROUP]): two cells, so the levelling has died away
## before the apron ends.
func apron_length() -> float:
	return 2.0 * cell_diagonal() + 0.1


## Colour of the ground straight below global [param x]/[param z], or
## [code]null[/code] off the grid: what the mesh is painted there, so that
## something laid on the ground can fade into it.
func surface_color_at(x: float, z: float) -> Variant:
	var height = surface_height_at(x, z)
	if height == null:
		return null
	var local := global_transform.affine_inverse() * Vector3(x, float(height), z)
	var half := size * 0.5
	var column := clampi(roundi((local.x + half.x) / _step.x), 0, _columns - 1)
	var row := clampi(roundi((local.z + half.y) / _step.y), 0, _rows - 1)
	return _color_for(local.y, _lowest, _highest, _normal_in(_surface, column, row))


## Height in [param field] at a local position, by the mesh's own triangles.
func _height_in(field: PackedFloat32Array, local: Vector3) -> Variant:
	var half := size * 0.5
	var u := (local.x + half.x) / _step.x
	var v := (local.z + half.y) / _step.y
	if field.is_empty() or u < 0.0 or v < 0.0 or u > float(_columns - 1) \
			or v > float(_rows - 1):
		return null
	var column := mini(int(u), _columns - 2)
	var row := mini(int(v), _rows - 2)
	var across := u - float(column)
	var down := v - float(row)
	var index := row * _columns + column
	var h00 := field[index]
	var h10 := field[index + 1]
	var h01 := field[index + _columns]
	var h11 := field[index + _columns + 1]
	# The quad's two triangles meet along its h00-h11 diagonal.
	var height: float
	if down >= across:
		height = h00 + across * (h11 - h01) + down * (h01 - h00)
	else:
		height = h00 + across * (h10 - h00) + down * (h11 - h10)
	return (global_transform * Vector3(local.x, height, local.z)).y
#endregion


#region Shaping
## Everything [constant SHAPER_GROUP] asks for, as [code][cuts, holes][/code].
func _collect_shapes() -> Array:
	var cuts: Array[Dictionary] = []
	var holes: Array[Dictionary] = []
	if is_inside_tree():
		for node in get_tree().get_nodes_in_group(SHAPER_GROUP):
			if node.has_method(&"ground_cuts"):
				cuts.append_array(node.call(&"ground_cuts", self))
			if node.has_method(&"ground_holes"):
				holes.append_array(node.call(&"ground_holes", self))
	return [cuts, holes]


func _apply_shapes(shapes: Array) -> void:
	_surface = _heights.duplicate()
	_holes.clear()
	var to_local := global_transform.affine_inverse() if is_inside_tree() else Transform3D.IDENTITY
	for cut: Dictionary in shapes[0]:
		_carve(cut, to_local)
	for hole: Dictionary in shapes[1]:
		var local := _local_hole(hole, to_local)
		if local != null:
			_holes.append(local)
	_apron_surface = _surface.duplicate() if not _holes.is_empty() else PackedFloat32Array()
	for hole in _holes:
		_lower_apron(hole)


## Lowers [member _surface] to [param cut]'s line wherever it stands above it,
## within the line's half width plus a cell diagonal.
func _carve(cut: Dictionary, to_local: Transform3D) -> void:
	var points := PackedVector3Array()
	for point: Vector3 in cut["line"]:
		points.append(to_local * point)
	if points.size() < 2:
		return
	var reach := float(cut["half_width"]) + cell_diagonal()
	var half := size * 0.5
	var count := points.size() - 1
	var starts := PackedVector2Array()
	var directions := PackedVector2Array()
	var lengths := PackedFloat32Array()
	for i in count:
		var from := Vector2(points[i].x, points[i].z)
		var along := Vector2(points[i + 1].x, points[i + 1].z) - from
		starts.append(from)
		lengths.append(along.length())
		directions.append(along / maxf(along.length(), 1e-6))
	for i in count:
		var length := lengths[i]
		if length < 1e-4:
			continue
		var a := points[i]
		var b := points[i + 1]
		var lowest := minf(a.y, b.y)
		var columns := _grid_span(minf(a.x, b.x) - reach, maxf(a.x, b.x) + reach, half.x, _step.x, _columns)
		var rows := _grid_span(minf(a.z, b.z) - reach, maxf(a.z, b.z) + reach, half.y, _step.y, _rows)
		for row in range(rows.x, rows.y + 1):
			for column in range(columns.x, columns.y + 1):
				var index := row * _columns + column
				if _surface[index] <= lowest:
					continue
				var vertex := _grid_xz(column, row)
				var offset := vertex - starts[i]
				var along := offset.dot(directions[i])
				# Off this segment's ends a vertex is only this segment's to cut
				# in the wedge outside a bend, where neither neighbour reaches -
				# so past either end of the whole line, nothing is cut.
				if along < 0.0 and (i == 0 \
						or (vertex - starts[i - 1]).dot(directions[i - 1]) <= lengths[i - 1]):
					continue
				if along > length and (i == count - 1 \
						or (vertex - starts[i + 1]).dot(directions[i + 1]) >= 0.0):
					continue
				var t := clampf(along / length, 0.0, 1.0)
				if (offset - directions[i] * (t * length)).length() > reach:
					continue
				_surface[index] = minf(_surface[index], lerpf(a.y, b.y, t))


## The grid indices a local span [param from]..[param to] along one axis covers.
static func _grid_span(from: float, to: float, half: float, step: float, count: int) -> Vector2i:
	return Vector2i(clampi(floori((from + half) / step), 0, count - 1),
			clampi(ceili((to + half) / step), 0, count - 1))


## A [code]ground_holes[/code] entry in local space, with what cutting it needs:
## the bore's footprint as a polygon, its apron in front of the face, and the
## face's own frame in plan.
func _local_hole(hole: Dictionary, to_local: Transform3D) -> Hole:
	var line := PackedVector3Array()
	for point: Vector3 in hole["line"]:
		line.append(to_local * point)
	if line.size() < 2:
		return null
	var half_width := float(hole["half_width"])
	var lefts := PackedVector2Array()
	var rights := PackedVector2Array()
	for i in line.size():
		var from := line[maxi(i - 1, 0)]
		var to := line[mini(i + 1, line.size() - 1)]
		var inward := Vector2(to.x - from.x, to.z - from.z).normalized()
		var right := Vector2(-inward.y, inward.x)
		var middle := Vector2(line[i].x, line[i].z)
		lefts.append(middle - right * half_width)
		rights.append(middle + right * half_width)
	rights.reverse()
	var polygon := lefts.duplicate()
	polygon.append_array(rights)

	var local := Hole.new()
	local.line = line
	local.polygon = polygon
	local.bounds = _bounds_of(polygon)
	local.roof = float(hole["roof"])
	local.half_width = half_width
	local.bed = line[0].y
	local.face = Vector2(line[0].x, line[0].z)
	local.outward = -Vector2(line[1].x - line[0].x, line[1].z - line[0].z).normalized()
	local.across = Vector2(-local.outward.y, local.outward.x)
	var face := local.face
	var across := local.across
	var ahead := local.outward * apron_length()
	local.apron = PackedVector2Array([face - across * half_width, face + across * half_width,
			face + ahead + across * half_width, face + ahead - across * half_width])
	local.apron_bounds = _bounds_of(local.apron)
	return local


## The apron in front of a mouth's face lies on the bed: inside it the mesh is
## built from [member _apron_surface], where every vertex within a cell of the
## face - in front of it or behind - is lowered to the bed. Without that the
## cell straddling the face would rise from the bed to the hillside in front of
## the opening. Two cells out it is the ordinary surface again, so the apron's
## far edge meets the ground outside it; its sides and the face are where the
## portal's walls stand.
func _lower_apron(hole: Hole) -> void:
	var diagonal := cell_diagonal()
	var face := hole.face
	var outward := hole.outward
	var across := hole.across
	var reach := hole.half_width + diagonal
	var bed := hole.bed
	var half := size * 0.5
	var columns := _grid_span(face.x - reach - diagonal, face.x + reach + diagonal, half.x, _step.x, _columns)
	var rows := _grid_span(face.y - reach - diagonal, face.y + reach + diagonal, half.y, _step.y, _rows)
	for row in range(rows.x, rows.y + 1):
		for column in range(columns.x, columns.y + 1):
			var offset := _grid_xz(column, row) - face
			if absf(offset.dot(outward)) >= diagonal or absf(offset.dot(across)) > reach:
				continue
			var index := row * _columns + column
			_apron_surface[index] = minf(_apron_surface[index], bed)


## Height of a hole's roof over local [param point]: its line's height at the
## nearest point along it, plus the roof.
static func _roof_at(hole: Hole, point: Vector2) -> float:
	var line := hole.line
	var best := INF
	var height := line[0].y
	for i in line.size() - 1:
		var a := Vector2(line[i].x, line[i].z)
		var b := Vector2(line[i + 1].x, line[i + 1].z)
		var ab := b - a
		var t := clampf((point - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
		var distance := point.distance_squared_to(a + ab * t)
		if distance < best:
			best = distance
			height = lerpf(line[i].y, line[i + 1].y, t)
	return height + hole.roof


func _near_hole(rect: Rect2) -> bool:
	for hole in _holes:
		if hole.bounds.intersects(rect) or hole.apron_bounds.intersects(rect):
			return true
	return false


## One grid triangle near a tunnel mouth, cut up exactly: the parts inside an
## apron take their heights from [member _apron_surface], the part inside a
## bore's footprint and under its roof is left out, and the rest is the
## ordinary surface. Each part is a piece of the triangle's own plane in its
## field, so it meets the uncut triangles round it seamlessly.
func _add_clipped(corners: PackedInt32Array, grid: MeshSurface,
		apron_normals: PackedVector3Array, cut: MeshSurface) -> void:
	var triangle := PackedVector2Array()
	for corner in corners:
		triangle.append(Vector2(grid.vertices[corner].x, grid.vertices[corner].z))
	var bounds := _bounds_of(triangle)
	var plain: Array[PackedVector2Array] = [triangle]
	var aproned: Array[PackedVector2Array] = []
	for hole in _holes:
		if not hole.apron_bounds.intersects(bounds):
			continue
		var apron := hole.apron
		var outside: Array[PackedVector2Array] = []
		for piece in plain:
			for inside in Geometry2D.intersect_polygons(piece, apron):
				aproned.append(inside)
			outside.append_array(_subtract(piece, apron))
		plain = outside
	for hole in _holes:
		if not hole.bounds.intersects(bounds):
			continue
		# Where the triangle is under the roof: its height less the roof's is
		# linear across it, so that part is the triangle clipped to a line.
		var depth := PackedFloat32Array()
		for k in 3:
			depth.append(_surface[corners[k]] - _roof_at(hole, triangle[k]) + _ROOF_GAP)
		var below := PackedVector2Array()
		for k in 3:
			var next := (k + 1) % 3
			if depth[k] < 0.0:
				below.append(triangle[k])
			if (depth[k] < 0.0) != (depth[next] < 0.0):
				below.append(triangle[k].lerp(triangle[next], depth[k] / (depth[k] - depth[next])))
		if below.size() < 3:
			continue
		for footprint in Geometry2D.intersect_polygons(below, hole.polygon):
			var kept: Array[PackedVector2Array] = []
			for piece in plain:
				kept.append_array(_subtract(piece, footprint))
			plain = kept
	_emit(plain, triangle, corners, _surface, grid.normals, grid.colors, cut)
	_emit(aproned, triangle, corners, _apron_surface, apron_normals, grid.colors, cut)


## [param from] less [param cut]. Should [param cut] lie wholly inside it -
## which would leave a polygon with a hole, and triangulating that needs more
## than a list of outlines - [param from] is halved across [param cut] first.
static func _subtract(from: PackedVector2Array, cut: PackedVector2Array) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var clipped := Geometry2D.clip_polygons(from, cut)
	for polygon in clipped:
		if Geometry2D.is_polygon_clockwise(polygon):
			var box := _bounds_of(from).grow(1.0)
			var split := _bounds_of(cut).get_center().x
			for side in [Rect2(box.position, Vector2(split - box.position.x, box.size.y)),
					Rect2(Vector2(split, box.position.y), Vector2(box.end.x - split, box.size.y))]:
				var rect := side as Rect2
				var half_box := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y),
						rect.end, Vector2(rect.position.x, rect.end.y)])
				for half in Geometry2D.intersect_polygons(from, half_box):
					result.append_array(Geometry2D.clip_polygons(half, cut))
			return result
	result.assign(clipped)
	return result


## Triangulates [param pieces] of [param triangle] onto [param cut], heights,
## normals and colours interpolated across the triangle from [param field].
func _emit(pieces: Array[PackedVector2Array], triangle: PackedVector2Array,
		corners: PackedInt32Array, field: PackedFloat32Array, field_normals: PackedVector3Array,
		colors: PackedColorArray, cut: MeshSurface) -> void:
	for piece in pieces:
		if piece.size() < 3:
			continue
		var triangles := Geometry2D.triangulate_polygon(piece)
		for i in range(0, triangles.size() - 2, 3):
			var q0 := piece[triangles[i]]
			var q1 := piece[triangles[i + 1]]
			var q2 := piece[triangles[i + 2]]
			# The grid's winding: counter-clockwise seen with X right and Z down.
			var turn := (q1 - q0).cross(q2 - q0)
			# Clipping leaves slivers along its lines, a square centimetre or
			# less: nothing to see, and only noise to anything reading the mesh.
			if absf(turn) < 2e-4:
				continue
			var ordered := [q0, q1, q2] if turn > 0.0 else [q0, q2, q1]
			for q: Vector2 in ordered:
				var w := _barycentric(q, triangle)
				var height := w.x * field[corners[0]] + w.y * field[corners[1]] \
						+ w.z * field[corners[2]]
				cut.vertices.append(Vector3(q.x, height, q.y))
				cut.normals.append((field_normals[corners[0]] * w.x
						+ field_normals[corners[1]] * w.y + field_normals[corners[2]] * w.z).normalized())
				cut.colors.append(colors[corners[0]] * w.x + colors[corners[1]] * w.y
						+ colors[corners[2]] * w.z)


static func _barycentric(point: Vector2, triangle: PackedVector2Array) -> Vector3:
	var v0 := triangle[1] - triangle[0]
	var v1 := triangle[2] - triangle[0]
	var v2 := point - triangle[0]
	var d := v0.cross(v1)
	var w1 := v2.cross(v1) / d
	var w2 := v0.cross(v2) / d
	return Vector3(1.0 - w1 - w2, w1, w2)


static func _bounds_of(polygon: PackedVector2Array) -> Rect2:
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon:
		bounds = bounds.expand(point)
	return bounds
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
		_surface = PackedFloat32Array()
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
				height = _hill_height_at(-half.x + float(column) * _step.x,
						-half.y + float(row) * _step.y, hill_height)
			_heights[row * _columns + column] = height


## Local XZ of a grid vertex.
func _grid_xz(column: int, row: int) -> Vector2:
	var half := size * 0.5
	return Vector2(-half.x + float(column) * _step.x, -half.y + float(row) * _step.y)


func _grid_height(field: PackedFloat32Array, column: int, row: int) -> float:
	return field[clampi(row, 0, _rows - 1) * _columns + clampi(column, 0, _columns - 1)]


## [method _normal_in] at every grid point.
func _normals_in(field: PackedFloat32Array) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(_columns * _rows)
	for row in _rows:
		for column in _columns:
			normals[row * _columns + column] = _normal_in(field, column, row)
	return normals


func _normal_in(field: PackedFloat32Array, column: int, row: int) -> Vector3:
	var slope_x := (_grid_height(field, column + 1, row) - _grid_height(field, column - 1, row)) \
			/ (2.0 * _step.x)
	var slope_z := (_grid_height(field, column, row + 1) - _grid_height(field, column, row - 1)) \
			/ (2.0 * _step.y)
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


## Setters rebuild only inside the tree. Loading a scene assigns every exported
## property in turn, and rebuilding on each would build a baked terrain several
## times over before [method _ready] builds it once more anyway.
func _changed() -> void:
	if is_inside_tree():
		rebuild()

