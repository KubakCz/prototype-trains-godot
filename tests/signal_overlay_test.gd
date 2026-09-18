extends SignalDemoCase
## The floating layer: that signals and turnouts share one overlay, that widgets
## which would cover each other are shifted apart, that each of the three
## collapse rules does what it says, and that a signal's widget shows which
## direction it governs.
##
## Everything here is measured off the real [MarkerOverlay] running against the
## real camera, so it needs idle frames rather than physics frames - the overlay
## lays out in [method Node._process]. The fixture stops every train, so letting
## idle frames run does not move the level under the test.

var _overlay: MarkerOverlay
var _rig: CameraRig
var _camera: Camera3D


func before_each() -> void:
	await super.before_each()
	_overlay = demo.get_node("DebugUi/MarkerOverlay")
	_rig = demo.get_node("CameraRig")
	_camera = demo.get_node("CameraRig/Camera3D")
	_look_at_signals(70.0)


## Points the camera at the middle of the signalled stretch from [param zoom]
## metres out, and lets the overlay lay itself out again.
func _look_at_signals(zoom: float) -> void:
	_rig.position = (home.signal_position() + yard_b.signal_position()) * 0.5
	_rig.yaw_degrees = -16.0
	_rig.pitch_degrees = -30.0
	_rig.zoom = zoom
	_rig._apply()
	await _settle()


func _settle() -> void:
	await frames(3)


## Widgets that are actually on screen, which is the set the layout works on.
func _laid_out() -> Array[TrackMarkerWidget]:
	var found: Array[TrackMarkerWidget] = []
	for widget: TrackMarkerWidget in _overlay.widgets():
		if widget.visible:
			found.append(widget)
	return found


func _rect_of(widget: TrackMarkerWidget) -> Rect2:
	return Rect2(widget.position, widget.size * widget.scale)


func test_signals_and_turnouts_share_one_overlay() -> void:
	await _settle()
	var signal_widgets := 0
	var turnout_widgets := 0
	for widget: TrackMarkerWidget in _overlay.widgets():
		if widget is SignalWidget:
			signal_widgets += 1
		elif widget is TurnoutWidget:
			turnout_widgets += 1
	note("%d signal widgets, %d turnout widgets" % [signal_widgets, turnout_widgets])
	# One overlay rather than one each, because de-cluttering only works if it
	# knows about every widget on screen.
	assert_eq(signal_widgets, rail_signals().size(), "every signal has a widget")
	assert_eq(turnout_widgets, 1, "the turnout has one too, from the same overlay")


## The problem step 3 was asked to solve: three signals within eight metres of
## each other whose widgets, left alone, would sit on top of one another.
func test_widgets_that_would_cover_each_other_are_shifted_apart() -> void:
	_overlay.collapse_rule = MarkerOverlay.Collapse.WHEN_CROWDED
	await _look_at_signals(150.0)

	var viewport := _overlay.get_viewport_rect().size
	var moved := 0
	for widget: TrackMarkerWidget in _laid_out():
		var wanted := widget.desired_rect(viewport)
		if absf(widget.position.y - wanted.position.y) > 1.0:
			moved += 1
	note("%d of %d widgets on screen had to be moved off their own marker"
			% [moved, _laid_out().size()])
	assert_greater(float(moved), 1.0, "the crowded widgets were shifted out of each other's way")

	var overlaps := _count_overlaps()
	note("%d overlapping pairs after the layout" % overlaps)
	assert_eq(overlaps, 0, "no two widgets end up covering each other")


## Every pair of open badges that still intersects. Collapsed dots are left out
## on purpose: a dot sits on its own marker and takes no part in the layout, so
## two signals in the same place produce two dots in the same place, which is the
## truth rather than a clash.
func _count_overlaps() -> int:
	var open: Array[TrackMarkerWidget] = []
	for widget: TrackMarkerWidget in _laid_out():
		if not widget.collapsed:
			open.append(widget)
	var overlaps := 0
	for i in open.size():
		for j in range(i + 1, open.size()):
			if _rect_of(open[i]).intersects(_rect_of(open[j])):
				overlaps += 1
				note("  %s overlaps %s" % [open[i].name, open[j].name])
	return overlaps


func test_when_far_collapses_by_camera_distance() -> void:
	_overlay.collapse_rule = MarkerOverlay.Collapse.WHEN_FAR
	_overlay.collapse_distance = 1000.0
	await _look_at_signals(70.0)
	var near_widget := _overlay.widget_for(home)
	if not assert_not_null(near_widget, "Home has a widget"):
		return
	note("at %.0f m with a %.0f m threshold: collapsed=%s"
			% [near_widget.camera_distance, _overlay.collapse_distance, near_widget.collapsed])
	assert_false(near_widget.collapsed, "a widget inside the threshold stays expanded")

	_overlay.collapse_distance = 10.0
	await _settle()
	note("same widget with a %.0f m threshold: collapsed=%s"
			% [_overlay.collapse_distance, near_widget.collapsed])
	assert_true(near_widget.collapsed, "past the threshold it collapses to a point")
	assert_eq(near_widget.size, TrackMarkerWidget.COLLAPSED_SIZE,
			"and it is a dot's worth of screen rather than a badge's")


## Hovering always wins, whichever rule is in force - that is the whole point of
## a collapsed widget being a point you can open rather than a widget you lost.
func test_hovering_a_collapsed_widget_opens_it_again() -> void:
	_overlay.collapse_rule = MarkerOverlay.Collapse.WHEN_FAR
	_overlay.collapse_distance = 10.0
	await _settle()
	var widget := _overlay.widget_for(home)
	if not assert_not_null(widget, "Home has a widget"):
		return
	if not assert_true(widget.collapsed, "it starts collapsed"):
		return

	widget.mouse_entered.emit()
	await _settle()
	note("hovered: collapsed=%s size=%s" % [widget.collapsed, widget.size])
	assert_false(widget.collapsed, "hovering opens it")

	widget.mouse_exited.emit()
	await _settle()
	assert_true(widget.collapsed, "and it closes again when the mouse leaves")


func test_with_distance_shrinks_a_widget_and_then_collapses_it() -> void:
	_overlay.collapse_rule = MarkerOverlay.Collapse.WITH_DISTANCE
	_overlay.reference_distance = 55.0
	_overlay.min_scale = 0.6
	await _look_at_signals(55.0)
	var widget := _overlay.widget_for(home)
	if not assert_not_null(widget, "Home has a widget"):
		return
	var near_scale := widget.scale.x
	note("at %.0f m: scale %.2f, collapsed=%s"
			% [widget.camera_distance, near_scale, widget.collapsed])
	assert_between(near_scale, 0.6, 1.0, "close in, the widget is drawn at about full size")

	await _look_at_signals(400.0)
	note("at %.0f m: scale %.2f, collapsed=%s"
			% [widget.camera_distance, widget.scale.x, widget.collapsed])
	assert_true(widget.collapsed, "far out, it has shrunk past the floor and collapsed")


## The third rule: distance is not what decides anything, room on screen is.
func test_when_crowded_keeps_everything_that_fits_expanded() -> void:
	_overlay.collapse_rule = MarkerOverlay.Collapse.WHEN_CROWDED
	await _look_at_signals(400.0)
	var collapsed := 0
	for widget: TrackMarkerWidget in _laid_out():
		if widget.collapsed:
			collapsed += 1
	note("%d of %d widgets collapsed at %.0f m out"
			% [collapsed, _laid_out().size(), _overlay.widget_for(home).camera_distance])
	assert_eq(collapsed, 0, "distance alone never collapses anything under this rule")
	assert_eq(_count_overlaps(), 0, "and they are still kept out of each other's way")


## What [constant MarkerOverlay.Collapse.WHEN_CROWDED] does when shifting is not
## enough. Twenty signals within ten metres of each other is a taller column of
## badges than the screen can hold, and the ones that cannot be given a clear
## place collapse rather than being drawn on top of each other.
func test_when_crowded_collapses_what_it_cannot_fit() -> void:
	const CROWD := 20
	_overlay.collapse_rule = MarkerOverlay.Collapse.WHEN_CROWDED
	var host: Node = demo.get_node("Signals")
	for i in CROWD:
		var extra := RailSignal.new()
		extra.name = "Crowd%02d" % i
		extra.rail = main_line
		extra.distance = 120.0 + float(i) * 0.5
		host.add_child(extra)
		extra.add_to_group(&"signals")
	await _look_at_signals(60.0)

	var collapsed := 0
	for widget: TrackMarkerWidget in _laid_out():
		if widget.collapsed:
			collapsed += 1
	note("%d of %d widgets collapsed once %d signals stood on one spot"
			% [collapsed, _laid_out().size(), CROWD])
	assert_greater(float(collapsed), 0.0, "the ones with nowhere to go collapsed to points")
	assert_eq(_count_overlaps(), 0, "and nothing was left covering anything else")


## Draw order for a [Control] is child order, and a collapsed widget takes no
## part in the layout - so a dot happily lands on top of a badge. It has to be
## drawn *under* it: a dot behind a badge still says everything a dot has to say,
## while a badge behind a dot has lost its name, its aspect and its direction.
func test_a_collapsed_dot_is_drawn_under_an_open_badge() -> void:
	_overlay.collapse_rule = MarkerOverlay.Collapse.WHEN_FAR
	await _look_at_signals(90.0)
	# A threshold in the middle of the pack, so the same screen holds some of
	# each whatever the demo layout does next.
	var distances: Array[float] = []
	for widget: TrackMarkerWidget in _laid_out():
		distances.append(widget.camera_distance)
	distances.sort()
	if not assert_greater(float(distances.size()), 1.0, "several widgets are on screen"):
		return
	_overlay.collapse_distance = distances[distances.size() / 2]
	await _settle()

	var dots := 0
	var badges := 0
	var lowest_badge := _overlay.get_child_count()
	var highest_dot := -1
	for widget: TrackMarkerWidget in _laid_out():
		if widget.collapsed:
			dots += 1
			highest_dot = maxi(highest_dot, widget.get_index())
		else:
			badges += 1
			lowest_badge = mini(lowest_badge, widget.get_index())
	note("%d dots up to child %d, %d badges from child %d on"
			% [dots, highest_dot, badges, lowest_badge])
	if not assert_greater(float(dots * badges), 0.0, "the threshold left some of each"):
		return
	assert_less(float(highest_dot), float(lowest_badge), "every dot is drawn under every badge")


## The leader lines are the overlay's own draw rather than each widget's. A line
## drawn by a widget is drawn with that widget, so it crossed whatever badge
## happened to sit between the widget and its marker; drawn by the parent, every
## line is behind every badge on screen. What the widget still owns is where its
## line is attached.
func test_a_leader_line_leaves_the_widget_and_lands_on_its_marker() -> void:
	_overlay.collapse_rule = MarkerOverlay.Collapse.WHEN_FAR
	_overlay.collapse_distance = 1000.0
	await _settle()
	var widget := _overlay.widget_for(home)
	if not assert_not_null(widget, "Home has a widget"):
		return
	var rect := _rect_of(widget)
	note("leader %s -> %s, badge %s" % [widget.leader_start(), widget.leader_end(), rect])
	assert_between(widget.leader_start().x, rect.position.x, rect.end.x,
			"the line leaves the badge it belongs to")
	assert_near(widget.leader_start().y, rect.end.y, 0.01,
			"from its bottom edge, which is the side facing the track")
	assert_eq(widget.leader_end(), widget.anchor_screen, "and lands on the marker itself")


## A widget that only showed red or green would be telling half the story: the
## player has to know whether the red in front of them is theirs or the one
## facing the other way on the same piece of track.
func test_a_signal_widget_shows_which_way_its_signal_governs() -> void:
	await _settle()
	var forward := _overlay.widget_for(home) as SignalWidget
	var backward := _overlay.widget_for(home_back) as SignalWidget
	if not assert_not_null(forward, "Home has a widget"):
		return
	if not assert_not_null(backward, "HomeBack has a widget"):
		return
	var a := forward._screen_heading()
	var b := backward._screen_heading()
	note("Home points %s on screen, HomeBack points %s (dot %.2f)" % [a, b, a.dot(b)])
	assert_less(a.dot(b), -0.9,
			"the back-to-back pair's arrows point opposite ways on screen")
	assert_ne(forward._points_left(), backward._points_left(),
			"so the two badges are drawn pointing in opposite directions")
