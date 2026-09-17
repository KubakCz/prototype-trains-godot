extends TurnoutDemoCase
## Both routes into Turnout.throw_points: the collider on the 3D marker, and the
## floating widget over it. Clicks are fed through Input.parse_input_event, so GUI
## routing and physics object picking are both exercised for real.
##
## Needs a window - skipped under --headless. Run it with `tests/run.ps1 -Windowed`,
## and do not resize the window: with window/stretch/mode = "canvas_items" a resized
## window leaves the 2D canvas at the project's base size while the 3D render target
## follows the window, so unproject_position and Input.parse_input_event end up in
## different coordinate spaces and every click misses.

var _overlay: TurnoutOverlay
var _camera: Camera3D


func before_all() -> void:
	if not has_display():
		skip("no window (run with -Windowed)")


func before_each() -> void:
	await super.before_each()
	_overlay = demo.get_node("DebugUi/TurnoutOverlay")
	_camera = demo.get_node("CameraRig/Camera3D")
	var rig: CameraRig = demo.get_node("CameraRig")
	rig.position = stub.points_position()
	rig.yaw_degrees = -18.0
	rig.pitch_degrees = -30.0
	rig.zoom = 40.0
	rig._apply()


func test_a_click_on_the_marker_throws_the_points() -> void:
	_overlay.mode = TurnoutOverlay.Mode.LEGS_3D
	await _settle()
	# The click target sits beside the track on the branch side; see
	# Turnout._rebuild_marker.
	var marker := stub.global_transform * Vector3(float(stub.branch_side()) * 2.4, 0.9, 0.0)
	var before := stub.turnout_position
	await _click(_camera.unproject_position(marker))
	note("clicked the marker at %s" % _camera.unproject_position(marker))
	assert_ne(stub.turnout_position, before, "the 3D click threw the points")


func test_a_click_on_empty_ground_throws_nothing() -> void:
	_overlay.mode = TurnoutOverlay.Mode.LEGS_3D
	await _settle()
	var before := stub.turnout_position
	await _click(Vector2(60.0, tree.root.get_visible_rect().size.y - 300.0))
	assert_eq(stub.turnout_position, before, "nothing was thrown")


func test_a_click_on_the_floating_widget_throws_the_points_once() -> void:
	_overlay.mode = TurnoutOverlay.Mode.LEGS_AND_SCHEMATIC
	await _settle()
	var widget := _widget_for(stub)
	if not assert_not_null(widget, "StubPoints has a widget on screen"):
		return
	if not assert_true(widget.visible, "the widget is visible"):
		return

	var before := stub.turnout_position
	await _click(widget.get_global_rect().get_center())
	# Once, not twice: a Control that calls accept_event() consumes the click
	# before picking sees it, which is what stops the widget and the 3D collider
	# under it both throwing the same points - if both fired, the position would
	# come straight back and this would read as unchanged.
	assert_ne(stub.turnout_position, before, "the widget threw the points exactly once")


func _widget_for(turnout: Turnout) -> TurnoutWidget:
	for child: Node in _overlay.get_children():
		var candidate := child as TurnoutWidget
		if candidate != null and candidate.turnout == turnout:
			return candidate
	return null


func _settle() -> void:
	await frames(4)


## A press and a release, pushed through the real input path.
func _click(at: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.position = at
		event.global_position = at
		Input.parse_input_event(event)
		await frames(1)
	await frames(1)
