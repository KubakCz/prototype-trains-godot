extends TestCase
## Folding the debug HUD: every section collapses to its header, its number key
## opens it, and clicking the header does the same.
##
## The readouts had grown to cover a good part of the screen, so the panels start
## folded and the fold has to keep working - a section that cannot be reopened is
## a section that has been deleted.
##
## Also the two things that replaced the sections' own keys: the cycle rows that
## carry the open presentation questions, and the ">" that marks whichever line
## the mouse is on.

var _scene: Node
var _overlay: MarkerOverlay
var _panels: Array[DebugPanel] = []


func before_each() -> void:
	_scene = await load_scene("res://scenes/main.tscn")
	_overlay = _scene.get_node("DebugUi/MarkerOverlay")
	_panels.clear()
	for child in _scene.get_node("DebugUi/Panels").get_children():
		if child is DebugPanel:
			_panels.append(child)


func test_a_scene_opens_with_every_section_folded() -> void:
	if not assert_eq(_panels.size(), 3, "main.tscn has three debug sections"):
		return
	for panel in _panels:
		assert_false(panel.expanded, "%s starts folded" % panel.name)
		assert_eq(panel.readout_text(), "", "%s shows no readout while folded" % panel.name)


## The numbers are read off the column rather than authored, so they always run
## down it in order and reordering the panels renumbers them.
func test_the_sections_are_numbered_down_the_column() -> void:
	var expected: Array[Key] = [KEY_1, KEY_2, KEY_3]
	for i in _panels.size():
		var panel := _panels[i]
		assert_eq(panel.fold_key(), expected[i],
				"%s folds on [%s]" % [panel.name, OS.get_keycode_string(expected[i])])
		note("%s -> [ %s ]" % [panel.name, OS.get_keycode_string(panel.fold_key())])


func test_a_number_key_opens_only_its_own_section() -> void:
	await _press(KEY_2)
	for panel in _panels:
		var wanted := panel == _panels[1]
		assert_eq(panel.expanded, wanted,
				"%s is %s after [2]" % [panel.name, "open" if wanted else "still folded"])
	assert_true(_panels[1].readout_text().contains("MainJunction"),
			"the open section shows its readout")
	await _press(KEY_2)
	assert_false(_panels[1].expanded, "[2] folds it again")


## The switches for the presentation questions steps 2 and 3 left open are rows
## in the body rather than keys, so they belong to the fold like the readout does:
## a shut section is a header and nothing else.
func test_the_cycle_rows_belong_to_the_body() -> void:
	for panel in _panels:
		assert_true(panel.control_buttons().is_empty(),
				"%s shows no cycle rows while folded" % panel.name)
	for panel in _panels:
		panel.expanded = true
	await frames(2)
	assert_eq(_panels[0].control_buttons().size(), 0,
			"the train section has nothing to cycle")
	assert_eq(_panels[1].control_buttons().size(), 1,
			"the turnout section cycles the overlay mode")
	assert_eq(_panels[2].control_buttons().size(), 2,
			"the signal section cycles the widget style and the collapse rule")


## What the rows are for. Pressing one has to move the overlay and say so in its
## own label, because the label is the only readout of what mode you are in.
func test_a_cycle_row_advances_the_overlay() -> void:
	for panel in _panels:
		panel.expanded = true
	await frames(2)
	var mode := _overlay.mode
	_panels[1].control_buttons()[0].pressed.emit()
	assert_ne(_overlay.mode, mode, "the turnout row cycled the overlay mode")
	assert_true(_panels[1].control_buttons()[0].text.contains(_overlay.mode_label()),
			"the row's label followed the change")
	note("overlay mode %s -> %s" % [MarkerOverlay.Mode.keys()[mode], _overlay.mode_label()])

	var style := _overlay.signal_style
	var rule := _overlay.collapse_rule
	_panels[2].control_buttons()[0].pressed.emit()
	_panels[2].control_buttons()[1].pressed.emit()
	assert_ne(_overlay.signal_style, style, "the first signal row cycled the widget style")
	assert_ne(_overlay.collapse_rule, rule, "the second cycled the collapse rule")


## The ">" marks whatever the mouse is on. With no select key there is nothing
## else it could sensibly mean, and a readout that marks nothing is a readout you
## have to find your line in by name.
func test_the_readout_marks_what_the_mouse_is_on() -> void:
	if not has_display():
		skip("no window (run with -Windowed)")
		return
	# Distance is irrelevant under this rule, so the widget is open whatever the
	# camera is doing, and its rect is a place the pointer can be put.
	_overlay.collapse_rule = MarkerOverlay.Collapse.WHEN_CROWDED
	var panel := _panels[2]
	panel.expanded = true
	await frames(4)

	var rail_signal: RailSignal = tree.get_nodes_in_group("signals")[0]
	var widget := _overlay.widget_for(rail_signal)
	if not assert_not_null(widget, "%s has a widget on screen" % rail_signal.name):
		return
	assert_eq(_marked_line(panel), "", "nothing is marked before the mouse arrives")

	await hover_at(widget.get_global_rect().get_center())
	note("marked line: '%s'" % _marked_line(panel))
	assert_true(_marked_line(panel).begins_with("> %s " % rail_signal.name),
			"the hovered signal's line is the marked one")

	var corner := tree.root.get_visible_rect().size - Vector2(8.0, 8.0)
	await hover_at(corner)
	assert_eq(_marked_line(panel), "", "the mark goes with the mouse")


## The point of the whole exercise: folded, the HUD is a stack of headers rather
## than three screenfuls of text.
func test_folding_shrinks_the_column() -> void:
	var column: Control = _panels[0].get_parent()
	await frames(2)
	var folded := column.size.y
	for panel in _panels:
		panel.expanded = true
	await frames(2)
	var open := column.size.y
	note("column %.0f px folded, %.0f px open" % [folded, open])
	assert_less(folded, open * 0.5, "the folded column is less than half the open one")


func test_a_click_on_a_header_folds_the_section() -> void:
	if not has_display():
		skip("no window (run with -Windowed)")
		return
	var panel := _panels[0]
	await frames(2)
	var header: Vector2 = panel.global_position + Vector2(40.0, panel.size.y * 0.5)
	await click_at(header)
	assert_true(panel.expanded, "the click on the header opened the section")
	await frames(2)
	# The header has moved with the panel's own growth, so ask again rather than
	# reusing the point that opened it.
	await click_at(panel.global_position + Vector2(40.0, 24.0))
	assert_false(panel.expanded, "a second click folded it")


func _press(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = keycode
		event.keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames(1)
	await frames(1)


## The one line of a readout that starts with the marker, or "" if none does.
func _marked_line(panel: DebugPanel) -> String:
	for line in panel.readout_text().split("\n"):
		if line.begins_with(">"):
			return line
	return ""
