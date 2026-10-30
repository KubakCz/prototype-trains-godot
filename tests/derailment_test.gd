extends TrainDemoCase
## Everything that takes a train off the rails, and what does not: points thrown
## under it, points thrown against it too late to stop and the end of the line found
## too late, and two trains touching - head on, or fouling each other where two
## tracks converge. And trains that pass close by on parallel tracks, which must not.
##
## Derailing is final: a wreck stays where it came off whatever it is told.

const _UPRIGHT_TOLERANCE := 1.0


func test_points_thrown_under_a_train_derail_it() -> void:
	var points := north_points.points_distance()
	place_nose(express, north_line, points, 20.0, 10.0)
	assert_true(await drive_until(func() -> bool: return nose_short_of(express, points) < -10.0),
			"its nose gets 10 m past NorthPoints")
	var lead := express.cars()[0].global_position
	crossover.cycle()
	await drive(2)
	note(state(express))
	assert_true(express.derailed, "throwing the crossover under it derails it")
	assert_true(express.derail_reason.contains("Crossover/NorthPoints"),
			"and says which points did it: '%s'" % express.derail_reason)
	assert_eq(express.current_speed, 0.0, "it stops dead")
	assert_eq(express.state, Train.State.DERAILED, "its marker is black")
	assert_less(express.cars()[0].global_position.distance_to(lead), 0.6,
			"the wreck lies where the train was, not on the route the points went over to")
	_assert_a_wreck(express)
	await _assert_it_stays_put(express)


## Points set against a train are not braked for, however far off they are: it runs
## into them at speed and comes off there. Only a signal in front of them stops it.
func test_points_set_against_a_train_derail_it_when_it_gets_there() -> void:
	var points := middle_points.points_distance()
	place_nose(loaded_freight, middle_line, points, 90.0, 12.0)
	await drive(1)
	crossover.cycle()
	await drive(1)
	note("thrown 90 m short: %s" % state(loaded_freight))
	assert_false(loaded_freight.tripped, "it does not trip")
	assert_eq(loaded_freight.braking, 0.0, "nor brake")
	assert_eq(loaded_freight.state, Train.State.DRIVING, "green")
	await drive(600)
	note("then:              %s" % state(loaded_freight))
	assert_true(loaded_freight.derailed, "it ran into the points and came off")
	assert_true(loaded_freight.derail_reason.contains("ran into Crossover/MiddlePoints at 12 m/s"),
			"at full speed: '%s'" % loaded_freight.derail_reason)
	assert_near(nose_short_of(loaded_freight, points), 0.0, 0.05,
			"with its nose on the points")


func test_the_end_of_the_line_found_too_late_derails_it() -> void:
	var end := north_line.rail_length()
	place_nose(express, north_line, end, 15.0, 18.0)
	await drive(1)
	note("15 m from the end: %s" % state(express))
	assert_true(express.tripped, "it cannot stop in time")
	await drive(120)
	note("then:              %s" % state(express))
	assert_true(express.derailed, "it ran off the end")
	assert_true(express.derail_reason.contains("ran off the end of NorthLine"),
			"'%s'" % express.derail_reason)


func test_the_end_of_the_line_found_in_time_stops_it() -> void:
	express.end_behavior = Train.EndBehavior.STOP
	var end := north_line.rail_length()
	place_nose(express, north_line, end, 60.0, 18.0)
	await drive(400)
	note(state(express))
	assert_false(express.derailed, "it does not derail")
	assert_near(nose_short_of(express, end), Train.STOP_SHORT, 0.02,
			"it stops a few metres short of the end")
	assert_eq(express.state, Train.State.STOPPED, "and the placeholder end behaviour stops it")


func test_two_trains_that_touch_both_derail() -> void:
	south_stop.aspect = RailSignal.Aspect.CLEAR
	var stalled_nose := stalled.nose().distance
	place_nose(empty_freight, south_line, stalled_nose, 30.0, 8.0)
	var hit := await drive_until(func() -> bool: return empty_freight.derailed, 600)
	note("%s" % state(empty_freight))
	note("%s" % state(stalled))
	assert_true(hit, "the freight runs into the stalled train")
	assert_true(stalled.derailed, "and both come off")
	assert_true(empty_freight.derail_reason.contains("collided with Stalled"),
			"'%s'" % empty_freight.derail_reason)
	assert_true(stalled.derail_reason.contains("collided with EmptyFreight"),
			"'%s'" % stalled.derail_reason)
	assert_near(nose_short_of(empty_freight, stalled_nose), 0.0, 0.5,
			"they touched nose to nose")
	await _assert_it_stays_put(stalled)


## Touching is any part of one against any part of the other, not two trains on one
## rail: a train standing with its nose short of MiddlePoints fouls the link where
## it joins, and a train coming off the crossover hits it there.
func test_a_train_fouling_a_converging_track_is_hit() -> void:
	crossover.cycle()
	loaded_freight.rail = middle_line
	loaded_freight.distance = middle_points.points_distance() - 2.0 - loaded_freight.half_length()
	place_nose(express, north_line, north_points.points_distance(), 10.0, 8.0)
	var hit := await drive_until(func() -> bool: return express.derailed, 600)
	note("%s" % state(express))
	note("%s" % state(loaded_freight))
	assert_true(hit, "the express coming off the crossover hits the standing freight")
	assert_true(loaded_freight.derailed, "which comes off too")
	assert_eq(express.nose().rail, link, "the express was still on the link")


func test_trains_side_by_side_on_parallel_tracks_do_not_touch() -> void:
	place(express, north_line, 100.0, 18.0)
	place(loaded_freight, middle_line, 160.0, 12.0)
	place(empty_freight, south_line, 100.0, 12.0)
	# The express overtakes the loaded freight, and all three run up to their red
	# signals and stand there abreast.
	await drive(1500)
	for train in trains():
		note(state(train))
		assert_false(train.derailed, "%s is still on the rails" % train.name)


## A wreck is drawn knocked askew, and greyed.
func _assert_a_wreck(train: Train) -> void:
	var worst := 0.0
	for car in train.cars():
		worst = maxf(worst, rad_to_deg(car.global_basis.y.angle_to(Vector3.UP)))
	assert_greater(worst, _UPRIGHT_TOLERANCE, "its cars are knocked off upright (%.1f deg)" % worst)
	assert_less(train.body_color().s, 0.25, "and greyed")


## Nothing moves a wreck: not the throttle, not letting it go, not a rolling start.
func _assert_it_stays_put(train: Train) -> void:
	var was: Array[Transform3D] = []
	for car in train.cars():
		was.append(car.global_transform)
	train.throttle = 1
	train.release()
	train.roll(10.0)
	await drive(60)
	var moved := false
	for i in train.cars().size():
		moved = moved or not train.cars()[i].global_transform.is_equal_approx(was[i])
	assert_false(moved, "and stays exactly where it came off")
	assert_eq(train.current_speed, 0.0, "going nowhere")
