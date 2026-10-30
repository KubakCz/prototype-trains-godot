extends CompoundDemoCase
## Trains through the assemblies. The members are ordinary turnouts, so this is
## TrackWalker walking through two or four sets of points in a row - facing and
## trailing, in every position - and then trains actually driving it, including
## the one held by a crossover set against it.
##
## Walks start 20 m short of the assembly and go 80 m, which clears every one of
## them; the demo's tracks run straight, so where a walk ends says which track it
## came out on.


func test_a_three_way_sends_a_facing_train_down_the_track_it_is_set_for() -> void:
	var expected: Array[String] = ["ThreeWayMain", "ThreeWayLeft", "ThreeWayRight"]
	for index in three_way.position_count():
		three_way.compound_position = index
		var step := walk("ThreeWayMain", 80.0, 1, 80.0)
		note("%-8s %s" % [three_way.position_label(index), describe(step)])
		assert_false(step.is_blocked(), "a facing move is never refused")
		assert_eq(step.rail.name, expected[index], "%s leads onto %s"
				% [three_way.position_label(index), expected[index]])


func test_a_three_way_only_lets_the_set_track_back_out() -> void:
	var leaving: Array[Array] = [["ThreeWayMain", 180.0], ["ThreeWayLeft", 60.0],
			["ThreeWayRight", 60.0]]
	for index in three_way.position_count():
		three_way.compound_position = index
		for entry in leaving:
			var from: String = entry[0]
			var step := walk(from, entry[1], -1, 200.0)
			var admitted := step.rail.name == "ThreeWayMain" and step.distance < 90.0
			note("%-8s from %-13s %s" % [three_way.position_label(index), from, describe(step)])
			assert_eq(admitted, from == ["ThreeWayMain", "ThreeWayLeft", "ThreeWayRight"][index],
					"%s %s the trailing move from %s" % [three_way.position_label(index),
					"admits" if admitted else "refuses", from])


func test_a_crossover_moves_an_eastbound_train_across_only_when_set_to_cross() -> void:
	var parallel := walk("CrossoverNorth", 90.0, 1, 80.0)
	crossover.cycle()
	var crossed := walk("CrossoverNorth", 90.0, 1, 80.0)
	note("parallel: %s" % describe(parallel))
	note("cross:    %s" % describe(crossed))
	assert_eq(parallel.rail.name, "CrossoverNorth", "parallel keeps it on the north track")
	assert_eq(crossed.rail.name, "CrossoverSouth", "cross puts it on the south track")
	assert_eq(crossed.direction, 1, "still heading east")


## One direction only, which is what makes it a crossover rather than a pair of
## junctions: the two trains a cross setting stands in the way of are held.
func test_a_crossover_set_to_cross_holds_the_trains_it_stands_in_the_way_of() -> void:
	crossover.cycle()
	var north_west := walk("CrossoverNorth", 180.0, -1, 100.0)
	var south_east := walk("CrossoverSouth", 90.0, 1, 80.0)
	note("north, westbound: %s" % describe(north_west))
	note("south, eastbound: %s" % describe(south_east))
	assert_eq(north_west.blocking_turnout, member(crossover, "NorthPoints"),
			"a westbound train on the north track is held at NorthPoints")
	assert_eq(south_east.blocking_turnout, member(crossover, "SouthPoints"),
			"an eastbound train on the south track is held at SouthPoints")
	var south_west := walk("CrossoverSouth", 180.0, -1, 100.0)
	note("south, westbound: %s" % describe(south_west))
	assert_eq(south_west.rail.name, "CrossoverNorth",
			"and a westbound train on the south track crosses back north")


## Two crossovers in one: set to cross, every one of the four ways in changes
## track, which a plain crossover cannot do.
func test_a_double_crossover_crosses_trains_in_both_directions() -> void:
	var entries: Array[Array] = [["ScissorsNorth", 100.0, 1, "ScissorsSouth"],
			["ScissorsSouth", 100.0, 1, "ScissorsNorth"],
			["ScissorsNorth", 180.0, -1, "ScissorsSouth"],
			["ScissorsSouth", 180.0, -1, "ScissorsNorth"]]
	for position in scissors.position_count():
		scissors.compound_position = position
		for entry in entries:
			var from: String = entry[0]
			var step := walk(from, entry[1], entry[2], 80.0)
			var wanted: String = from if position == 0 else entry[3]
			note("%-8s %-13s %+d  %s" % [scissors.position_label(position), from, entry[2],
					describe(step)])
			assert_false(step.is_blocked(), "nothing is refused")
			assert_eq(step.rail.name, wanted, "%s from %s heading %+d ends on %s"
					% [scissors.position_label(position), from, entry[2], wanted])


func test_a_train_drives_over_the_crossover_and_on_along_the_other_track() -> void:
	var shuttle := train("CrossoverShuttle")
	shuttle.end_behavior = Train.EndBehavior.STOP
	crossover.cycle()
	place(shuttle, "CrossoverNorth", 80.0, Train.ALONG_RAIL)
	# 14 m/s: 360 frames is 84 m, which clears the link.
	await physics_frames(360)
	note(state(shuttle))
	assert_eq(shuttle.rail.name, "CrossoverSouth", "it came over to the south track")
	assert_eq(shuttle.facing, Train.ALONG_RAIL, "nose still east")
	assert_greater(shuttle.distance, 150.0, "and carried on east past SouthPoints")


func test_a_train_held_by_the_crossover_goes_when_it_is_set_back() -> void:
	var local := train("CrossoverLocal")
	crossover.cycle()
	# Points set against a train are run into, not stopped for: only one that starts
	# with its nose on them, and so can only creep up to them, is held there.
	place(local, "CrossoverSouth", 140.0 - local.half_length(), Train.ALONG_RAIL)
	local.roll(0.0)
	await physics_frames(60)
	note("held:     %s" % state(local))
	assert_eq(local.blocking_turnout, member(crossover, "SouthPoints"), "held by SouthPoints")
	assert_true(local.blocked_description().contains("Crossover/SouthPoints"),
			"the readout names the assembly the player has to change")
	assert_eq(local.throttle, 1, "held with the throttle open")

	crossover.cycle()
	await physics_frames(180)
	note("released: %s" % state(local))
	assert_null(local.blocking_turnout, "nothing holds it once the crossover is parallel")
	assert_greater(local.distance, 140.0, "it carried on past the points")


## Both routes of a position open at once: from each of the four ways in, the
## train comes out on its own track when straight and on the other when slipping,
## and nothing is ever refused. Entries are named by track and end - "1w" is
## track 1 from the west.
func test_a_double_slip_opens_two_routes_at_once() -> void:
	# Where each entry comes out, per position STRAIGHT, SLIP.
	var expected: Array[Array] = [
		["1w", "SlipLineOne", 1, ["SlipLineOne", "SlipLineTwo"]],
		["2w", "SlipLineTwo", 1, ["SlipLineTwo", "SlipLineOne"]],
		["1e", "SlipLineOne", -1, ["SlipLineOne", "SlipLineTwo"]],
		["2e", "SlipLineTwo", -1, ["SlipLineTwo", "SlipLineOne"]],
	]
	for position in double_slip.position_count():
		double_slip.compound_position = position
		for entry in expected:
			var step := _through_the_slip(entry[1], entry[2])
			var wanted: String = (entry[3] as Array)[position]
			note("%-8s %s -> %s" % [double_slip.position_label(position), entry[0], describe(step)])
			assert_false(step.is_blocked(), "%s: nothing is refused"
					% double_slip.position_label(position))
			assert_eq(str(step.rail.name), wanted, "%s: entry %s comes out on %s"
					% [double_slip.position_label(position), entry[0], wanted])


func test_a_train_takes_the_slip_road_and_carries_on_along_the_other_track() -> void:
	var eastbound := train("SlipEastbound")
	eastbound.end_behavior = Train.EndBehavior.STOP
	double_slip.compound_position = 1
	var mid := rail("SlipLineOne").rail_length() * 0.5
	place(eastbound, "SlipLineOne", mid - 50.0, Train.ALONG_RAIL)
	# 12 m/s: 480 frames is 96 m, well past the far points 14 m beyond the middle.
	await physics_frames(480)
	note(state(eastbound))
	assert_eq(eastbound.rail.name, "SlipLineTwo", "slip 1 took it onto track 2")
	assert_greater(eastbound.distance, mid + 14.0, "and it carried on east past the points")


## A 100 m walk from 50 m short of the middle, which clears the slip either way.
func _through_the_slip(on: String, direction: int) -> TrackWalker.Step:
	var mid := rail(on).rail_length() * 0.5
	return walk(on, mid - 50.0 * float(direction), direction, 100.0)


## The routes the overlay draws are walks too, so they have to agree with where a
## train actually goes. Four ways in, each set route green end to end.
func test_the_drawn_routes_follow_the_set_position() -> void:
	var link_down := rail("ScissorsDown")
	var north := rail("ScissorsNorth")
	for position in scissors.position_count():
		scissors.compound_position = position
		var on_link := false
		var between := false
		for span in scissors.route_spans():
			on_link = on_link or span.covers(link_down, link_down.rail_length() * 0.5)
			between = between or span.covers(north, 140.0)
		note("%-8s routes %d  over the link %s  along the north track between the points %s"
				% [scissors.position_label(position), scissors.route_spans().size(), on_link, between])
		assert_eq(on_link, position == 1, "the link is on a route only when crossed")
		assert_eq(between, position == 0, "the straight run is on a route only when parallel")
