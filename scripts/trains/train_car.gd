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
## Origin on the railhead between the two ends, -Z towards the train's nose.
##
## The body rides [constant FLOOR_HEIGHT] above the rails on two bogies, whose
## wheelsets are set to standard gauge. The bogies are placed by the train
## straight onto the rail under them ([method place_bogies]), so on a curve they
## stay on the track while the body - a chord - swings out over it. The
## collision box and the click target still run from the railhead to the roof:
## a train touching another one at bogie height has still touched it.

## The left mouse button on this car. The train turns it into selection.
signal clicked

const _COLOR_WIRE := Color(1.0, 0.2, 0.85)
## How far the load block is inset from the wagon's sides and ends.
const _LOAD_INSET := 0.82
## How much of the body's height the livery stripe is.
const _STRIPE_SHARE := 0.3
## Height of a full load. Half full is half as tall.
const _LOAD_HEIGHT := 1.1
## Railhead to the underside of the body: the bogies fit under it.
const FLOOR_HEIGHT := 1.05
## Standard gauge, between the railheads' inner faces; the wheel treads sit on
## the middle of the railheads, half a railhead further out.
const GAUGE := 1.435
const _WHEEL_RADIUS := 0.45
const _WHEELBASE := 2.5
const _COLOR_BOGIE := Color(0.16, 0.16, 0.17)
const _COLOR_WHEEL := Color(0.42, 0.4, 0.38)

var car_type: CarType
var length := 1.0
var width := 1.0
var height := 1.0

var _body: MeshInstance3D
var _load: MeshInstance3D
var _marker: MeshInstance3D
var _stripe: MeshInstance3D
var _picker: StaticBody3D
var _picker_box: BoxShape3D
var _wire: MeshInstance3D
var _bogies: Array[MeshInstance3D] = []
static var _bogie_mesh: ArrayMesh


## Shapes the car for [param type]. The materials are the train's, shared by all of
## its cars, so recolouring a train is three material writes however long it is.
## [param load_fraction] is how full it is - only a wagon with a capacity shows a
## load at all - and [param leads] puts the front marker on it. A [param stripe]
## material puts a band of that colour round the middle of the body.
func build(type: CarType, leads: bool, load_fraction: float, body: Material,
		load_material: Material, marker: Material, stripe: Material = null) -> void:
	car_type = type
	length = type.length
	width = type.width
	height = type.height
	top_level = true
	_build_body(body, stripe)
	_build_bogies()
	_build_load(type as WagonType, load_fraction, load_material)
	_build_marker(leads, marker)
	_rebuild_wire()


## The body box and the click target, both the car's whole size.
func _build_body(body: Material, stripe: Material) -> void:
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
	var body_height := maxf(height - FLOOR_HEIGHT, 0.5)
	body_mesh.size = Vector3(width, body_height, length)
	_body.position = Vector3(0.0, height - body_height * 0.5, 0.0)
	_body.material_override = body
	_build_stripe(stripe, body_height)
	_picker_box.size = Vector3(width, height, length)
	_picker.position = Vector3(0.0, height * 0.5, 0.0)


func _build_bogies() -> void:
	if _bogies.is_empty():
		for i in 2:
			var bogie := MeshInstance3D.new()
			bogie.name = "Bogie%d" % i
			bogie.mesh = _get_bogie_mesh()
			# Placed in global space by the train, onto the rail under it.
			bogie.top_level = true
			add_child(bogie)
			_bogies.append(bogie)


## A block on the roof as tall as [param load_fraction] of a full load, on a wagon that
## carries anything.
func _build_load(wagon: WagonType, load_fraction: float, load_material: Material) -> void:
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


## The front marker over the front of the roof, on the car that [param leads].
func _build_marker(leads: bool, marker: Material) -> void:
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


## The band round the body: a thin box a little bigger than the body, so it shows on
## the sides and both ends and not on the roof.
func _build_stripe(material: Material, body_height: float) -> void:
	if material == null:
		if _stripe != null:
			_stripe.visible = false
		return
	if _stripe == null:
		_stripe = _add_mesh("Stripe")
	_stripe.visible = true
	var band := body_height * _STRIPE_SHARE
	(_stripe.mesh as BoxMesh).size = Vector3(width + 0.06, band, length + 0.06)
	_stripe.position = Vector3(0.0, height - body_height * 0.5, 0.0)
	_stripe.material_override = material


#region Bogies
## How far each bogie's pivot is in from its end of the car.
func bogie_inset() -> float:
	return clampf(length * 0.17, minf(1.9, length * 0.5), length * 0.5)


## Puts the two bogies onto the rail: [param front] and [param rear] are the
## track's frame under each pivot, as the train found it by walking.
func place_bogies(front: Transform3D, rear: Transform3D) -> void:
	if _bogies.size() == 2:
		_bogies[0].global_transform = front
		_bogies[1].global_transform = rear


## Leaves the bogies where they sit under the body - on a wreck, which is off
## the rails anyway.
func place_bogies_under_body() -> void:
	var offset := length * 0.5 - bogie_inset()
	place_bogies(global_transform * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -offset)),
			global_transform * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, offset)))


func bogies() -> Array[MeshInstance3D]:
	return _bogies


## One bogie, shared by every car: two side frames, a bolster for the body to
## sit on, and two wheelsets whose treads are on the railheads.
static func _get_bogie_mesh() -> ArrayMesh:
	if _bogie_mesh != null:
		return _bogie_mesh
	var frame := MeshSurface.new()
	var tread := GAUGE * 0.5 + TrackLayout.HEAD_WIDTH * 0.5
	for x: float in [-1.0, 1.0]:
		frame.add_box(Transform3D(Basis.IDENTITY, Vector3(x * (tread + 0.22), _WHEEL_RADIUS, 0.0)),
				Vector3(0.14, 0.4, _WHEELBASE + 0.6), _COLOR_BOGIE)
	frame.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.82, 0.0)),
			Vector3(tread * 2.0 + 0.6, 0.26, 0.6), _COLOR_BOGIE)
	for z: float in [-_WHEELBASE * 0.5, _WHEELBASE * 0.5]:
		frame.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, _WHEEL_RADIUS, z)),
				Vector3(tread * 2.0 + 0.3, 0.12, 0.12), _COLOR_BOGIE)
		for x: float in [-tread, tread]:
			_add_wheel(frame, Vector3(x, _WHEEL_RADIUS, z))
	_bogie_mesh = ArrayMesh.new()
	frame.commit(_bogie_mesh, TrackMaterials.metal())
	return _bogie_mesh


## A wheel as a twelve-sided disc turning about X.
static func _add_wheel(surface: MeshSurface, centre: Vector3) -> void:
	const SIDES := 12
	const HALF_WIDTH := 0.065
	for i in SIDES:
		var a := TAU * float(i) / float(SIDES)
		var b := TAU * float(i + 1) / float(SIDES)
		var ra := Vector3(0.0, sin(a), cos(a)) * _WHEEL_RADIUS
		var rb := Vector3(0.0, sin(b), cos(b)) * _WHEEL_RADIUS
		var side := Vector3(HALF_WIDTH, 0.0, 0.0)
		surface.add_quad_facing(centre + ra - side, centre + rb - side, centre + rb + side,
				centre + ra + side, (ra + rb) * 0.5, _COLOR_WHEEL)
		for x: float in [-1.0, 1.0]:
			surface.add_triangle_facing(centre + side * x, centre + ra + side * x,
					centre + rb + side * x, Vector3(x, 0.0, 0.0), _COLOR_WHEEL)
#endregion


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
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, DebugLines.material(true))
	for corner in 8:
		for bit: int in [1, 2, 4]:
			# Each edge once: from the corner with the bit clear to the one with it set.
			if (corner & bit) == 0:
				DebugLines.line(mesh, corners[corner], corners[corner | bit], _COLOR_WIRE)
	mesh.surface_end()
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
