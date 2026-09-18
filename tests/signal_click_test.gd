extends SignalDemoCase
## Both routes into [method RailSignal.toggle_aspect]: the collider on the mast,
## and the floating widget over it. Clicks are fed through
## [method Input.parse_input_event], so GUI routing and physics object picking
## are both exercised for real.
##
## Needs a window - skipped under --headless. Run it with
## [code]tests/run.ps1 -Windowed[/code]. Clicks go through [method TestCase.click_at],
## which converts the canvas coordinates [method Camera3D.unproject_position] hands
## back into the window coordinates the input system wants, so the window may be any
## size.

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
	rig.position = section.signal_position()
	rig.yaw_degrees = -18.0
	rig.pitch_degrees = -26.0
	rig.zoom = 34.0
	rig._apply()
	# Section stands on its own out past the turnout, so nothing else can be
	# under the cursor when its mast or its widget is clicked.
	_overlay.collapse_rule = MarkerOverlay.Collapse.WHEN_CROWDED


func test_a_click_on_the_mast_changes_the_aspect() -> void:
	await _settle()
	var mast := section.click_target_position()
	var before := section.aspect
	await click_at(_camera.unproject_position(mast))
	note("clicked the mast at %s" % _camera.unproject_position(mast))
	assert_ne(section.aspect, before, "the 3D click changed the signal")


func test_a_click_on_empty_ground_changes_nothing() -> void:
	await _settle()
	var before := section.aspect
	await click_at(Vector2(60.0, tree.root.get_visible_rect().size.y - 300.0))
	assert_eq(section.aspect, before, "nothing was changed")


func test_a_click_on_the_floating_widget_changes_the_aspect_once() -> void:
	await _settle()
	var widget := _overlay.widget_for(section)
	if not assert_not_null(widget, "Section has a widget on screen"):
		return
	if not assert_true(widget.visible and not widget.collapsed,
			"the widget is on screen and open"):
		return

	var before := section.aspect
	await click_at(widget.get_global_rect().get_center())
	# Once, not twice: a Control that calls accept_event() consumes the click
	# before picking sees it, which is what stops the widget and the mast's own
	# collider both acting on it - if both fired, the aspect would come straight
	# back and this would read as unchanged.
	assert_ne(section.aspect, before, "the widget changed the signal exactly once")


## A signal the level has taken off the player ignores clicks, which is how step
## 8's interlocking will hold one at danger.
func test_a_signal_the_player_cannot_operate_ignores_a_click() -> void:
	section.player_operable = false
	await _settle()
	var mast := section.click_target_position()
	var before := section.aspect
	await click_at(_camera.unproject_position(mast))
	assert_eq(section.aspect, before, "a signal with player_operable off does not budge")


## Same as the turnout's: the mast's collider is what tells the signal readout
## the mouse is on this signal rather than on its floating widget.
func test_hovering_the_mast_is_reported_by_the_signal() -> void:
	await _settle()
	var on_mast: bool = await hover_probe(
			_camera.unproject_position(section.click_target_position()),
			section.is_pointer_over)
	assert_true(on_mast, "the pointer is reported over Section")
	var on_ground: bool = await hover_probe(
			Vector2(60.0, tree.root.get_visible_rect().size.y - 300.0),
			section.is_pointer_over, 2)
	assert_false(on_ground, "and not over it from empty ground")


func _settle() -> void:
	await frames(4)
