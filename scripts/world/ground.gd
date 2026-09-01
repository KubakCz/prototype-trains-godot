@tool
class_name Ground
extends MeshInstance3D
## Procedural, gently rolling base plate - the surface rails snap onto.
##
## Stand-in for whatever terrain solution the real game uses. [SurfaceSnapper]
## reads the generated triangles, so nothing else depends on the height function
## below; any mesh would do.

@export var size := Vector2(220.0, 180.0): set = _set_size
## Quads along each axis. Higher is smoother but slows snapping down, since
## snapping walks the triangles.
@export_range(2, 400, 1) var subdivisions := 90: set = _set_subdivisions
@export var hill_height := 2.2: set = _set_hill_height
@export_tool_button("Rebuild") var _rebuild_button := rebuild

const _COLOR_LOW := Color(0.30, 0.42, 0.24)
const _COLOR_HIGH := Color(0.55, 0.52, 0.35)


func _ready() -> void:
	if mesh == null:
		rebuild()


## Height of the terrain at a world XZ position.
static func height_at(x: float, z: float, amplitude: float) -> float:
	return amplitude * (sin(x * 0.06) * cos(z * 0.05) + 0.4 * sin(x * 0.13 + 1.3))


func rebuild() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := size * 0.5
	var step := size / float(subdivisions)

	for row in subdivisions:
		for column in subdivisions:
			var x0 := -half.x + float(column) * step.x
			var x1 := x0 + step.x
			var z0 := -half.y + float(row) * step.y
			var z1 := z0 + step.y
			# Two triangles per quad, wound so their normals point up. Get this
			# backwards and the terrain is invisible from above: still solid to
			# the snapper, but culled as backfaces by the renderer.
			_add_triangle(surface, x0, z0, x1, z1, x0, z1)
			_add_triangle(surface, x0, z0, x1, z0, x1, z1)

	surface.generate_normals()
	mesh = surface.commit()
	if material_override == null:
		material_override = _make_material()


func _add_triangle(surface: SurfaceTool, ax: float, az: float,
		bx: float, bz: float, cx: float, cz: float) -> void:
	for corner in [Vector2(ax, az), Vector2(bx, bz), Vector2(cx, cz)]:
		var y := height_at(corner.x, corner.y, hill_height)
		surface.set_color(_color_for_height(y))
		surface.add_vertex(Vector3(corner.x, y, corner.y))


func _color_for_height(y: float) -> Color:
	if is_zero_approx(hill_height):
		return _COLOR_LOW
	var t := inverse_lerp(-hill_height, hill_height, y)
	return _COLOR_LOW.lerp(_COLOR_HIGH, clampf(t, 0.0, 1.0))


func _make_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	# Vertex colours are consumed as linear unless this is set, which renders
	# anything authored by eye far darker and greyer than intended.
	material.vertex_color_is_srgb = true
	material.roughness = 0.95
	return material


func _set_size(value: Vector2) -> void:
	size = Vector2(maxf(value.x, 1.0), maxf(value.y, 1.0))
	rebuild()


func _set_subdivisions(value: int) -> void:
	subdivisions = maxi(value, 2)
	rebuild()


func _set_hill_height(value: float) -> void:
	hill_height = value
	rebuild()
