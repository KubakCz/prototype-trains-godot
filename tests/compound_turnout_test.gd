extends CompoundDemoCase
## CompoundTurnout itself: what each kind's positions set its members to, the
## single control cycling them, a member thrown behind the assembly's back, the
## configuration warnings and the overlay showing one widget per assembly.


## Every kind's first position is every member normal.
func test_every_assembly_starts_in_its_first_position() -> void:
	for compound in compounds():
		note("%-10s %s  members %s" % [compound.name,
				compound.position_label(compound.compound_position), member_letters(compound)])
		assert_eq(compound.compound_position, 0, "%s starts in its first position" % compound.name)
		assert_eq(member_letters(compound), wanted_letters(compound, 0),
				"the members of %s are where that position wants them" % compound.name)
		assert_true(compound._get_configuration_warnings().is_empty(),
				"%s is configured without warnings" % compound.name)


## The assembly is the only way the player moves the points: its members are
## taken off the player and know which assembly they belong to.
func test_members_are_driven_by_their_assembly_not_the_player() -> void:
	for compound in compounds():
		for turnout in compound.members:
			assert_eq(turnout.assembly, compound, "%s knows it belongs to %s"
					% [turnout.name, compound.name])
			assert_false(turnout.player_operable, "%s is not player-operable on its own"
					% turnout.name)


func test_a_three_way_cycles_straight_left_right() -> void:
	var left := member(three_way, "LeftPoints")
	var right := member(three_way, "RightPoints")
	assert_eq(left.branch_side(), -1, "LeftPoints branches to the left")
	assert_eq(right.branch_side(), 1, "RightPoints branches to the right")
	assert_eq(three_way.three_way_member(-1), left, "the left branch is LeftPoints'")

	var expected: Array[Array] = [["LEFT", "RN"], ["RIGHT", "NR"], ["STRAIGHT", "NN"]]
	for wanted in expected:
		three_way.cycle()
		note("%-8s members %s" % [three_way.position_label(three_way.compound_position),
				member_letters(three_way)])
		assert_eq(three_way.position_label(three_way.compound_position), wanted[0],
				"the next click sets %s" % wanted[0])
		assert_eq(member_letters(three_way), wanted[1], "%s sets the members %s"
				% [wanted[0], wanted[1]])


func test_both_crossovers_cycle_between_parallel_and_cross() -> void:
	for compound: CompoundTurnout in [crossover, scissors]:
		var all_reverse := "R".repeat(compound.members.size())
		compound.cycle()
		note("%-9s %s members %s" % [compound.name,
				compound.position_label(compound.compound_position), member_letters(compound)])
		assert_eq(compound.position_label(compound.compound_position), "CROSS",
				"one click sets %s to cross" % compound.name)
		assert_eq(member_letters(compound), all_reverse, "every member is reverse")
		compound.cycle()
		assert_eq(compound.position_label(compound.compound_position), "PARALLEL",
				"a second click sets it back to parallel")
		assert_eq(member_letters(compound), "N".repeat(compound.members.size()),
				"every member is normal again")


func test_one_change_raises_one_position_changed() -> void:
	var raised := [0]
	scissors.position_changed.connect(func() -> void: raised[0] += 1)
	scissors.cycle()
	note("four members thrown, %d position_changed" % raised[0])
	assert_eq(raised[0], 1, "throwing four members is still one change of the assembly")


## Something other than the player may throw a member directly - step 9's
## interlocking, a test, a level script. The assembly does not fight it; it
## reports a combination it has no name for, and the next click starts over.
func test_a_member_thrown_behind_its_back_leaves_the_assembly_mixed() -> void:
	member(crossover, "NorthPoints").throw_points()
	note("members %s -> %s" % [member_letters(crossover),
			crossover.position_label(crossover.compound_position)])
	assert_eq(crossover.compound_position, CompoundTurnout.MIXED, "the assembly reads MIXED")
	assert_false(crossover.is_consistent(), "and says so")

	member(crossover, "SouthPoints").throw_points()
	assert_eq(crossover.position_label(crossover.compound_position), "CROSS",
			"throwing the other member too lands on a position it knows")

	member(crossover, "SouthPoints").throw_points()
	crossover.cycle()
	note("after a click from MIXED: members %s" % member_letters(crossover))
	assert_eq(crossover.compound_position, 0, "a click from MIXED goes to the first position")
	assert_eq(member_letters(crossover), "NN", "and puts every member where it says")


func test_an_assembly_the_player_may_not_operate_ignores_clicks() -> void:
	crossover.player_operable = false
	var widget := _overlay().widget_for(crossover)
	await frames(2)
	if not assert_not_null(widget, "the crossover has a widget"):
		return
	widget.activate()
	member(crossover, "NorthPoints").clicked.emit()
	assert_eq(crossover.compound_position, 0, "neither the widget nor a member click cycled it")


func test_misconfigured_assemblies_are_warned_about() -> void:
	var cases: Array[Array] = []
	var lone := CompoundTurnout.new()
	lone.kind = CompoundTurnout.Kind.CROSSOVER
	lone.members = [member(crossover, "NorthPoints")]
	cases.append([lone, "needs exactly 2"])

	var wrong_rails := CompoundTurnout.new()
	wrong_rails.kind = CompoundTurnout.Kind.THREE_WAY
	wrong_rails.members = [member(three_way, "LeftPoints"), member(crossover, "NorthPoints")]
	cases.append([wrong_rails, "same main rail"])

	var not_joined := CompoundTurnout.new()
	not_joined.kind = CompoundTurnout.Kind.CROSSOVER
	not_joined.members = [member(crossover, "NorthPoints"), member(scissors, "SouthEast")]
	cases.append([not_joined, "connecting rail"])

	var single_link := CompoundTurnout.new()
	single_link.kind = CompoundTurnout.Kind.DOUBLE_CROSSOVER
	single_link.members = [member(crossover, "NorthPoints"), member(crossover, "SouthPoints"),
			member(scissors, "NorthWest"), member(three_way, "LeftPoints")]
	cases.append([single_link, "connecting rail"])

	for entry in cases:
		var compound := entry[0] as CompoundTurnout
		var warnings := " | ".join(compound._get_configuration_warnings())
		note("%s: %s" % [CompoundTurnout.Kind.keys()[compound.kind], warnings])
		assert_true(warnings.contains(entry[1]), "a %s is warned about: '%s'"
				% [CompoundTurnout.Kind.keys()[compound.kind], entry[1]])
		compound.free()


## The single controlling element the plan asks for: one widget per assembly,
## none for its members, in every mode that shows turnout widgets at all.
func test_the_overlay_shows_one_widget_per_assembly_and_none_for_members() -> void:
	var overlay := _overlay()
	await frames(2)
	var compound_widgets := 0
	var turnout_widgets := 0
	for widget in overlay.widgets():
		if widget is CompoundTurnoutWidget:
			compound_widgets += 1
		elif widget is TurnoutWidget:
			turnout_widgets += 1
	note("%d assembly widgets, %d single-turnout widgets" % [compound_widgets, turnout_widgets])
	assert_eq(compound_widgets, compounds().size(), "each assembly has one widget")
	assert_eq(turnout_widgets, 0, "no member has a widget of its own")

	var widget := overlay.widget_for(scissors) as CompoundTurnoutWidget
	for mode in MarkerOverlay.Mode.size():
		overlay.mode = mode as MarkerOverlay.Mode
		await frames(2)
		note("%-18s suppressed %s  legs %s" % [overlay.mode_label(),
				widget.suppressed, scissors.debug_draw])
		assert_eq(widget.suppressed, mode == MarkerOverlay.Mode.LEGS_3D,
				"the widget is shown in %s unless that mode shows none" % overlay.mode_label())
		assert_eq(scissors.debug_draw, mode != MarkerOverlay.Mode.SCHEMATIC_ONLY,
				"the assembly's 3D routes follow %s" % overlay.mode_label())
		for turnout in scissors.members:
			assert_true(turnout._debug_mesh.mesh.get_surface_count() == 0,
					"%s leaves its legs to the assembly" % turnout.name)


## The caption is the same choice for an assembly as for a single turnout, and it
## names the assembly's own position rather than any member's.
func test_the_assembly_widget_follows_the_turnout_caption() -> void:
	var overlay := _overlay()
	var widget := overlay.widget_for(crossover) as CompoundTurnoutWidget
	if not assert_not_null(widget, "the crossover has a widget"):
		return
	var heights: Dictionary[TurnoutWidget.Caption, float] = {}
	for caption in TurnoutWidget.Caption.size():
		overlay.turnout_caption = caption as TurnoutWidget.Caption
		await frames(2)
		var text := widget._caption_text()
		note("%-16s '%s'  %s" % [overlay.turnout_caption_label(), text, widget.expanded_size()])
		assert_eq(widget.caption, overlay.turnout_caption, "the overlay pushed the caption")
		heights[overlay.turnout_caption] = widget.expanded_size().y
		var names := (caption == TurnoutWidget.Caption.TURNOUT_NAME
				or caption == TurnoutWidget.Caption.ALL)
		var positions := (caption == TurnoutWidget.Caption.TURNOUT_POSITION
				or caption == TurnoutWidget.Caption.ALL)
		assert_eq(text.contains(str(crossover.name)), names,
				"%s %s the name" % [overlay.turnout_caption_label(),
				"shows" if names else "leaves out"])
		assert_eq(text.contains("PARALLEL"), positions,
				"%s %s the position" % [overlay.turnout_caption_label(),
				"shows" if positions else "leaves out"])
	assert_less(heights[TurnoutWidget.Caption.NO_TEXT], heights[TurnoutWidget.Caption.ALL],
			"with no text the widget gives up the caption's strip")


func test_clicking_the_widget_cycles_the_assembly() -> void:
	await frames(2)
	var widget := _overlay().widget_for(three_way)
	if not assert_not_null(widget, "the three-way has a widget"):
		return
	widget.activate()
	assert_eq(three_way.position_label(three_way.compound_position), "LEFT",
			"the widget cycled the three-way")


## Any member's 3D marker is a way in, because the points really are there; it
## cycles the whole assembly rather than throwing only itself.
func test_a_click_on_any_member_cycles_the_whole_assembly() -> void:
	member(scissors, "SouthEast").clicked.emit()
	note("after a click on SouthEast: members %s" % member_letters(scissors))
	assert_eq(scissors.position_label(scissors.compound_position), "CROSS",
			"a click on one member crossed the whole assembly")
	assert_eq(member_letters(scissors), "RRRR", "every member moved, not just the one clicked")


## Worked in pairs, like the crossovers: both straight routes, or both slip roads.
func test_a_double_slip_cycles_straight_and_slip() -> void:
	note("%s members %s" % [double_slip.position_label(double_slip.compound_position),
			member_letters(double_slip)])
	assert_eq(double_slip.position_count(), 2, "two positions")
	assert_eq(double_slip.position_label(0), "STRAIGHT", "the first is both straight routes")
	assert_eq(member_letters(double_slip), "NNNN", "which is every member normal")
	double_slip.cycle()
	assert_eq(double_slip.position_label(double_slip.compound_position), "SLIP",
			"the second is both slip roads")
	assert_eq(member_letters(double_slip), "RRRR", "which is every member reverse")


func _overlay() -> MarkerOverlay:
	return demo.get_node("DebugUi/MarkerOverlay")
