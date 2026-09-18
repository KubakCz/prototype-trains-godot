extends SignalDemoCase
## Driving real trains at the signals: held at danger with the throttle still
## open, away again the moment it clears, untouched by the signal facing the
## other way, and - the case that decides whether the rule is written from the
## nose or from the centre - not stranded when a signal goes back to danger while
## the train is passing it.
##
## Distances are in metres and time is in physics frames; the Local runs at
## 16 m/s, so 60 frames is 16 m of track. Each test gets its own copy of the demo
## scene with every train stopped.


func test_it_is_held_at_danger_and_goes_the_moment_the_signal_clears() -> void:
	place(local, main_line, 20.0, Train.ALONG_RAIL)
	await drive(250)
	note("at the signal:  %s" % state(local))

	assert_eq(local.blocking_signal, home, "it is held at Home, which is at danger")
	assert_near(local.distance, 60.0 - local.body_length * 0.5, 0.2,
			"it waits with its nose on the signal, not past it")
	# Held, not stopped: the throttle stays open so it goes by itself.
	assert_eq(local.throttle, 1, "its throttle is still open while held")

	var held_at := local.distance
	await drive(60)
	assert_near(local.distance, held_at, 1e-3, "it stays put while the signal is at danger")

	home.aspect = RailSignal.Aspect.CLEAR
	await drive(120)
	note("after clearing: %s" % state(local))
	assert_null(local.blocking_signal, "nothing is holding it any more")
	assert_greater(local.distance, 70.0, "it rolled on past the signal by itself")


## The one-directional rule, driven rather than walked: the signal that stops a
## train is the one facing it, and its back-to-back partner four metres away is
## no business of its.
func test_the_signal_for_the_other_direction_does_not_apply() -> void:
	home.aspect = RailSignal.Aspect.DANGER
	home_back.aspect = RailSignal.Aspect.CLEAR
	place(local, main_line, 100.0, Train.AGAINST_RAIL)
	await drive(200)
	note("westbound past Home:  %s" % state(local))
	assert_null(local.blocking_signal, "Home faces the other way, so it lets this train by")
	assert_less(local.distance, 50.0, "it ran past both signals of the pair")

	# Same train, same track, the other signal of the pair.
	place(local, main_line, 100.0, Train.AGAINST_RAIL)
	home_back.aspect = RailSignal.Aspect.DANGER
	await drive(250)
	note("held by its own:      %s" % state(local))
	assert_eq(local.blocking_signal, home_back, "HomeBack is the one that governs it")
	assert_near(local.distance, 56.0 + local.body_length * 0.5, 0.2,
			"and it stops with its nose on HomeBack")


## Putting a signal back to danger under a moving train is allowed - step 8 is
## what will stop it happening by accident. What must not happen is the train
## being stranded across the signal: the rule is written from the nose, so a
## signal the nose is already past no longer applies to that train.
func test_a_signal_put_back_to_danger_under_a_train_lets_it_out() -> void:
	home.aspect = RailSignal.Aspect.CLEAR
	place(local, main_line, 20.0, Train.ALONG_RAIL)
	if not await _drive_until_nose_is_past(home):
		fail("the train's nose gets past Home while its centre is still short of it",
				"never caught it straddling the signal")
		return

	note("straddling Home: %s, nose at %.1f m" % [state(local), nose_of(local).distance])
	home.aspect = RailSignal.Aspect.DANGER
	var was := local.distance
	await drive(40)
	note("after the signal went back: %s" % state(local))
	assert_null(local.blocking_signal, "the signal its nose is past is not holding it")
	assert_greater(local.distance - was, 5.0, "it carried on out rather than sticking")

	# And the next train up to it is still held, so the signal is genuinely at
	# danger rather than quietly disabled.
	place(goods, main_line, 30.0, Train.ALONG_RAIL)
	await drive(180)
	note("the next train up: %s" % state(goods))
	assert_eq(goods.blocking_signal, home, "the signal still holds a train that has yet to reach it")


func test_a_train_crosses_the_points_and_is_held_at_the_signal_beyond_them() -> void:
	points.turnout_position = Turnout.Position.NORMAL
	place(local, main_line, 150.0, Train.ALONG_RAIL)
	await drive(400)
	note("through the points: %s" % state(local))
	assert_eq(local.rail, main_line, "the normal route keeps it on the main line")
	assert_eq(local.blocking_signal, section, "and it is held at Section, past the turnout")

	# Set for the branch instead, it never meets Section at all.
	place(local, main_line, 150.0, Train.ALONG_RAIL)
	points.turnout_position = Turnout.Position.REVERSE
	await drive(300)
	note("into the siding:    %s" % state(local))
	assert_eq(local.rail, siding_line, "the reverse route diverts it into the siding")
	assert_null(local.blocking_signal, "Section is on the main line and does not apply")


func test_a_signal_on_the_branch_holds_a_train_leaving_the_siding() -> void:
	points.turnout_position = Turnout.Position.REVERSE
	place(shunter, siding_line, 45.0, Train.AGAINST_RAIL)
	await drive(400)
	note("in the siding:   %s" % state(shunter))
	assert_eq(shunter.blocking_signal, siding_exit, "SidingExit holds it inside the siding")
	assert_near(shunter.distance, 12.0 + shunter.body_length * 0.5, 0.2,
			"with its nose on the signal")

	siding_exit.aspect = RailSignal.Aspect.CLEAR
	await drive(300)
	note("after clearing:  %s" % state(shunter))
	assert_eq(shunter.rail, main_line, "it came out onto the main line")


## Two trains, two directions, one piece of track: each is held by its own
## signal, and neither notices the other's.
func test_each_direction_is_held_at_its_own_signal_in_the_cluster() -> void:
	place(local, main_line, 90.0, Train.ALONG_RAIL)
	place(goods, main_line, 170.0, Train.AGAINST_RAIL)
	await drive(300)
	note("eastbound: %s" % state(local))
	note("westbound: %s" % state(goods))
	assert_eq(local.blocking_signal, yard_a, "the eastbound train is held at YardA")
	assert_eq(goods.blocking_signal, yard_b, "the westbound train is held at YardB")
	assert_less(local.distance, goods.distance, "and they are held nose to nose, not past each other")


## Sends the Local at [param rail_signal] and stops the moment its nose is past
## while its centre is still short of it.
func _drive_until_nose_is_past(rail_signal: RailSignal) -> bool:
	for _frame in 400:
		await drive(1)
		var nose := nose_of(local)
		if nose.distance > rail_signal.signal_distance() and local.distance < rail_signal.signal_distance():
			return true
	return false
