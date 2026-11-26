@tool
class_name TracksideModel
extends RefCounted
## The clickable model a [Turnout] (its marker) and a [RailSignal] (its mast)
## stand beside the track: an internal [code]top_level[/code] root placed by
## [method Rail.ground_frame], a post, and a click target.
##
## Not built in the owner's own frame: that one is the rail's, so it leans with
## the gradient and the curve's tilt and sits on the railhead. The root stands
## upright on the ground instead, every height on it is measured from the railhead
## (hence [member lift]), and the post is stretched down to whatever ground it
## stands on.

## The player pressed [code]interact[/code] on the click target.
signal pressed

## Where the model stands, in global space. Kept rather than asked for again,
## because the ground query behind it is the one expensive part.
var frame := Transform3D.IDENTITY
## How far the railhead is above the ground at [member frame].
var lift := 0.0
## Whether the mouse is over the click target.
var pointer_over := false
var root: Node3D
var post: MeshInstance3D
var click_target: StaticBody3D


## Stands the model [param side_offset] metres to the right of [param rail] at
## [param distance], facing [param heading].
func place(rail: Rail, distance: float, heading: Vector3, side_offset: float) -> void:
	frame = rail.ground_frame(distance, heading, side_offset)
	lift = rail.sample_position(distance).y - frame.origin.y
	if root != null:
		root.global_transform = frame


## Creates the root as an internal child of [param owner], with the post in it.
func build(owner: Node3D, node_name: String, post_color: Color, post_width: float) -> Node3D:
	root = Node3D.new()
	root.name = node_name
	root.top_level = true
	owner.add_child(root, false, Node.INTERNAL_MODE_BACK)
	root.global_transform = frame
	post = add_box(root, "Post", post_color, Vector3(post_width, 1.0, post_width))
	return root


## The click target, last child of the root. Also switches on physics object
## picking, which is off by default and without which it never sees a click.
func add_click_target(shape: Shape3D) -> void:
	click_target = StaticBody3D.new()
	click_target.name = "ClickTarget"
	click_target.input_ray_pickable = true
	var collider := CollisionShape3D.new()
	collider.shape = shape
	click_target.add_child(collider)
	root.add_child(click_target)
	click_target.input_event.connect(_on_input_event)
	click_target.mouse_entered.connect(_set_pointer_over.bind(true))
	click_target.mouse_exited.connect(_set_pointer_over.bind(false))
	if not Engine.is_editor_hint():
		root.get_viewport().physics_object_picking = true


## Stretches the post from the ground up to [param top] above the railhead, but
## never shorter than [param min_height] where the ground stands above the track.
func stretch_post(top: float, min_height: float) -> void:
	var height := maxf(lift + top, min_height)
	var box := post.mesh as BoxMesh
	box.size = Vector3(box.size.x, height, box.size.z)
	post.position = Vector3(0.0, height * 0.5, 0.0)


static func add_box(parent: Node3D, node_name: String, color: Color,
		size: Vector3) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var box := BoxMesh.new()
	box.size = size
	instance.mesh = box
	instance.material_override = material
	parent.add_child(instance)
	return instance


func _on_input_event(_camera: Node, event: InputEvent, _at: Vector3, _normal: Vector3,
		_shape: int) -> void:
	if event.is_action_pressed(&"interact"):
		pressed.emit()


func _set_pointer_over(value: bool) -> void:
	pointer_over = value
