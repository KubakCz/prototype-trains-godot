@tool
class_name TrainCar
extends Node3D
## One vehicle of a [Train], as drawn and as touched: a box, a load on top if it
## carries one, the front marker if it leads, a click target, and the box that
## collisions are tested against.
##
## Built and placed entirely by its train, as an internal child - never saved,
## never in the scene tree. [member Node3D.top_level], because the train writes
## every car straight into global space: each one is the chord between the rail
## positions under its own two ends, which is not something a child transform of
## the train could express.
##
## Origin on the railhead between the two ends, -Z towards the train's nose, the
## same frame the single-box train used to have.

## The left mouse button on this car. The train turns it into selection.
signal clicked

const _COLOR_WIRE := Color(1.0, 0.2, 0.85)
## How far the load block is inset from the wagon's sides and ends.
const _LOAD_INSET := 0.82
## Height of a full load. Half full is half as tall.
const _LOAD_HEIGHT := 1.1

var car_type: CarType
var length := 1.0
var width := 1.0
var height := 1.0

var _body: MeshInstance3D
var _load: MeshInstance3D
var _marker: MeshInstance3D
var _picker: StaticBody3D
var _picker_box: BoxShape3D
var _wire: MeshInstance3D
static var _wire_material: StandardMaterial3D


## Shapes the car for [param type]. The materials are the train's, shared by all of
## its cars, so recolouring a train is three material writes however long it is.
## [param load_fraction] is how full it is - only a wagon with a capacity shows a
## load at all - and [param leads] puts the front marker on it.
func build(type: CarType, leads: bool, load_fraction: float, body: Material,
		load_material: Material, marker: Material) -> void:
	car_type = type
	length = type.length
	width = type.width
	height = type.height
	top_level = true
	if _body == null:
		_body = _add_mesh("Body")
		_picker = StaticBody3D.new()
		_picker.name = "ClickTarget"
		_picker.input_ray_pickable = true
		var shape := CollisionShape3D.new()
		_picker_box = BoxShape3D.new()
		shape.shape = _picker_box
		_picker.add_child(shape)
		add_child(_picker)
		_picker.input_event.connect(_on_picker_input)

	var body_mesh := _body.mesh as BoxMesh
	body_mesh.size = Vector3(width, height, length)
	_body.position = Vector3(0.0, height * 0.5, 0.0)
	_body.material_override = body
	_picker_box.size = body_mesh.size
	_picker.position = _body.position

	var wagon := type as WagonType
	var carried := wagon != null and wagon.capacity > 0.0 and load_fraction > 0.0
	if carried and _load == null:
		_load = _add_mesh("Load")
	if _load != null:
		_load.visible = carried
		if carried:
			var load_height := _LOAD_HEIGHT * clampf(load_fraction, 0.05, 1.0)
			(_load.mesh as BoxMesh).size = Vector3(width * _LOAD_INSET, load_height,
					length * _LOAD_INSET)
			_load.position = Vector3(0.0, height + load_height * 0.5, 0.0)
			_load.material_override = load_material

	if leads and _marker == null:
		_marker = _add_mesh("NoseMarker")
	if _marker != null:
		_marker.visible = leads
		var marker_height := height * 0.25
		var marker_length := minf(length * 0.12, 2.0)
		(_marker.mesh as BoxMesh).size = Vector3(width * 0.75, marker_height, marker_length)
		# -Z is forward, so the marker sits over the front of the roof.
		_marker.position = Vector3(0.0, height + marker_height * 0.5,
				-length * 0.5 + marker_length * 0.5)
		_marker.material_override = marker
	_rebuild_wire()


#region Collision
## Half the size of the collision box: the body itself. A load on top is left out,
## since nothing can reach it that has not already hit the body under it.
func half_extents() -> Vector3:
	return Vector3(width, height, length) * 0.5


## Where the collision box is, in global space: centred in the body, with the
## car's own orientation, which on a derailed car is the wreck's.
func box_transform() -> Transform3D:
	return global_transform * Transform3D(Basis.IDENTITY, Vector3(0.0, height * 0.5, 0.0))


## Whether any part of this car is touching any part of [param other].
func touches(other: TrainCar) -> bool:
	return boxes_touch(box_transform(), half_extents(), other.box_transform(),
			other.half_extents())


## Separating-axis test for two oriented boxes: they overlap unless some axis -
## one of the six face normals, or one of the nine cross products of an edge from
## each - has their shadows apart. Exact, and in 3D, so a train on a bridge does
## not touch one passing through the tunnel under it.
static func boxes_touch(a: Transform3D, a_half: Vector3, b: Transform3D,
		b_half: Vector3) -> bool:
	var a_axes: Array[Vector3] = [a.basis.x.normalized(), a.basis.y.normalized(),
			a.basis.z.normalized()]
	var b_axes: Array[Vector3] = [b.basis.x.normalized(), b.basis.y.normalized(),
			b.basis.z.normalized()]
	var axes: Array[Vector3] = []
	axes.append_array(a_axes)
	axes.append_array(b_axes)
	for i in 3:
		for j in 3:
			var edge := a_axes[i].cross(b_axes[j])
			# Parallel edges give no axis; the face normals already cover them.
			if edge.length_squared() > 1e-8:
				axes.append(edge.normalized())
	var between := b.origin - a.origin
	for axis in axes:
		var a_reach := (a_half.x * absf(a_axes[0].dot(axis)) + a_half.y * absf(a_axes[1].dot(axis))
				+ a_half.z * absf(a_axes[2].dot(axis)))
		var b_reach := (b_half.x * absf(b_axes[0].dot(axis)) + b_half.y * absf(b_axes[1].dot(axis))
				+ b_half.z * absf(b_axes[2].dot(axis)))
		if absf(between.dot(axis)) > a_reach + b_reach:
			return false
	return true


## The collision box as a wireframe, for the train panel's collision-box row.
func show_box(shown: bool) -> void:
	if _wire != null and _wire.visible != shown:
		_wire.visible = shown


func _rebuild_wire() -> void:
	if _wire == null:
		_wire = MeshInstance3D.new()
		_wire.name = "CollisionBox"
		_wire.visible = false
		add_child(_wire)
	var mesh := ImmediateMesh.new()
	_wire.mesh = mesh
	var h := half_extents()
	var centre := Vector3(0.0, h.y, 0.0)
	var corners: Array[Vector3] = []
	for corner in 8:
		corners.append(centre + Vector3(h.x if (corner & 1) != 0 else -h.x,
				h.y if (corner & 2) != 0 else -h.y, h.z if (corner & 4) != 0 else -h.z))
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _get_wire_material())
	for corner in 8:
		for bit: int in [1, 2, 4]:
			# Each edge once: from the corner with the bit clear to the one with it set.
			if (corner & bit) == 0:
				mesh.surface_set_color(_COLOR_WIRE)
				mesh.surface_add_vertex(corners[corner])
				mesh.surface_set_color(_COLOR_WIRE)
				mesh.surface_add_vertex(corners[corner | bit])
	mesh.surface_end()


static func _get_wire_material() -> StandardMaterial3D:
	if _wire_material == null:
		_wire_material = StandardMaterial3D.new()
		_wire_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_wire_material.vertex_color_use_as_albedo = true
		_wire_material.vertex_color_is_srgb = true
		_wire_material.no_depth_test = true
	return _wire_material
#endregion


func _add_mesh(node_name: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = BoxMesh.new()
	add_child(instance)
	return instance


func _on_picker_input(_camera: Node, event: InputEvent, _at: Vector3, _normal: Vector3,
		_shape: int) -> void:
	if event.is_action_pressed(&"interact"):
		clicked.emit()
