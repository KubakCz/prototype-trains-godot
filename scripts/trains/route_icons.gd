class_name RouteIcons
extends Node3D
## The first of the two ways a train's route is shown: a row of coloured shapes
## floating over the train, one for each stop still to come - a sphere for a station,
## a cube for a connection, in the colour of the point - with the next stop frontmost,
## over the nose end, and the last at the back.
##
## Belongs to its [Train] as an internal child and is placed from it every frame. The
## other way is the route list ([RouteListPanel]); [member mode] picks between them,
## and only one is showing at a time.

enum Mode {
	## The shapes over each train.
	ICONS,
	## The list panel, and nothing over the trains.
	LIST,
}

## Which way routes are shown. A debug panel row.
static var mode := Mode.ICONS

## Size of a shape, the gap between two, and how high the row floats over the rails.
const ICON_SIZE := 3.0
const SPACING := 4.2
const HEIGHT := 9.0
## The next stop is a little bigger than the rest.
const NEXT_SCALE := 1.3

var _train: Train
var _shapes: Array[MeshInstance3D] = []
var _points: Array[InterestPoint] = []


func _ready() -> void:
	top_level = true


## Attaches to [param train] and builds the row for its route.
func follow(train: Train) -> void:
	_train = train
	refresh()


## Builds the shapes again for the stops still to come.
func refresh() -> void:
	if _train == null:
		return
	for shape in _shapes:
		remove_child(shape)
		shape.queue_free()
	_shapes.clear()
	_points = _train.remaining_stops()
	for i in _points.size():
		var shape := MeshInstance3D.new()
		shape.name = "Stop%d" % i
		if _points[i].is_square():
			var box := BoxMesh.new()
			box.size = Vector3.ONE * ICON_SIZE
			shape.mesh = box
		else:
			var ball := SphereMesh.new()
			ball.radius = ICON_SIZE * 0.5
			ball.height = ICON_SIZE
			shape.mesh = ball
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		shape.material_override = material
		shape.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if i == 0:
			shape.scale = Vector3.ONE * NEXT_SCALE
		add_child(shape)
		_shapes.append(shape)
	_place()


func _process(_delta: float) -> void:
	_place()


## Number of shapes showing, for tests.
func shape_count() -> int:
	return _shapes.size()


func shapes() -> Array[MeshInstance3D]:
	return _shapes


func _place() -> void:
	if _train == null or not is_inside_tree():
		return
	visible = mode == Mode.ICONS and not _train.derailed and not _shapes.is_empty()
	if not visible:
		return
	global_transform = _train.global_transform
	var count := _shapes.size()
	for i in count:
		var shape := _shapes[i]
		# The first stop forward, towards -Z, the rest behind it, the row centred.
		shape.position = Vector3(0.0, HEIGHT, -(float(count - 1) * 0.5 - float(i)) * SPACING)
		(shape.material_override as StandardMaterial3D).albedo_color = _points[i].color()
