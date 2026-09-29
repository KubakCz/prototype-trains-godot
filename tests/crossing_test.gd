extends CompoundDemoCase
## Crossings: two rails crossing with no way from one to the other. There is no
## player interaction, so what is tested is what later steps will build on - the
## crossing is found where the rails really meet, trains run straight through it,
## the rails know it is there, and it knows which trains are standing over it.


func test_each_crossing_is_located_where_its_two_rails_meet() -> void:
	for crossing: Crossing in [diamond, scissors_middle, double_slip_middle]:
		var a := crossing.rail_a.sample_position(crossing.distance_a)
		var b := crossing.rail_b.sample_position(crossing.distance_b)
		var gap := Vector2(a.x - b.x, a.z - b.z).length()
		note("%-14s %s @ %.2f m x %s @ %.2f m  gap %.3f m  %.1f deg" % [crossing.name,
				crossing.rail_a.name, crossing.distance_a, crossing.rail_b.name,
				crossing.distance_b, gap, crossing.crossing_angle_degrees()])
		assert_less(gap, 0.05, "%s sits on both rails at once" % crossing.name)
		assert_true(crossing._get_configuration_warnings().is_empty(),
				"%s is configured without warnings" % crossing.name)
	assert_near(diamond.crossing_angle_degrees(), 31.0, 1.5,
			"the diamond crosses at the angle the diagonal was drawn at")
	assert_near(double_slip_middle.crossing_angle_degrees(), 12.0, 0.5,
			"the double slip's tracks cross at the 12 deg they were drawn at")


## A crossing is registered on both rails, exactly like a turnout or a signal,
## so anything collecting what is on a rail finds it.
func test_both_rails_list_the_crossing_among_their_attachments() -> void:
	for crossing: Crossing in [diamond, scissors_middle]:
		assert_true(crossing in crossing.rail_a.attachments(), "%s is attached to %s"
				% [crossing.name, crossing.rail_a.name])
		assert_true(crossing in crossing.rail_b.attachments(), "%s is attached to %s"
				% [crossing.name, crossing.rail_b.name])
		assert_eq(crossing.other_rail(crossing.rail_a), crossing.rail_b,
				"from one rail, the crossing names the other")


func test_trains_run_straight_through_a_crossing_on_either_rail() -> void:
	var along := walk("DiamondStraight", diamond.distance_a - 30.0, 1, 60.0)
	var across := walk("DiamondDiagonal", diamond.distance_b + 30.0, -1, 60.0)
	note("straight: %s" % describe(along))
	note("diagonal: %s" % describe(across))
	assert_false(along.is_blocked(), "nothing stops a walk along the straight rail")
	assert_eq(along.rail.name, "DiamondStraight", "and it stays on it")
	assert_near(along.travelled, 60.0, 1e-3, "for the whole distance asked")
	assert_false(across.is_blocked(), "nor one along the diagonal, the other way")
	assert_eq(across.rail.name, "DiamondDiagonal", "which stays on the diagonal")


func test_the_crossing_knows_which_trains_are_on_it() -> void:
	var straight := train("DiamondStraightTrain")
	var diagonal := train("DiamondDiagonalTrain")
	await physics_frames(2)
	note("before: %s" % _names(diamond.occupants()))
	assert_false(diamond.is_occupied(), "nothing is over the diamond to begin with")

	# 14 m long, so standing 5 m short of the crossing it covers it with its nose.
	straight.distance = diamond.distance_a - 5.0
	await physics_frames(2)
	note("straight train 5 m short: %s" % _names(diamond.occupants()))
	assert_eq(diamond.occupants().size(), 1, "one train is over it")
	assert_true(straight in diamond.occupants(), "the one on the straight rail")

	diagonal.distance = diamond.distance_b + 3.0
	await physics_frames(2)
	note("and the diagonal train 3 m past: %s" % _names(diamond.occupants()))
	assert_eq(diamond.occupants().size(), 2, "both trains count, whichever rail they are on")

	straight.distance = diamond.distance_a - 20.0
	diagonal.distance = diamond.distance_b + 20.0
	await physics_frames(2)
	note("both moved 20 m off: %s" % _names(diamond.occupants()))
	assert_false(diamond.is_occupied(), "the crossing is clear again")


## Occupancy is read off the train's body, not its centre, so a train straddling
## points is on whichever rails its two halves are on. At the scissors' middle
## crossing that is both links, from a train that came in off either.
func test_a_train_crossing_the_scissors_occupies_its_middle() -> void:
	var eastbound := train("ScissorsEastbound")
	eastbound.end_behavior = Train.EndBehavior.STOP
	scissors.cycle()
	place(eastbound, "ScissorsNorth", 100.0, Train.ALONG_RAIL)
	var seen := false
	var raised := [0]
	scissors_middle.occupancy_changed.connect(func() -> void: raised[0] += 1)
	for _frame in 400:
		await physics_frames(1)
		if eastbound in scissors_middle.occupants():
			seen = true
			note("on the middle crossing: %s" % state(eastbound))
			break
	assert_true(seen, "the train crossing over is reported on the middle crossing")
	assert_eq(raised[0], 1, "occupancy_changed fired as it arrived")


func test_misconfigured_crossings_are_warned_about() -> void:
	var off := Crossing.new()
	off.rail_a = rail("DiamondStraight")
	off.rail_b = rail("DiamondDiagonal")
	off.distance_a = 10.0
	off.distance_b = 10.0
	var same := Crossing.new()
	same.rail_a = rail("DiamondStraight")
	same.rail_b = rail("DiamondStraight")
	for entry: Array in [[off, "Locate Crossing"], [same, "two different rails"]]:
		var crossing := entry[0] as Crossing
		var warnings := " | ".join(crossing._get_configuration_warnings())
		note(warnings)
		assert_true(warnings.contains(entry[1]), "warned: '%s'" % entry[1])
	# Locate is the button the first warning points at, and it has to fix it.
	off.locate()
	assert_true(off._get_configuration_warnings().is_empty(), "Locate Crossing clears it")
	assert_near(off.distance_a, diamond.distance_a, 0.05, "and finds the same crossing")
	off.free()
	same.free()


func _names(trains: Array[Train]) -> String:
	var names: Array[String] = []
	for each in trains:
		names.append(str(each.name))
	return "[%s]" % ", ".join(names) if not names.is_empty() else "clear"
