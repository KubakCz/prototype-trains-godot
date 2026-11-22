extends StationsDemoCase
## A train whose next stop is a station brakes to stand with its middle on the mark,
## dwells, does what the station does to its freight, and goes on - and a train whose
## next stop is anything else does not stop there at all.

func test_the_next_station_is_stopped_at_with_the_middle_on_the_mark() -> void:
	var train := make_train(express_type, north_line, 20.0, 1, stops([central, east_gate]))
	var reached := []
	train.reached.connect(func(point: InterestPoint) -> void: reached.append(point))
	var stopped := await drive_until(func() -> bool: return train.dwelling_at != null)
	assert_true(stopped, "the train comes to rest at the station")
	note("%s: at %.3f m, mark at 250, %s" % [train.name, train.distance, train.state_name()])
	assert_near(train.distance, 250.0, 0.02, "its middle is on the mark")
	assert_eq(train.current_speed, 0.0, "it is standing")
	assert_eq(train.state, Train.State.DWELLING, "the marker says it is dwelling")
	assert_eq(train.dwelling_at, central, "at Central Station")
	assert_eq(reached, [central], "reaching it was reported once")
	assert_eq(train.route_index, 1, "and the next stop is the gate")


func test_a_station_stops_the_train_whatever_the_signals_before_it_say() -> void:
	# The demo's signals are all at clear: nothing but the station can stop it here.
	var train := make_train(express_type, north_line, 20.0, 1, stops([central, east_gate]))
	await drive_until(func() -> bool: return train.dwelling_at != null)
	assert_null(train.blocking_signal, "it is not held by a signal")
	assert_eq(train.dwelling_at, central, "it is dwelling at the station")


func test_the_train_dwells_for_the_stations_time_and_then_goes_on() -> void:
	var train := make_train(express_type, north_line, 20.0, 1, stops([central, east_gate]))
	await drive_until(func() -> bool: return train.dwelling_at != null)
	var frames_dwelt := 0
	while train.dwelling_at != null and frames_dwelt < 2000:
		await physics_frames(1)
		frames_dwelt += 1
	note("dwelt %d frames, %.1f s" % [frames_dwelt, float(frames_dwelt) / 60.0])
	assert_between(float(frames_dwelt) / 60.0, central.dwell_time - 0.1, central.dwell_time + 0.1,
			"it stood for the station's dwell time")
	await drive(120)
	assert_greater(train.current_speed, 1.0, "then it is away again")
	assert_greater(train.distance, 252.0, "past the mark")
	assert_eq(train.state, Train.State.DRIVING, "driving")
	var stopped_again := await drive_until(func() -> bool: return train.dwelling_at != null, 600)
	assert_false(stopped_again, "it does not stop at the same station twice")


func test_a_station_that_is_not_the_next_stop_is_driven_through() -> void:
	var train := make_train(express_type, north_line, 20.0, 1, stops([east_gate]))
	var fastest := 0.0
	for i in 1500:
		await physics_frames(1)
		if train.distance > 235.0 and train.distance < 265.0:
			fastest = maxf(fastest, train.current_speed)
			assert_null(train.dwelling_at, "no stop at Central Station")
	assert_greater(fastest, 17.0, "it went through at line speed, %.1f m/s" % fastest)


func test_a_red_signal_before_the_station_still_holds_the_train() -> void:
	var signal_node: RailSignal = demo.get_node("Signals/WestNorth")
	signal_node.aspect = RailSignal.Aspect.DANGER
	var train := make_train(express_type, north_line, 20.0, 1, stops([central, east_gate]))
	await drive(900)
	assert_eq(train.blocking_signal, signal_node, "held at the red signal")
	assert_null(train.dwelling_at, "it never reached the station")
	assert_eq(train.route_index, 0, "so the station is still its next stop")


func test_a_train_too_fast_to_stop_in_time_passes_the_station() -> void:
	# 15 m short of the mark at 18 m/s: 27 m is what its brakes need at the very least.
	var train := make_train(express_type, north_line, 235.0, 1, stops([central, east_gate]))
	train.roll(18.0)
	await drive(240)
	assert_null(train.dwelling_at, "it is not dwelling")
	assert_eq(train.route_index, 0, "the station was missed")
	assert_greater(train.distance, 260.0, "and it is past")
	assert_false(train.tripped, "missing a station is not a fault")


func test_a_station_with_several_tracks_is_stopped_at_on_whichever_the_train_is_on() -> void:
	for line: Rail in [middle_line, south_line]:
		var train := make_train(local_type, line, 30.0, 1, stops([central, east_gate]), 1)
		await drive_until(func() -> bool: return train.dwelling_at != null)
		assert_eq(train.dwelling_at, central, "on %s it stops at Central Station" % line.name)
		assert_near(train.distance, 250.0, 0.02, "with its middle on %s's mark" % line.name)
		train.queue_free()
		await physics_frames(2)


func test_a_train_going_the_other_way_stops_on_the_same_mark() -> void:
	var train := make_train(local_type, south_line, 460.0, -1, stops([central, west_gate]), 1)
	await drive_until(func() -> bool: return train.dwelling_at != null)
	assert_near(train.distance, 250.0, 0.02, "a westbound train stands on the mark too")


func test_a_mine_fills_the_wagons_while_the_train_stands() -> void:
	var train := make_train(empty_type, south_line, 460.0, -1, stops([coal_mine, west_gate]), 3, 0.0)
	await drive_until(func() -> bool: return train.dwelling_at == coal_mine)
	assert_eq(train.load_factor, 0.0, "it arrives empty")
	var mass_before := train.total_mass()
	await physics_frames(int(coal_mine.dwell_time * 60.0 * 0.5))
	note("half way through the stop: load %.1f" % train.load_factor)
	assert_between(train.load_factor, 0.2, 0.8, "half full half way through")
	await drive_until(func() -> bool: return train.dwelling_at == null)
	assert_eq(train.load_factor, 1.0, "it leaves full")
	assert_greater(train.total_mass(), mass_before + 100.0, "and heavier")


func test_a_factory_empties_the_wagons() -> void:
	var train := make_train(loaded_type, north_line, 250.0, 1, stops([factory, east_gate]), 3, 1.0)
	await drive_until(func() -> bool: return train.dwelling_at == factory)
	assert_eq(train.load_factor, 1.0, "it arrives full")
	await drive_until(func() -> bool: return train.dwelling_at == null)
	assert_eq(train.load_factor, 0.0, "it leaves empty")


func test_a_station_that_does_nothing_leaves_the_load_alone() -> void:
	var train := make_train(loaded_type, north_line, 20.0, 1, stops([central, east_gate]), 3, 1.0)
	await drive_until(func() -> bool: return train.dwelling_at == central)
	await drive_until(func() -> bool: return train.dwelling_at == null)
	assert_eq(train.load_factor, 1.0, "a freight train stopping at a passenger station keeps its load")


func test_passenger_coaches_carry_nothing_to_load() -> void:
	var train := make_train(local_type, south_line, 460.0, -1, stops([coal_mine, west_gate]), 2)
	await drive_until(func() -> bool: return train.dwelling_at == coal_mine)
	await drive_until(func() -> bool: return train.dwelling_at == null)
	assert_eq(train.load_factor, 0.0, "a mine does nothing to a coach")


func test_stops_are_made_in_the_order_of_the_route() -> void:
	# Factory first, Central Station second: Central Station is passed first and
	# driven through, the factory is stopped at, and then the train carries on.
	var train := make_train(express_type, north_line, 20.0, 1, stops([factory, central, east_gate]))
	await drive_until(func() -> bool: return train.dwelling_at != null)
	assert_eq(train.dwelling_at, factory, "the first stop is the factory, not the station before it")
	assert_near(train.distance, 350.0, 0.02, "on its mark")
	assert_eq(train.next_stop(), central, "Central Station, behind it now, is what comes next")


func test_a_derailed_train_does_not_dwell_or_load() -> void:
	var train := make_train(empty_type, south_line, 460.0, -1, stops([coal_mine, west_gate]), 2)
	await drive_until(func() -> bool: return train.dwelling_at == coal_mine)
	train.derail("test")
	assert_null(train.dwelling_at, "a wreck is not dwelling")
	assert_eq(train.state, Train.State.DERAILED, "it is a wreck")
	await physics_frames(600)
	assert_eq(train.load_factor, 0.0, "and loads nothing")


func test_the_front_marker_is_cyan_while_dwelling() -> void:
	assert_eq(Train.state_color(Train.State.DWELLING), Color(0.2, 0.85, 1.0), "cyan")
	assert_false(Train.state_blinks(Train.State.DWELLING), "steady")
