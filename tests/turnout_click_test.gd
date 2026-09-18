extends TurnoutDemoCase
## Both routes into Turnout.throw_points: the collider on the 3D marker, and the
## floating widget over it. Clicks are fed through Input.parse_input_event, so GUI
## routing and physics object picking are both exercised for real.
##
## Needs a window - skipped under --headless. Run it with `tests/run.ps1 -Windowed`.
## Clicks go through TestCase.click_at, which converts the canvas coordinates
## unproject_position hands back into the window coordinates the input system wants,
## so the window may be any size.

var _overlay: MarkerOverlay
var _camera: Camera3D


func before_all() -> void:
	if not has_display():
		skip("no window (run with -Windowed)")


func before_each() -> void:
	await super.before_each()
	_overlay = demo.get_node("DebugUi/MarkerOverlay")
	_camera = demo.get_node("CameraRig/Camera3D")
	var rig: CameraRig = demo.get_node("CameraRig")
	rig.position = stub.points_position()
	rig.yaw_degrees = -18.0
	rig.pitch_degrees = -30.0
	rig.zoom = 40.0
	rig._apply()


func test_a_click_on_the_marker_throws_the_points() -> void:
	_overlay.mode = MarkerOverlay.Mode.LEGS_3D
	await _settle()
	# The click target sits beside the track on the branch side, on the ground
	# rather than at railhead height; see Turnout._rebuild_marker.
	var marker := stub.click_target_position()
	var before := stub.turnout_position
	await click_at(_camera.unproject_position(marker))
	note("clicked the marker at %s" % _camera.unproject_position(marker))
	assert_ne(stub.turnout_position, before, "the 3D click threw the points")


func test_a_click_on_empty_ground_throws_nothing() -> void:
	_overlay.mode = MarkerOverlay.Mode.LEGS_3D
	await _settle()
	var before := stub.turnout_position
	await click_at(Vector2(60.0, tree.root.get_visible_rect().size.y - 300.0))
	assert_eq(stub.turnout_position, before, "nothing was thrown")


func test_a_click_on_the_floating_widget_throws_the_points_once() -> void:
	_overlay.mode = MarkerOverlay.Mode.LEGS_AND_SCHEMATIC
	await _settle()
	var widget := _widget_for(stub)
	if not assert_not_null(widget, "StubPoints has a widget on screen"):
		return
	if not assert_true(widget.visible, "the widget is visible"):
		return

	var before := stub.turnout_position
	await click_at(widget.get_global_rect().get_center())
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


## The readouts mark whatever the mouse is on, and the 3D marker is half of what
## "on" means: the floating widget answers for its own rect, the model for its
## collider. In LEGS_3D there is no widget at all, so this is the collider alone.
func test_hovering_the_marker_is_reported_by_the_turnout() -> void:
	_overlay.mode = MarkerOverlay.Mode.LEGS_3D
	await _settle()
	var on_marker: bool = await hover_probe(
			_camera.unproject_position(stub.click_target_position()), stub.is_pointer_over)
	assert_true(on_marker, "the pointer is reported over StubPoints")
	var on_ground: bool = await hover_probe(
			Vector2(60.0, tree.root.get_visible_rect().size.y - 300.0), stub.is_pointer_over, 2)
	assert_false(on_ground, "and not over it from empty ground")


func _settle() -> void:
	await frames(4)
