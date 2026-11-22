extends StationsDemoCase
## The two ways a route is shown - a row of shapes over the train and a list of trains -
## and the switch between them, plus the interest point panel.


func after_each() -> void:
	RouteIcons.mode = RouteIcons.Mode.ICONS
	InterestPoint.show_names = true


func _panel(script: GDScript) -> DebugPanel:
	var panel := script.new() as DebugPanel
	tree.root.add_child(panel)
	own(panel)
	panel.expanded = true
	return panel


func test_the_icons_over_a_train_are_its_stops_with_the_next_one_in_front() -> void:
	var train := make_train(express_type, north_line, 100.0, 1, stops([central, east_gate]))
	await frames(2)
	var icons := train.route_icons()
	if not assert_not_null(icons, "the train has a row of icons"):
		return
	assert_eq(icons.shape_count(), 2, "one for each stop to come")
	var shapes := icons.shapes()
	assert_true(shapes[0].mesh is SphereMesh, "a circle for the station")
	assert_true(shapes[1].mesh is BoxMesh, "a square for the gate")
	assert_eq((shapes[0].material_override as StandardMaterial3D).albedo_color, central.color(),
			"in the station's colour")
	assert_eq((shapes[1].material_override as StandardMaterial3D).albedo_color, east_gate.color(),
			"and the gate's")
	var forward := -train.global_basis.z
	assert_greater(shapes[0].global_position.dot(forward), shapes[1].global_position.dot(forward),
			"the next stop is nearer the nose")
	assert_greater(shapes[0].global_position.y, train.global_position.y + 4.0, "they float over the train")
	assert_true(icons.visible, "and they are showing")


func test_the_next_stop_leaves_the_row_when_it_is_reached() -> void:
	var train := make_train(express_type, north_line, 100.0, 1, stops([central, east_gate]))
	await drive_until(func() -> bool: return train.dwelling_at != null)
	await frames(2)
	assert_eq(train.route_icons().shape_count(), 1, "one stop is left")
	assert_true(train.route_icons().shapes()[0].mesh is BoxMesh, "the gate")


func test_a_train_without_a_route_shows_no_icons() -> void:
	var train := make_train(express_type, north_line, 100.0, 1, stops([]))
	await frames(2)
	assert_false(train.route_icons().visible, "there is nothing to show")


func test_the_list_mode_takes_the_icons_off_the_trains() -> void:
	var train := make_train(express_type, north_line, 100.0, 1, stops([central, east_gate]))
	await frames(2)
	RouteIcons.mode = RouteIcons.Mode.LIST
	await frames(2)
	assert_false(train.route_icons().visible, "the shapes are gone from over the train")
	RouteIcons.mode = RouteIcons.Mode.ICONS
	await frames(2)
	assert_true(train.route_icons().visible, "and back")


func test_a_wreck_shows_no_icons() -> void:
	var train := make_train(express_type, north_line, 100.0, 1, stops([central, east_gate]))
	await frames(2)
	train.derail("test")
	await frames(2)
	assert_false(train.route_icons().visible, "a derailed train is going nowhere")


func test_the_list_has_a_line_per_train_in_the_order_they_came() -> void:
	var panel := _panel(RouteListPanel) as RouteListPanel
	RouteIcons.mode = RouteIcons.Mode.LIST
	var first := make_train(express_type, north_line, 100.0, 1, stops([central, east_gate]))
	var second := make_train(local_type, south_line, 400.0, -1, stops([central, west_gate]), 1)
	var third := make_train(loaded_type, middle_line, 100.0, 1, stops([factory, east_gate]), 3, 1.0)
	await frames(3)
	var view := panel.view()
	assert_true(view.visible, "the list is showing")
	assert_eq(view.rows(), [first, second, third] as Array[Train], "oldest at the top")
	assert_greater(view.custom_minimum_size.y, view.row_count() * RouteListView.ROW_HEIGHT - 1.0,
			"with room for every line")
	second.queue_free()
	await frames(3)
	assert_eq(view.rows(), [first, third] as Array[Train], "a train that leaves drops off the list")


func test_the_panel_row_switches_between_the_icons_and_the_list() -> void:
	var panel := _panel(RouteListPanel) as RouteListPanel
	await frames(2)
	assert_eq(RouteIcons.mode, RouteIcons.Mode.ICONS, "the icons are the default")
	assert_false(panel.view().visible, "and the list is hidden")
	panel.control_buttons()[0].pressed.emit()
	await frames(2)
	assert_eq(RouteIcons.mode, RouteIcons.Mode.LIST, "the first row switches to the list")
	assert_true(panel.view().visible, "which shows")
	panel.control_buttons()[0].pressed.emit()
	assert_eq(RouteIcons.mode, RouteIcons.Mode.ICONS, "and back")


func test_the_list_can_name_its_stops() -> void:
	var panel := _panel(RouteListPanel) as RouteListPanel
	RouteIcons.mode = RouteIcons.Mode.LIST
	make_train(express_type, north_line, 100.0, 1, stops([central, east_gate]))
	await frames(3)
	var narrow := panel.view().custom_minimum_size.x
	panel.control_buttons()[1].pressed.emit()
	await frames(3)
	assert_true(panel.view().show_names, "the second row turns the names on")
	# By how much depends on the font the display server hands out - it was exactly 40 px
	# under Xvfb - so only that it grew.
	assert_greater(panel.view().custom_minimum_size.x, narrow + 3.0, "and the list is wider for them")


func test_the_list_is_drawn() -> void:
	# Drawing is the one thing a headless run cannot look at; it can at least run it.
	var panel := _panel(RouteListPanel) as RouteListPanel
	RouteIcons.mode = RouteIcons.Mode.LIST
	var train := make_train(express_type, north_line, 100.0, 1, stops([central, east_gate]))
	train.livery = Livery.random(RandomNumberGenerator.new())
	panel.view().show_names = true
	await frames(4)
	assert_eq(panel.view().row_count(), 1, "the train is listed")


func test_the_interest_panel_lists_the_points_and_switches_the_names() -> void:
	var panel := _panel(InterestDebugPanel) as InterestDebugPanel
	await frames(2)
	var text := panel.readout_text()
	for point in [west_gate, east_gate, central, coal_mine, factory]:
		assert_true(text.contains(point.label()), "%s is listed" % point.label())
	assert_true(text.contains("trains 0 / 6"), "with the spawner's count")
	assert_true(InterestPoint.show_names, "names start on")
	panel.control_buttons()[0].pressed.emit()
	assert_false(InterestPoint.show_names, "the row switches them off")


func test_the_train_panel_shows_the_route_and_the_engine() -> void:
	var train := make_train(express_type, north_line, 100.0, 1, stops([central, east_gate]))
	train.livery = Livery.new()
	var panel := _panel(load("res://scripts/debug/train_debug_panel.gd")) as DebugPanel
	await frames(2)
	var text := panel.readout_text()
	assert_true(text.contains("*Central Station > East Gate"), "the next stop is starred: %s" % text)
