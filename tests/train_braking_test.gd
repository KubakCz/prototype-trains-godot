extends TrainDemoCase
## Getting going and stopping: acceleration from the consist, the service curve
## into a red signal, harder braking for one put back late, the overrun when even
## full brakes are not enough and the player letting the train go again, and the
## player's own stop.
##
## The express is the subject almost throughout: 160 t, 2.25 m/s² to get going, 3.6
## to stop normally and 6.0 at full brake, so from 18 m/s it needs 45 m to stop
## normally and 27 m at the very least. NorthOverrun stands at 230 m and starts
## clear; NorthStop at 420 m is red.


func test_it_gets_going_at_the_rate_its_consist_gives_it() -> void:
	place(express, north_line, 60.0)
	await drive(120)
	note("after 2 s: %s" % state(express))
	assert_near(express.current_speed, express.acceleration_rate() * 2.0, 0.05,
			"two seconds in it is doing its acceleration times two")
	var fastest := 0.0
	for _frame in 420:
		await drive(1)
		fastest = maxf(fastest, express.current_speed)
	note("after 9 s: %s" % state(express))
	assert_near(express.current_speed, express.max_speed, 1e-4, "it reaches its top speed")
	assert_less(fastest, express.max_speed + 1e-4, "and never goes over it")

	place(loaded_freight, middle_line, 60.0)
	place(empty_freight, south_line, 60.0)
	await drive(600)
	note("after 10 s: %s" % state(loaded_freight))
	note("            %s" % state(empty_freight))
	assert_near(loaded_freight.current_speed, loaded_freight.acceleration_rate() * 10.0, 0.05,
			"the loaded freight picks up speed at its own rate")
	assert_less(loaded_freight.current_speed * 2.0, empty_freight.current_speed,
			"less than half as fast as the same train empty")


func test_it_brakes_for_a_red_signal_and_stops_short_of_it() -> void:
	north_overrun.aspect = RailSignal.Aspect.CLEAR
	place_nose(express, north_line, north_stop.signal_distance(), 120.0, 18.0)
	var began := INF
	var hardest := 0.0
	var states: Array[String] = []
	for _frame in 900:
		await drive(1)
		if express.braking > 0.0 and is_inf(began):
			began = nose_short_of(express, north_stop.signal_distance())
		# The last few frames are left out: with millimetres to go, the rate that
		# lands it exactly on the signal is all rounding.
		if express.current_speed > 1.0:
			hardest = maxf(hardest, express.braking)
		if not states.has(express.state_name()):
			states.append(express.state_name())
	note("began braking %.2f m short, hardest %.3f m/s², went %s" % [began + 18.0 / 60.0,
			hardest, " -> ".join(states)])
	note(state(express))
	var service := Train.stopping_distance(18.0, express.service_brake_rate())
	assert_near(began, service + Train.STOP_SHORT, 0.5,
			"it starts braking its normal stopping distance short of where it stops")
	assert_less(hardest, express.service_brake_rate() * 1.02, "and never brakes harder than normal")
	assert_eq(states, ["DRIVING", "BRAKING", "HELD"] as Array[String],
			"driving, braking, then held")
	assert_near(nose_short_of(express, north_stop.signal_distance()), Train.STOP_SHORT, 0.02,
			"it stands a few metres short of the signal")
	assert_eq(express.blocking_signal, north_stop, "held at NorthStop")
	assert_eq(express.throttle, 1, "with its throttle still open")
	assert_eq(Train.state_color(express.state), Color(0.95, 0.12, 0.1), "and a red marker")

	north_stop.aspect = RailSignal.Aspect.CLEAR
	await drive(60)
	assert_eq(express.state, Train.State.DRIVING, "it goes as soon as the signal clears")
	assert_greater(express.current_speed, 1.0, "under its own power")


## Starting 100 m short of a red, it meets the braking curve before its top speed -
## and has to meet it at the normal rate rather than a frame's travel over it.
func test_a_train_getting_going_towards_a_red_stops_normally() -> void:
	var at := north_stop.signal_distance()
	place_nose(express, north_line, at, 100.0)
	var top := 0.0
	var hardest := 0.0
	for _frame in 1200:
		await drive(1)
		top = maxf(top, express.current_speed)
		if express.current_speed > 1.0:
			hardest = maxf(hardest, express.braking)
	note("top %.2f m/s, hardest %.4f m/s²: %s" % [top, hardest, state(express)])
	assert_less(top, express.max_speed, "it never got to its top speed")
	assert_less(hardest, express.service_brake_rate() * 1.0001, "it braked at the normal rate")
	assert_near(nose_short_of(express, at), Train.STOP_SHORT, 0.02,
			"and stopped a few metres short of the signal")


## Between its normal stopping distance and its shortest: it brakes as hard as it
## has to - harder than normal - and still stops at the signal, not past it.
func test_a_signal_put_back_late_is_stopped_for_harder() -> void:
	north_stop.aspect = RailSignal.Aspect.CLEAR
	place_nose(express, north_line, north_stop.signal_distance(), 120.0, 18.0)
	var at := north_stop.signal_distance()
	assert_true(await drive_until(func() -> bool: return nose_short_of(express, at) <= 35.0),
			"it gets within 35 m of NorthStop")
	north_stop.aspect = RailSignal.Aspect.DANGER
	await drive(1)
	note("put back 35 m short: %s" % state(express))
	assert_greater(express.braking, express.service_brake_rate(), "it brakes harder than normal")
	assert_less(express.braking, express.full_brake_rate(), "but not flat out")
	assert_eq(express.state, Train.State.BRAKING, "red, not blinking")
	await drive(300)
	note(state(express))
	assert_false(express.tripped, "it did not trip")
	assert_near(nose_short_of(express, at), Train.STOP_SHORT, 0.02,
			"and stopped a few metres short of the signal")


## Too late to stop short of the signal even at 100%, but not too late to stop before
## it: it uses the margin rather than tripping, and stands between the two.
func test_a_signal_put_back_inside_the_margin_is_stopped_for_at_the_signal() -> void:
	north_stop.aspect = RailSignal.Aspect.CLEAR
	var at := north_stop.signal_distance()
	place_nose(express, north_line, at, 120.0, 18.0)
	var shortest := Train.stopping_distance(18.0, express.full_brake_rate())
	var put_back := shortest + 1.0
	assert_true(await drive_until(func() -> bool: return nose_short_of(express, at) <= put_back),
			"it gets within %.1f m of NorthStop" % put_back)
	north_stop.aspect = RailSignal.Aspect.DANGER
	await drive(1)
	note("put back %.1f m short: %s" % [put_back, state(express)])
	assert_false(express.tripped, "it can still stop before the signal, so it does not trip")
	await drive(300)
	note(state(express))
	assert_false(express.tripped, "nor later")
	assert_eq(express.blocking_signal, north_stop, "it is held at NorthStop")
	var short := nose_short_of(express, at)
	assert_less(short, Train.STOP_SHORT, "short of where it would have liked to stop")
	assert_greater(short, -0.02, "but not past the signal")


## Inside its shortest stopping distance: full brakes, past the signal, and it waits
## beyond it - blinking red - until the player lets it go.
func test_a_signal_put_back_too_late_is_overrun() -> void:
	var at := north_overrun.signal_distance()
	place_nose(express, north_line, at, 80.0, 18.0)
	assert_true(await drive_until(func() -> bool: return nose_short_of(express, at) <= 15.0),
			"it gets within 15 m of NorthOverrun")
	north_overrun.aspect = RailSignal.Aspect.DANGER
	await drive(1)
	note("put back 15 m short: %s" % state(express))
	assert_true(express.tripped, "it trips")
	assert_eq(express.state, Train.State.TRIPPED, "blinking red")
	assert_true(Train.state_blinks(express.state), "the marker blinks")
	assert_near(express.braking, express.full_brake_rate(), 1e-4, "brakes at 100%")

	await drive(300)
	note("at rest:  %s" % state(express))
	var past := -nose_short_of(express, at)
	var expected := Train.stopping_distance(18.0, express.full_brake_rate()) - 15.0
	assert_near(past, expected, 0.6, "it comes to rest past the signal, as soon as it can")
	assert_eq(express.current_speed, 0.0, "and stands")
	var stood := express.distance
	await drive(120)
	assert_eq(express.distance, stood, "it stays there")
	assert_eq(express.state, Train.State.TRIPPED, "still blinking: it waits to be let go")
	assert_eq(north_overrun.aspect, RailSignal.Aspect.DANGER, "the signal behind it is still red")

	express.release()
	await drive(180)
	note("let go:   %s" % state(express))
	assert_false(express.tripped, "letting it go clears the trip")
	assert_eq(express.state, Train.State.DRIVING, "and it drives on")
	assert_greater(express.distance, stood + 5.0, "away from the signal")


## "At any point": let go while it is still braking past the signal, it takes the
## brakes off and carries on through.
func test_an_overrunning_train_can_be_let_go_before_it_stops() -> void:
	var at := north_overrun.signal_distance()
	place_nose(express, north_line, at, 80.0, 18.0)
	assert_true(await drive_until(func() -> bool: return nose_short_of(express, at) <= 15.0),
			"it gets within 15 m of NorthOverrun")
	north_overrun.aspect = RailSignal.Aspect.DANGER
	await drive(20)
	var slowed := express.current_speed
	note("braking:  %s" % state(express))
	express.release()
	await drive(2)
	note("let go:   %s" % state(express))
	assert_eq(express.braking, 0.0, "the brakes come off")
	assert_greater(express.current_speed, slowed, "and it picks up speed again")
	await drive(120)
	note("later:    %s" % state(express))
	assert_less(nose_short_of(express, at), -20.0, "carrying on past the signal it overran")
	assert_eq(express.state, Train.State.DRIVING, "driving normally")


func test_cutting_the_throttle_stops_it_normally() -> void:
	place(express, north_line, 60.0, 18.0)
	await drive(2)
	var from := express.nose().distance
	express.throttle = 0
	await drive(1)
	note("stopping: %s" % state(express))
	assert_eq(express.state, Train.State.STOPPING, "it is stopping")
	assert_true(Train.state_blinks(express.state), "blinking")
	assert_eq(Train.state_color(express.state), Color(1.0, 0.82, 0.1), "yellow")
	assert_near(express.braking, express.service_brake_rate(), 1e-4, "at the normal rate")
	await drive(360)
	note("stopped:  %s" % state(express))
	assert_eq(express.state, Train.State.STOPPED, "it stands, stopped")
	assert_false(Train.state_blinks(express.state), "steady yellow")
	assert_near(express.nose().distance - from,
			Train.stopping_distance(18.0, express.service_brake_rate()), 0.5,
			"its normal stopping distance on")


## Stopped by the player with a red signal closer than a normal stop: it brakes as
## hard as it has to and stands at the signal rather than past it.
func test_a_stop_that_a_red_signal_cuts_short_still_stops_at_the_signal() -> void:
	north_stop.aspect = RailSignal.Aspect.CLEAR
	var at := north_stop.signal_distance()
	place_nose(express, north_line, at, 120.0, 18.0)
	assert_true(await drive_until(func() -> bool: return nose_short_of(express, at) <= 35.0),
			"it gets within 35 m of NorthStop")
	express.throttle = 0
	north_stop.aspect = RailSignal.Aspect.DANGER
	await drive(1)
	note("both:     %s" % state(express))
	assert_eq(express.state, Train.State.BRAKING, "the signal is what it is braking for")
	assert_greater(express.braking, express.service_brake_rate(), "harder than a normal stop")
	await drive(300)
	note("stopped:  %s" % state(express))
	assert_near(nose_short_of(express, at), Train.STOP_SHORT, 0.02,
			"it stands a few metres short of the signal")
	assert_eq(express.state, Train.State.STOPPED, "stopped by the player, so yellow")


func test_reversing_at_speed_stops_it_before_it_backs() -> void:
	place(express, north_line, 120.0, 18.0)
	await drive(2)
	express.throttle = -1
	await drive(1)
	note("reversed: %s" % state(express))
	assert_eq(express.state, Train.State.STOPPING, "it stops first")
	assert_eq(express.moving_direction(), 1, "still moving nose-first")
	await drive(360)
	var stood := express.distance
	await drive(120)
	note("backing:  %s" % state(express))
	assert_eq(express.moving_direction(), -1, "then backs")
	assert_less(express.distance, stood, "the way it came")
	assert_eq(express.facing, Train.ALONG_RAIL, "with its nose still east")


func test_the_front_marker_says_what_the_train_is_doing() -> void:
	var red := Color(0.95, 0.12, 0.1)
	var yellow := Color(1.0, 0.82, 0.1)
	var states: Array[Train.State] = [Train.State.DRIVING, Train.State.BRAKING, Train.State.HELD,
			Train.State.STOPPING, Train.State.STOPPED, Train.State.TRIPPED, Train.State.DERAILED]
	var colours: Array[Color] = [Color(0.2, 0.95, 0.3), red, red, yellow, yellow, red,
			Color(0.02, 0.02, 0.02)]
	var blinking: Array[bool] = [false, false, false, true, false, true, false]
	for i in states.size():
		var label: String = Train.State.keys()[states[i]]
		assert_eq(Train.state_color(states[i]), colours[i], "%s shows #%s" % [label,
				colours[i].to_html(false)])
		assert_eq(Train.state_blinks(states[i]), blinking[i], "%s %s" % [label,
				"blinks" if blinking[i] else "is steady"])
