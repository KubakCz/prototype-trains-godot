extends StationsDemoCase
## scenes/demos/stations.tscn as a level, built by tools/build_stations_demo.gd: that it
## follows the rules the other levels are built to - every signal at danger when it
## opens, no configuration warnings - is signalled the way stations are, every way back
## from every junction meeting an entry or exit signal ([method
## JunctionProtection.check_signalled]) rather than one signal per junction, and the
## ones the stations bring with them: an exit signal each way off every station track
## that is not a dead end, standing clear of the platform's end, and on every gate track
## room outside the mark for the longest train the routes send and an entry signal
## inside it.

const SIGNAL_COUNT := 21


func _turnouts() -> Array[Turnout]:
	var found: Array[Turnout] = []
	for node in tree.get_nodes_in_group(&"turnouts"):
		found.append(node as Turnout)
	return found


func _compounds() -> Array[CompoundTurnout]:
	var found: Array[CompoundTurnout] = []
	for node in tree.get_nodes_in_group(&"compound_turnouts"):
		found.append(node as CompoundTurnout)
	return found


func _points() -> Array[InterestPoint]:
	var found: Array[InterestPoint] = []
	for node in tree.get_nodes_in_group(InterestPoint.GROUP):
		found.append(node as InterestPoint)
	return found


func test_every_signal_starts_at_danger() -> void:
	assert_eq(signals().size(), SIGNAL_COUNT, "the demo has %d signals" % SIGNAL_COUNT)
	for rail_signal in signals():
		assert_eq(rail_signal.aspect, RailSignal.Aspect.DANGER, "%s starts at danger" % rail_signal.name)


func test_every_way_into_every_junction_is_signalled() -> void:
	var ways_in := JunctionProtection.ways_in(_turnouts(), _compounds(), [])
	var protecting := JunctionProtection.check_signalled(self, ways_in)
	note("%d ways into %d turnouts and %d assemblies, protected by %d of the %d signals" % [
			ways_in.size(), _turnouts().size(), _compounds().size(), protecting.size(),
			signals().size()])
	assert_eq(ways_in.size(), 5 * 3 + 4 * 4, "five lone turnouts and four scissors crossovers make 31 ways in")


func test_the_level_has_no_configuration_warnings() -> void:
	var nodes: Array[Node] = []
	nodes.append_array(_turnouts())
	nodes.append_array(_compounds())
	nodes.append_array(signals())
	nodes.append(spawner)
	nodes.append_array(spawner.routes())
	for point in _points():
		nodes.append(point)
		nodes.append_array(point.tracks())
	for node: Node in nodes:
		var warnings: PackedStringArray = node._get_configuration_warnings()
		if not warnings.is_empty():
			note("%s: %s" % [node.name, ", ".join(warnings)])
		assert_true(warnings.is_empty(), "%s: no configuration warnings" % node.name)


func test_every_station_track_has_an_exit_signal_each_way_off_it() -> void:
	for point in _points():
		var station := point as Station
		if station == null:
			continue
		for track in station.tracks():
			for direction: int in [1, -1]:
				var way := "%s/%s towards the rail's %s" % [station.label(), track.name,
						"end" if direction > 0 else "start"]
				var exit_signal := track.guarding_signal(direction)
				var walk := TrackWalker.walk(track.rail, track.distance, direction,
						track.rail.rail_length() + 1.0)
				if walk.at_dead_end and walk.spans.size() == 1:
					note("%-38s  a dead end" % way)
					succeed("%s needs no exit signal: it ends in a buffer" % way)
					continue
				if assert_not_null(exit_signal, "%s has an exit signal" % way):
					var beyond := float(direction) * (exit_signal.signal_distance()
							- track.stop_distance(direction))
					note("%-38s  %s, %.1f m past the platform's end" % [way, exit_signal.name, beyond])
					assert_greater(beyond, Station.EXIT_CLEARANCE - 0.001,
							"%s's exit signal stands clear of the platform" % way)


func test_every_gate_track_has_room_outside_for_the_longest_train_and_an_entry_signal() -> void:
	var longest := 0.0
	for route in spawner.routes():
		for type in route.train_types:
			longest = maxf(longest, type.longest_length())
	note("the longest train the routes send is %.1f m" % longest)
	for gate: OutsideConnection in [west_gate, east_gate]:
		for track in gate.tracks():
			var room := OutsideConnection.room_outside(track)
			assert_greater(room, longest, "%s/%s has %.1f m outside its mark for the longest train" % [
					gate.label(), track.name, room])
			var entry := track.guarding_signal(-OutsideConnection.outward(track))
			if not assert_not_null(entry, "%s/%s has an entry signal" % [gate.label(), track.name]):
				continue
			var inside := float(-OutsideConnection.outward(track)) * (entry.signal_distance() - track.distance)
			note("%s/%s: %s %.1f m in" % [gate.label(), track.name, entry.name, inside])
			assert_greater(inside, Train.STOP_SHORT, "%s/%s's entry signal stands inside the mark" % [
					gate.label(), track.name])
