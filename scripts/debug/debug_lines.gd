class_name DebugLines
extends RefCounted
## Shared plumbing for the unshaded line overlays drawn with an `ImmediateMesh`
## (rail arrows, turnout legs, signal markers, the train's stopping strip and
## car wireframes). Names no other class, so anything may use it.

static var _materials: Dictionary[bool, StandardMaterial3D] = {}


## Vertex-coloured, unshaded. [param see_through] skips the depth test so the
## overlay shows through the track and the ground it describes.
static func material(see_through: bool) -> StandardMaterial3D:
	if not _materials.has(see_through):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.disable_receive_shadows = true
		m.no_depth_test = see_through
		_materials[see_through] = m
	return _materials[see_through]


## One coloured segment; call between `surface_begin(PRIMITIVE_LINES, ...)`
## and `surface_end()`.
static func line(mesh: ImmediateMesh, from: Vector3, to: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(from)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(to)


## The internal child an overlay is drawn into, created on first use. Generated,
## so it is added with `INTERNAL_MODE_BACK` and never saved into the scene.
static func ensure_instance(owner: Node, existing: MeshInstance3D, node_name: String,
		top_level: bool) -> MeshInstance3D:
	if existing != null:
		return existing
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.top_level = top_level
	owner.add_child(instance, false, Node.INTERNAL_MODE_BACK)
	return instance
