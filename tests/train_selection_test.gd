extends TrainDemoCase
## Selecting a train, and the debug train panel's keys acting on whichever one is
## selected. Selection by clicking is in train_click_test.gd, which needs a window.

var _panel: DebugPanel


func before_each() -> void:
	await super.before_each()
	_panel = demo.get_node("DebugUi/Panels/TrainDebugPanel")


func after_each() -> void:
	# Selection is the class's, not the scene's, so it outlives the demo.
	Train.clear_selection()


func test_the_selected_train_is_lighter_blue() -> void:
	assert_null(Train.selected_train(), "nothing is selected to begin with")
	var normal := express.body_color()
	express.select()
	note("normal %s, selected %s" % [normal.to_html(false), express.body_color().to_html(false)])
	assert_eq(Train.selected_train(), express, "the express is selected")
	assert_greater(express.body_color().v, normal.v, "and drawn lighter")
	assert_greater(express.body_color().b, express.body_color().r, "but still blue")

	loaded_freight.select()
	assert_false(express.is_selected(), "selecting another train deselects it")
	assert_eq(express.body_color(), normal, "and it goes back to its own colour")
	Train.clear_selection()
	assert_null(Train.selected_train(), "and the selection can be cleared")
	assert_eq(loaded_freight.body_color(), normal, "leaving every train its own colour")


func test_the_keys_do_nothing_with_nothing_selected() -> void:
	assert_false(_panel._panel_key(KEY_SPACE), "Space is not taken")
	assert_eq(express.throttle, 0, "and nothing started")


func test_space_stops_and_starts_the_selected_train() -> void:
	express.select()
	assert_true(_panel._panel_key(KEY_SPACE), "Space is taken")
	assert_eq(express.throttle, 1, "it opens the throttle of a stopped train")
	assert_eq(loaded_freight.throttle, 0, "of the selected train only")
	_panel._panel_key(KEY_SPACE)
	assert_eq(express.throttle, 0, "and closes it again")


## The player's "let go" for an overrun is the same key as go.
func test_space_lets_a_tripped_train_go() -> void:
	var at := north_overrun.signal_distance()
	place_nose(express, north_line, at, 10.0, 18.0)
	north_overrun.aspect = RailSignal.Aspect.DANGER
	await drive(2)
	if not assert_true(express.tripped, "it overruns NorthOverrun"):
		return
	express.select()
	_panel._panel_key(KEY_SPACE)
	assert_false(express.tripped, "Space lets it go")
	assert_eq(express.throttle, 1, "with its throttle still open")


func test_the_consist_keys_change_the_selected_train() -> void:
	express.select()
	var wagons := express.wagons.size()
	_panel._panel_key(KEY_EQUAL)
	assert_eq(express.wagons.size(), wagons + 1, "[+] couples another coach on")
	_panel._panel_key(KEY_MINUS)
	_panel._panel_key(KEY_MINUS)
	assert_eq(express.wagons.size(), wagons - 1, "[-] takes them off again")

	loaded_freight.select()
	_panel._panel_key(KEY_L)
	assert_eq(loaded_freight.load_factor, 0.0, "[L] unloads a loaded train")
	_panel._panel_key(KEY_L)
	assert_eq(loaded_freight.load_factor, 1.0, "and loads it again")


func test_turning_round_waits_for_a_standstill() -> void:
	place(express, north_line, 120.0, 18.0)
	express.select()
	_panel._panel_key(KEY_F)
	assert_eq(express.facing, Train.ALONG_RAIL, "a moving train is not turned round")
	express.throttle = 0
	express.current_speed = 0.0
	_panel._panel_key(KEY_F)
	assert_eq(express.facing, Train.AGAINST_RAIL, "a standing one is")


func test_a_wreck_takes_no_keys() -> void:
	express.select()
	express.derail("test")
	assert_false(_panel._panel_key(KEY_SPACE), "Space does nothing to a derailed train")
	assert_eq(express.throttle, 0, "its throttle stays as it was")


func test_the_readout_follows_the_selection() -> void:
	_panel.expanded = true
	await frames(2)
	assert_true(_panel.readout_text().contains("click a train to select it"),
			"with nothing selected it says how to select")
	express.select()
	await frames(2)
	assert_true(_panel.readout_text().contains("selected: Express"), "then names the selection")
	assert_true(_panel.readout_text().contains("> Express"), "and marks it in the list")
