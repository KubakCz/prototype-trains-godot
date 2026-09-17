extends TurnoutDemoCase
## Driving the shuttle through every case in the passage table, plus the two cases
## that only exist once a train has length: a body drawn as a chord across two
## rails, and points thrown under it.
##
## Distances are in metres and time is in physics frames - the shuttle runs at
## 16 m/s, so 60 frames is 16 m of track. Each test gets its own copy of the demo
## scene with every train stopped.


func test_it_runs_the_main_line_and_stops_at_the_dead_end() -> void:
	set_points(Turnout.Position.NORMAL, Turnout.Position.NORMAL, Turnout.Position.NORMAL)
	place_shuttle(main_line, 20.0, Train.ALONG_RAIL)
	shuttle.end_behavior = Train.EndBehavior.STOP
	await drive(900)
	note(shuttle_state())

	# at_dead_end is cleared once the throttle drops, by design: a stopped train is
	# not being held by anything. STOP having fired is the lasting evidence.
	assert_eq(shuttle.rail, main_line, "it never left the main line")
	assert_eq(shuttle.throttle, 0, "it stopped at the east dead end")
	assert_near(shuttle.distance, main_line.rail_length() - 8.0, 0.2,
			"it stopped with its nose on the rail end, half a body behind it")


func test_a_facing_move_puts_it_on_the_loop_and_the_far_points_hold_it() -> void:
	set_points(Turnout.Position.REVERSE, Turnout.Position.NORMAL, Turnout.Position.NORMAL)
	place_shuttle(main_line, 20.0, Train.ALONG_RAIL)
	shuttle.end_behavior = Train.EndBehavior.STOP

	await drive(200)
	note("after diverging: %s" % shuttle_state())
	assert_eq(shuttle.rail, loop_line, "the facing move at LoopWest put it on the loop")
	assert_eq(shuttle.facing, Train.ALONG_RAIL, "its nose still points the way it was going")

	await drive(700)
	note("at the far end:  %s" % shuttle_state())
	assert_eq(shuttle.blocking_turnout, east, "it is held by LoopEast, which is set against it")
	# Held, not stopped: the throttle stays open so it rolls the instant the points
	# are thrown.
	assert_eq(shuttle.throttle, 1, "its throttle is still open while held")
	assert_near(shuttle.distance, loop_line.rail_length() - 8.0, 0.2,
			"it waits with its nose on the points, not past them")

	var held_at := shuttle.distance
	await drive(60)
	assert_near(shuttle.distance, held_at, 1e-3, "it stays put while held")

	east.throw_points()
	await drive(120)
	note("after throwing:  %s" % shuttle_state())
	assert_eq(shuttle.rail, main_line, "it rolled on to the main line once LoopEast was thrown")
	assert_null(shuttle.blocking_turnout, "nothing is holding it any more")
	assert_eq(shuttle.facing, Train.ALONG_RAIL, "it is still nose-east after rejoining")


func test_a_trailing_move_is_refused_by_points_set_to_the_branch() -> void:
	set_points(Turnout.Position.NORMAL, Turnout.Position.NORMAL, Turnout.Position.REVERSE)
	place_shuttle(main_line, 20.0, Train.ALONG_RAIL)
	shuttle.end_behavior = Train.EndBehavior.STOP

	await drive(700)
	note(shuttle_state())
	assert_eq(shuttle.blocking_turnout, east,
			"it is held on LoopEast's through leg with the points reverse")
	assert_eq(shuttle.rail, main_line, "it never left the main line")

	east.throw_points()
	await drive(120)
	note("after throwing:  %s" % shuttle_state())
	assert_null(shuttle.blocking_turnout, "the trailing move is admitted once the points are normal")
	assert_greater(shuttle.distance, 175.0, "it carried straight on past the points")


func test_it_can_run_into_the_dead_end_siding_and_back_out() -> void:
	set_points(Turnout.Position.NORMAL, Turnout.Position.REVERSE, Turnout.Position.NORMAL)
	place_shuttle(main_line, 20.0, Train.ALONG_RAIL)
	shuttle.end_behavior = Train.EndBehavior.TURN_AROUND

	await drive(500)
	note("in the siding:   %s" % shuttle_state())
	assert_eq(shuttle.rail, stub_line, "it diverged into the stub siding")

	await drive(200)
	note("at the buffers:  %s" % shuttle_state())
	assert_eq(shuttle.rail, stub_line, "it is still in the siding")
	# end_behavior now fires only at a genuine dead end - a rail end with no
	# turnout attached - which is exactly what the buffer stop here is.
	assert_eq(shuttle.facing, Train.AGAINST_RAIL, "it turned around at the buffer stop")

	await drive(400)
	note("coming back:     %s" % shuttle_state())
	assert_eq(shuttle.rail, main_line, "it trailed back out through the reverse points")


func test_it_is_held_inside_the_siding_by_points_set_against_it() -> void:
	place_shuttle(stub_line, stub_line.rail_length() - 8.0, Train.AGAINST_RAIL)
	shuttle.end_behavior = Train.EndBehavior.STOP
	stub.turnout_position = Turnout.Position.NORMAL

	await drive(400)
	note(shuttle_state())
	assert_eq(shuttle.blocking_turnout, stub, "it is held inside the siding by StubPoints normal")

	stub.throw_points()
	await drive(200)
	note("after throwing:  %s" % shuttle_state())
	assert_eq(shuttle.rail, main_line, "it came out onto the main line")
	assert_eq(shuttle.facing, Train.AGAINST_RAIL, "it came out nose-west, the way it was pointing")


func test_the_body_spans_two_rails_while_it_crosses_the_points() -> void:
	if not await _drive_until_spanning():
		fail("the body spans two rails while passing the points",
				"nose and tail stayed on one rail for the whole run")
		return
	var nose := shuttle_nose()
	var tail := shuttle_tail()
	var chord := tail.rail.sample_position(tail.distance).distance_to(
			nose.rail.sample_position(nose.distance))
	note("tail on %s @ %.1f m, nose on %s @ %.1f m, chord %.2f m"
			% [tail.rail.name, tail.distance, nose.rail.name, nose.distance, chord])
	assert_near(chord, shuttle.body_length, 0.5,
			"the body is drawn as a full-length chord across two rails")


## Throwing points under a train is allowed for now - step 8 is what locks them.
## The body visibly kinks onto the other route, which is expected; what must not
## happen is a stuck or teleported train.
func test_points_thrown_under_a_train_leave_it_running() -> void:
	if not await _drive_until_spanning():
		skip("never caught the train straddling the points")
		return
	var was := shuttle.global_position
	west.throw_points()
	await drive(30)
	var moved := was.distance_to(shuttle.global_position)
	note("thrown under the train: moved %.2f m in 30 frames, now on %s"
			% [moved, shuttle.rail.name])
	assert_true(shuttle.global_position.is_finite(), "its position is still finite")
	# 30 frames at 16 m/s is 8 m; anything in this band is running rather than
	# stuck or flung down the line.
	assert_between(moved, 1.0, 20.0, "it keeps running at roughly its own speed")


## Sends the shuttle at the west points and stops the moment its two ends are on
## two different rails.
func _drive_until_spanning() -> bool:
	set_points(Turnout.Position.REVERSE, Turnout.Position.NORMAL, Turnout.Position.NORMAL)
	place_shuttle(main_line, 20.0, Train.ALONG_RAIL)
	for _frame in 400:
		await drive(1)
		if shuttle_nose().rail != shuttle_tail().rail:
			return true
	return false
