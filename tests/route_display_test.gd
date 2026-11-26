extends StationsDemoCase
## The two ways a route is shown - a row of flat icons over the locomotive and a list of
## trains - and the switch between them, plus the interest point panel.
##
## The icons are billboards placed on the idle frame, so these tests wait on idle
## frames, and the trains they make stand still: nothing here needs them to move except
## the test that drives one to its stop.

var _camera: Camera3D
var _rig: CameraRig


func before_each() -> void:
	await super.before_each()
	_rig = demo.get_node("CameraRig")
	_camera = demo.get_node("CameraRig/Camera3D")


func after_each() -> void:
	RouteIcons.mode = RouteIcons.Mode.ICONS
	InterestPoint.show_names = true


func _panel(script: GDScript) -> DebugPanel:
	var panel := script.new() as DebugPanel
	tree.root.add_child(panel)
	own(panel)
	panel.expanded = true
	return panel


## A standing train bound for [param route], on the north main by Central.
func _standing(route: Array[InterestPoint], facing := 1) -> Train:
	var train := make_train(express_type, north_main, 360.0, facing, route)
	train.throttle = 0
	return train


## Whether the corner of [param texture] is see-through: a circle's is, a square's not.
static func _corner_is_empty(texture: Texture2D) -> bool:
	return texture.get_image().get_pixel(1, 1).a < 0.1


## Which way the nose is from the middle of [param train] on screen: -1 left, 1 right.
func _nose_side_on_screen(train: Train) -> float:
	var nose := train.nose()
	var towards := _camera.unproject_position(nose.rail.sample_position(nose.distance)) \
			- _camera.unproject_position(train.global_position)
	return -1.0 if towards.x < 0.0 else 1.0


func test_the_icons_over_a_train_are_its_stops() -> void:
	var train := _standing(stops([central, halt, east_gate]))
	await frames(2)
	var icons := train.route_icons()
	if not assert_not_null(icons, "the train has a row of icons"):
		return
	assert_eq(icons.icon_count(), 3, "one for each stop to come")
	assert_eq(icons.points(), stops([central, halt, east_gate]), "in the order of the route")
	var sprites := icons.icons()
	for i in sprites.size():
		assert_eq(sprites[i].modulate, icons.points()[i].color(),
				"icon %d is in %s's colour" % [i, icons.points()[i].label()])
	assert_true(icons.visible, "and they are showing")


func test_a_station_is_a_circle_and_a_connection_a_square() -> void:
	var train := _standing(stops([central, halt, east_gate]))
	await frames(2)
	var sprites := train.route_icons().icons()
	if not assert_eq(sprites.size(), 3, "three icons"):
		return
	assert_eq(sprites[0].texture, sprites[1].texture, "two stations share the circle")
	assert_ne(sprites[0].texture, sprites[2].texture, "the gate's square is another picture")
	assert_true(_corner_is_empty(sprites[0].texture), "a station's icon has empty corners: a circle")
	assert_false(_corner_is_empty(sprites[2].texture), "a gate's has filled corners: a square")
	var other := make_train(local_type, south_main, 360.0, 1, stops([east_gate]), 1)
	other.throttle = 0
	await frames(2)
	assert_eq(other.route_icons().icons()[0].texture, sprites[2].texture,
			"every train's gate icon is the same square")


func test_the_icons_are_flat_billboards_with_no_text() -> void:
	var train := _standing(stops([central, east_gate]))
	await frames(2)
	for sprite in train.route_icons().icons():
		assert_eq(sprite.billboard, BaseMaterial3D.BILLBOARD_ENABLED, "%s faces the camera" % sprite.name)
		assert_true(sprite.fixed_size, "%s keeps one size on screen" % sprite.name)
		assert_true(sprite.no_depth_test, "%s is drawn over the scenery" % sprite.name)
	for node in train.route_icons().get_children(true):
		assert_true(node is Sprite3D, "%s under the icons is an icon, not a shape or a label" % node.name)


func test_the_row_floats_over_the_locomotive_not_the_middle_of_the_train() -> void:
	for facing: int in [1, -1]:
		var train := _standing(stops([central, east_gate]), facing)
		await frames(2)
		var icons := train.route_icons()
		var engine := train.cars()[0]
		var over := icons.global_position
		var flat := Vector2(over.x - engine.global_position.x, over.z - engine.global_position.z)
		note("facing %d: row at %s, engine at %s, middle at %s" % [facing, over,
				engine.global_position, train.global_position])
		assert_near(flat.length(), 0.0, 0.05, "facing %d: the row is straight over the locomotive" % facing)
		assert_near(over.y - engine.global_position.y, RouteIcons.HEIGHT, 0.05,
				"%.0f m up" % RouteIcons.HEIGHT)
		assert_greater(Vector2(over.x - train.global_position.x, over.z - train.global_position.z).length(),
				10.0,
				"facing %d: not over the middle of the %.0f m train" % [facing, train.train_length()])
		var nose := train.nose()
		assert_less(over.distance_to(nose.rail.sample_position(nose.distance) + Vector3.UP * RouteIcons.HEIGHT),
				25.0, "facing %d: it is at the nose end" % facing)
		train.queue_free()
		await frames(2)


func test_the_next_stop_is_the_bigger_icon_at_the_nose_end_of_the_row() -> void:
	for facing: int in [1, -1]:
		var train := _standing(stops([central, east_gate]), facing)
		await frames(3)
		var sprites := train.route_icons().icons()
		if not assert_eq(sprites.size(), 2, "two icons"):
			return
		assert_near(sprites[0].pixel_size / sprites[1].pixel_size, RouteIcons.NEXT_SCALE, 0.001,
				"the next stop is %.2f times the size of the rest" % RouteIcons.NEXT_SCALE)
		# An icon's offset is in its own texture's pixels; in metres it is that times
		# pixel_size, along the camera's right.
		var side := _nose_side_on_screen(train)
		var next_at := sprites[0].offset.x * sprites[0].pixel_size * side
		var then_at := sprites[1].offset.x * sprites[1].pixel_size * side
		note("facing %d: nose to the %s on screen, offsets %.2f / %.2f m" % [facing,
				"right" if side > 0 else "left", next_at, then_at])
		assert_greater(next_at, then_at, "facing %d: the next stop is at the end nearer the nose" % facing)
		train.queue_free()
		await frames(2)


func test_the_icons_keep_their_size_when_the_camera_moves() -> void:
	var train := _standing(stops([central, east_gate]))
	_rig.position = train.global_position
	_rig.zoom = 60.0
	_rig._apply()
	await frames(3)
	var near := train.route_icons().icons()[0].pixel_size
	_rig.zoom = 300.0
	_rig._apply()
	await frames(3)
	var far := train.route_icons().icons()[0].pixel_size
	note("pixel_size at 60 m %.6f, at 300 m %.6f" % [near, far])
	assert_near(far, near, near * 0.001, "a fixed-size icon needs no rescaling as the camera pulls back")


## UiScale puts the factor back to what the window's height calls for on every size
## change, and setting the factor is one - so it is unhooked while the test sets its own.
func test_the_icons_grow_with_the_ui_scale() -> void:
	var window := tree.root
	var ui_scale := window.get_node("UiScale")
	var reset := Callable(ui_scale, "_apply")
	var before := window.content_scale_factor
	var train := _standing(stops([central, east_gate]))
	await frames(3)
	var icons := train.route_icons()
	var at_one := icons.icons()[0].pixel_size
	if window.size_changed.is_connected(reset):
		window.size_changed.disconnect(reset)
	window.content_scale_factor = before * 2.0
	await frames(3)
	var held := window.content_scale_factor
	var at_two := icons.icons()[0].pixel_size
	window.content_scale_factor = before
	window.size_changed.connect(reset)
	await frames(2)
	note("pixel_size at UI scale %.2f: %.6f, at %.2f: %.6f" % [before, at_one, held, at_two])
	if not assert_near(held, before * 2.0, 0.001, "the doubled UI scale held long enough to measure"):
		return
	assert_near(at_two / at_one, 2.0, 0.01, "twice the UI scale, twice the icon")


func test_the_next_stop_leaves_the_row_when_it_is_reached() -> void:
	var train := make_train(express_type, north_main, 320.0, 1, stops([central, halt, east_gate]))
	await drive_until(func() -> bool: return train.dwelling_at != null)
	await frames(2)
	var icons := train.route_icons()
	assert_eq(icons.icon_count(), 2, "two stops are left")
	assert_eq(icons.points(), stops([halt, east_gate]), "the Halt and the gate")
	assert_true(_corner_is_empty(icons.icons()[0].texture), "the Halt, a circle, is next")


func test_a_train_without_a_route_shows_no_icons() -> void:
	var train := _standing(stops([]))
	await frames(2)
	assert_eq(train.route_icons().icon_count(), 0, "there are no icons")
	assert_false(train.route_icons().visible, "there is nothing to show")


func test_the_list_mode_takes_the_icons_off_the_trains() -> void:
	var train := _standing(stops([central, east_gate]))
	await frames(2)
	RouteIcons.mode = RouteIcons.Mode.LIST
	await frames(2)
	assert_false(train.route_icons().visible, "the icons are gone from over the train")
	RouteIcons.mode = RouteIcons.Mode.ICONS
	await frames(2)
	assert_true(train.route_icons().visible, "and back")


func test_a_wreck_shows_no_icons() -> void:
	var train := _standing(stops([central, east_gate]))
	await frames(2)
	train.derail("test")
	await frames(2)
	assert_false(train.route_icons().visible, "a derailed train is going nowhere")


func test_the_list_has_a_line_per_train_in_the_order_they_came() -> void:
	var panel := _panel(RouteListPanel) as RouteListPanel
	RouteIcons.mode = RouteIcons.Mode.LIST
	var first := make_train(express_type, north_main, 100.0, 1, stops([central, east_gate]))
	var second := make_train(local_type, south_main, 500.0, -1, stops([central, west_gate]), 1)
	var third := make_train(loaded_type, factory_siding, 60.0, 1, stops([factory, west_gate]), 3, 1.0)
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
	make_train(express_type, north_main, 100.0, 1, stops([central, east_gate]))
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
	var train := make_train(express_type, north_main, 100.0, 1, stops([central, east_gate]))
	train.livery = Livery.random(RandomNumberGenerator.new())
	panel.view().show_names = true
	await frames(4)
	assert_eq(panel.view().row_count(), 1, "the train is listed")


func test_the_interest_panel_lists_the_points_and_switches_the_names() -> void:
	var panel := _panel(InterestDebugPanel) as InterestDebugPanel
	await frames(2)
	var text := panel.readout_text()
	for point: InterestPoint in [west_gate, east_gate, central, mine, factory, halt]:
		assert_true(text.contains(point.label()), "%s is listed" % point.label())
	assert_true(text.contains("trains 0 / 4"), "with the spawner's count")
	assert_true(InterestPoint.show_names, "names start on")
	panel.control_buttons()[0].pressed.emit()
	assert_false(InterestPoint.show_names, "the row switches them off")


func test_the_train_panel_shows_the_route_and_the_engine() -> void:
	var train := make_train(express_type, north_main, 100.0, 1, stops([central, east_gate]))
	train.livery = Livery.new()
	var panel := _panel(load("res://scripts/debug/train_debug_panel.gd")) as DebugPanel
	await frames(2)
	var text := panel.readout_text()
	assert_true(text.contains("*Central > East"), "the next stop is starred: %s" % text)
