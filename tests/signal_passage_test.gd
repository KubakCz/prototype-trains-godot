extends SignalDemoCase
## The stopping rule itself, straight through [TrackWalker] rather than by
## driving a train: which walks a signal stops, which it is invisible to, and the
## two cases where "a signal at danger stops you" is not the whole rule - a walk
## measuring a train's body, and a signal the nose has already gone past.
##
## Plus the half of a signal that is level data rather than behaviour: which side
## of the track the mast ends up on, and what a misconfigured one says.


## The whole one-directional rule in one table: every signal in the demo, walked
## at from both sides.
##
## One signal at a time, because three of them stand within eight metres of each
## other and a walk aimed at the far one is stopped by the near one first - which
## is correct, and would make this table say nothing about the signal it names.
func test_a_signal_at_danger_stops_only_the_direction_it_governs() -> void:
	for rail_signal: RailSignal in rail_signals():
		var at := rail_signal.signal_distance()
		var governed := rail_signal.governed_direction()
		set_all(RailSignal.Aspect.CLEAR)
		rail_signal.aspect = RailSignal.Aspect.DANGER
		for direction: int in [1, -1]:
			# Start 20 m back from the signal on the side the walk comes from, and
			# aim 40 m past it.
			var from := rail_signal.rail.clamp_distance(at - float(direction) * 20.0)
			var step := TrackWalker.walk(rail_signal.rail, from, direction, 40.0,
					TrackWalker.OBEY_ALL_SIGNALS)
			var expected := direction == governed
			note("%-11s governs %+d  walked %+d -> %s" % [rail_signal.name, governed,
					direction, step.describe()])
			assert_eq(step.blocking_signal == rail_signal, expected,
					"%s stops a walk going %+d: %s" % [rail_signal.name, direction,
					"yes" if expected else "no"])
			if expected:
				assert_near(step.distance, at, TrackWalker.EPSILON,
						"%s stops the walk on the signal, not past it" % rail_signal.name)


func test_a_clear_signal_is_invisible_to_the_walk() -> void:
	set_all(RailSignal.Aspect.CLEAR)
	var step := TrackWalker.walk(main_line, 20.0, 1, 150.0, TrackWalker.OBEY_ALL_SIGNALS)
	note("cleared everything: walked 20 -> %.1f m, %s" % [step.distance, step.describe()])
	assert_near(step.distance, 170.0, 0.01, "the walk ran the full 150 m past four signals")
	assert_null(step.blocking_signal, "nothing stopped it")


## Where a train's body reaches is a question about track, not about permission,
## so the walks that place it pass no [param signals_from] at all.
func test_a_walk_measuring_track_ignores_signals_entirely() -> void:
	set_all(RailSignal.Aspect.DANGER)
	var step := TrackWalker.walk(main_line, 20.0, 1, 150.0)
	note("same walk without asking permission: -> %.1f m, %s" % [step.distance, step.describe()])
	assert_near(step.distance, 170.0, 0.01, "it ran straight through four signals at danger")
	assert_null(step.blocking_signal, "none of them stopped it")


## The rule that keeps a train from being stranded when a signal goes back to
## danger underneath it: a signal nearer than [param signals_from] is one the
## nose is already beyond, and it no longer applies.
func test_a_signal_the_nose_has_already_passed_no_longer_applies() -> void:
	set_all(RailSignal.Aspect.DANGER)
	var half := 8.0
	# A centre 3 m short of Home, so the nose is 5 m past it.
	var straddling := TrackWalker.walk(main_line, 57.0, 1, half + 4.0, half)
	note("nose 5 m past Home: %s, travelled %.2f m" % [straddling.describe(),
			straddling.travelled])
	assert_null(straddling.blocking_signal, "a signal the nose is past does not stop the walk")

	# A centre a full half-body short of Home, so the nose is exactly on it.
	var arriving := TrackWalker.walk(main_line, 60.0 - half, 1, half + 4.0, half)
	note("nose exactly on Home: %s, travelled %.2f m" % [arriving.describe(),
			arriving.travelled])
	assert_eq(arriving.blocking_signal, home, "a signal the nose has just reached does stop it")
	assert_near(arriving.travelled, half, 0.01, "and it is allowed no further than its nose")


## A signal standing exactly on a set of points wins the tie. Stopping short of
## points a train would have been allowed through is harmless; being let through
## points a signal was holding it at is not.
func test_a_signal_standing_at_a_turnout_stops_the_walk_before_the_points() -> void:
	set_all(RailSignal.Aspect.DANGER)
	yard_a.distance = points.main_distance
	var step := TrackWalker.walk(main_line, 150.0, 1, 80.0, TrackWalker.OBEY_ALL_SIGNALS)
	note("YardA moved onto the points at %.1f m: %s" % [yard_a.signal_distance(),
			step.describe()])
	assert_eq(step.blocking_signal, yard_a, "the signal on the points holds the walk")
	assert_near(step.distance, points.main_distance, TrackWalker.EPSILON,
			"and holds it on the points rather than past them")


## A walk that crosses points and then meets a signal has to report the signal,
## not lose it on the handover.
func test_a_signal_past_a_turnout_still_stops_a_walk_that_crossed_it() -> void:
	set_all(RailSignal.Aspect.DANGER)
	points.turnout_position = Turnout.Position.REVERSE
	var diverted := TrackWalker.walk(main_line, 150.0, 1, 120.0, TrackWalker.OBEY_ALL_SIGNALS)
	note("points reverse: %s on %s @ %.1f m" % [diverted.describe(), diverted.rail.name,
			diverted.distance])
	assert_eq(diverted.rail, siding_line, "the reverse route puts the walk on the branch")
	assert_null(diverted.blocking_signal, "Section is on the main line, so it does not apply")

	points.turnout_position = Turnout.Position.NORMAL
	var through := TrackWalker.walk(main_line, 150.0, 1, 120.0, TrackWalker.OBEY_ALL_SIGNALS)
	note("points normal:  %s on %s @ %.1f m" % [through.describe(), through.rail.name,
			through.distance])
	assert_eq(through.blocking_signal, section, "the through route runs on into Section")


## Which side the mast stands on is not authored: it falls out of the direction
## the signal governs, because a signal is on the right of the trains it applies
## to. The back-to-back pair is the proof - same place, opposite sides.
func test_the_mast_stands_on_the_right_of_the_trains_it_governs() -> void:
	for rail_signal: RailSignal in rail_signals():
		var at := rail_signal.signal_distance()
		var travel := rail_signal.governed_heading()
		var up := rail_signal.rail.sample_up(at)
		var right := travel.cross(up).normalized()
		var offset := rail_signal.mast_position() - rail_signal.signal_position()
		note("%-11s mast %.2f m to the right of the governed direction"
				% [rail_signal.name, offset.dot(right)])
		assert_greater(offset.dot(right), 1.0,
				"%s stands to the right of the trains it stops" % rail_signal.name)

	var separation := home.mast_position().distance_to(home_back.mast_position())
	note("Home and HomeBack stand %.2f m apart, across the track from each other" % separation)
	assert_greater(separation, home.side_offset,
			"a back-to-back pair ends up on opposite sides of the track")


func test_the_demo_layout_has_no_configuration_warnings() -> void:
	for rail_signal: RailSignal in rail_signals():
		var warnings := rail_signal._get_configuration_warnings()
		if not warnings.is_empty():
			note("%s: %s" % [rail_signal.name, ", ".join(warnings)])
		assert_true(warnings.is_empty(), "%s: no configuration warnings" % rail_signal.name)


## The editor-facing path: a misconfigured signal has to say so, and has to stop
## saying so once it is fixed.
func test_a_signal_that_nothing_can_reach_is_reported() -> void:
	home.distance = main_line.rail_length() + 40.0
	note("off the rail -> %s" % ", ".join(home._get_configuration_warnings()))
	assert_false(home._get_configuration_warnings().is_empty(),
			"a distance off the rail is reported")

	# At distance 0 governing towards the end, the signal faces the start of the
	# rail: there is no track behind it for a train to arrive on.
	home.distance = 0.0
	home.governs = RailSignal.Governs.TOWARDS_RAIL_END
	note("facing off the end of the rail -> %s"
			% ", ".join(home._get_configuration_warnings()))
	assert_false(home._get_configuration_warnings().is_empty(),
			"a signal nothing can ever approach is reported")

	home.distance = 60.0
	assert_true(home._get_configuration_warnings().is_empty(),
			"the warnings clear once it is back on the rail with track in front of it")
