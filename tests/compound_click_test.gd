extends CompoundDemoCase
## The two ways a player works an assembly, through the real input path: a click
## on any member's 3D marker, and a click on the assembly's one floating widget.
## Either cycles the whole assembly, and exactly once.
##
## Needs a window - skipped under --headless. Run it with `tests/run.ps1 -Windowed`.

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
	rig.position = scissors.centre()
	rig.yaw_degrees = -12.0
	rig.pitch_degrees = -40.0
	rig.zoom = 55.0
	rig._apply()


func test_a_click_on_one_members_marker_cycles_the_whole_assembly() -> void:
	_overlay.mode = MarkerOverlay.Mode.LEGS_3D
	await frames(4)
	var south_east := member(scissors, "SouthEast")
	var at := _camera.unproject_position(south_east.click_target_position())
	await click_at(at)
	note("clicked SouthEast's marker at %s: %s, members %s" % [at,
			scissors.position_label(scissors.compound_position), member_letters(scissors)])
	assert_eq(scissors.position_label(scissors.compound_position), "CROSS",
			"the click on one member crossed the assembly")
	assert_eq(member_letters(scissors), "RRRR", "all four members moved")


func test_a_click_on_the_widget_cycles_the_assembly_once() -> void:
	_overlay.mode = MarkerOverlay.Mode.LEGS_AND_SCHEMATIC
	await frames(4)
	var widget := _overlay.widget_for(scissors)
	if not assert_not_null(widget, "the scissors has a widget"):
		return
	if not assert_true(widget.visible and not widget.collapsed, "and it is open on screen"):
		return
	await click_at(widget.get_global_rect().get_center())
	# Once: the widget consumes the click, so a member's collider that happens to
	# lie under it does not cycle the assembly straight back.
	note("after the click: %s" % scissors.position_label(scissors.compound_position))
	assert_eq(scissors.position_label(scissors.compound_position), "CROSS",
			"the widget cycled the assembly exactly once")


func test_hovering_a_member_marker_is_reported_by_the_assembly() -> void:
	_overlay.mode = MarkerOverlay.Mode.LEGS_3D
	await frames(4)
	var north_west := member(scissors, "NorthWest")
	var on_marker: bool = await hover_probe(
			_camera.unproject_position(north_west.click_target_position()),
			scissors.is_pointer_over)
	assert_true(on_marker, "the pointer on NorthWest's marker counts as on the scissors")
