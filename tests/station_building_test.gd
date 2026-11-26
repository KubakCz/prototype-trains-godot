extends StationsDemoCase
## What a station puts beside its tracks and what it asks of them: the building - a box
## with a gable roof in the station's colour, standing on the ground on the side the
## station names, beside the outermost track - its platforms, and the warnings for a station track
## without an exit signal or a gate track without an entry signal.
##
## Central's first track is the loop, which runs west to east, so its right is south:
## the demo leaves every station's building on the right, which puts Central's beside
## the south main. Looking east the tracks are, north to south, Loop, North, South.


func _walls(station: Station) -> MeshInstance3D:
	return station.building().get_node("Walls") as MeshInstance3D


func _roof(station: Station) -> MeshInstance3D:
	return station.building().get_node("Roof") as MeshInstance3D


## [param point] relative to [param track]'s mark: x along the first track's rail
## towards its end, y up, z to the right of it, all flat.
func _beside(station: Station, track: InterestTrack, point: Vector3) -> Vector3:
	var first := station.tracks()[0]
	var forward := first.rail.sample_forward(first.distance)
	forward.y = 0.0
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP)
	var offset := point - track.position()
	return Vector3(offset.dot(forward), offset.y, offset.dot(right))


func _track_named(station: Station, track_name: String) -> InterestTrack:
	return station.get_node(track_name) as InterestTrack


#region The building
func test_every_station_has_a_building_and_a_gate_none() -> void:
	for station: Station in [central, mine, factory, halt]:
		var building := station.building()
		if not assert_not_null(building, "%s has a building" % station.label()):
			continue
		assert_true(building.visible, "%s's building is showing" % station.label())
		assert_true(_walls(station).mesh is BoxMesh, "%s's walls are a box" % station.label())
		assert_true(_roof(station).mesh is PrismMesh, "%s's roof is a gable" % station.label())
		assert_greater(_roof(station).global_position.y, _walls(station).global_position.y,
				"%s's roof is on top of the walls" % station.label())
	for gate: OutsideConnection in [west_gate, east_gate]:
		for node in gate.get_children(true):
			assert_ne(str(node.name), "Building", "%s has no building" % gate.label())


func test_the_building_is_in_the_stations_colour() -> void:
	await frames(2)
	for station: Station in [central, mine, factory, halt]:
		var walls := _walls(station).material_override as StandardMaterial3D
		var roof := _roof(station).material_override as StandardMaterial3D
		assert_eq(walls.albedo_color, station.color(), "%s's walls are its colour" % station.label())
		assert_less(roof.albedo_color.get_luminance(), walls.albedo_color.get_luminance(),
				"%s's roof is darker" % station.label())
	central.use_custom_color = true
	central.custom_color = Color(0.1, 0.6, 0.15)
	await frames(2)
	assert_eq((_walls(central).material_override as StandardMaterial3D).albedo_color,
			Color(0.1, 0.6, 0.15), "a colour set by hand repaints the building")


func test_the_building_stands_beside_the_outermost_track_on_its_side() -> void:
	var south := _track_named(central, "South")
	var at := _beside(central, south, central.building().global_position)
	note("Central's building from the south track's mark: %.2f along, %.2f up, %.2f right" % [
			at.x, at.y, at.z])
	assert_eq(central.building_side, Station.Side.RIGHT, "the demo leaves Central's building on the right")
	assert_near(at.z, Station.BUILDING_GAP + Station.BUILDING_SIZE.z * 0.5, 0.05,
			"its middle is the gap and half its depth right of the south track, the outermost")
	assert_near(at.x, 0.0, 0.05, "level with the mark")
	for track in central.tracks():
		var from_track := _beside(central, track, central.building().global_position)
		assert_greater(from_track.z, Station.BUILDING_GAP + Station.BUILDING_SIZE.z * 0.5 - 0.05,
				"no track runs between it and %s" % track.name)


func test_the_building_moves_to_the_other_side_beside_the_loop() -> void:
	central.building_side = Station.Side.LEFT
	await frames(1)
	if not assert_not_null(central.building(), "Central still has a building"):
		return
	var loop := _track_named(central, "Loop")
	var at := _beside(central, loop, central.building().global_position)
	note("on the left, from the loop's mark: %.2f along, %.2f right" % [at.x, at.z])
	assert_near(at.z, -(Station.BUILDING_GAP + Station.BUILDING_SIZE.z * 0.5), 0.05,
			"it stands the gap and half its depth left of the loop, the outermost that side")
	assert_near(at.x, 0.0, 0.05, "level with the loop's mark")


func test_the_building_is_the_size_asked_for_and_faces_along_the_track() -> void:
	var building := central.building()
	var box := _walls(central).mesh as BoxMesh
	var extent := building.global_basis * box.size
	var first := central.tracks()[0]
	var forward := first.rail.sample_forward(first.distance)
	note("walls %s, in the world %s" % [box.size, extent])
	assert_near(absf(extent.dot(forward.normalized())), Station.BUILDING_SIZE.x, 0.05,
			"it is %.0f m long along the track" % Station.BUILDING_SIZE.x)
	assert_greater(absf(extent.y), Station.BUILDING_SIZE.y - 0.01,
			"at least %.1f m high, the eaves over the ground" % Station.BUILDING_SIZE.y)
	assert_near(absf(extent.dot(forward.cross(Vector3.UP).normalized())), Station.BUILDING_SIZE.z, 0.05,
			"and %.0f m deep" % Station.BUILDING_SIZE.z)


func test_the_building_stands_on_the_ground() -> void:
	for station: Station in [central, mine, factory, halt]:
		var building := station.building()
		var rail := station.tracks()[0].rail
		var ground = rail.ground_height_at(building.global_position)
		if not assert_not_null(ground, "there is ground under %s's building" % station.label()):
			continue
		assert_near(building.global_position.y, float(ground), 0.05,
				"%s's building stands on the ground" % station.label())
		var walls := _walls(station)
		var box := walls.mesh as BoxMesh
		var bottom := walls.global_position.y - box.size.y * 0.5
		var eaves := walls.global_position.y + box.size.y * 0.5
		assert_less(bottom, float(ground) + 0.01, "%s's walls reach into it" % station.label())
		assert_near(eaves - float(ground), Station.BUILDING_SIZE.y, 0.05,
				"%s's eaves are %.1f m over it" % [station.label(), Station.BUILDING_SIZE.y])


func test_a_station_with_no_side_has_no_building() -> void:
	central.building_side = Station.Side.NONE
	await frames(1)
	assert_null(central.building(), "no side, no building")
	central.building_side = Station.Side.RIGHT
	await frames(1)
	assert_not_null(central.building(), "and it comes back with a side")
#endregion



#region Platforms
## Each platform of [param station] as [code][track it runs along, middle relative to
## that track's mark (see [method _beside]), length, width][/code].
func _platforms(station: Station) -> Array[Array]:
	var found: Array[Array] = []
	for platform in station.platforms():
		var track := _track_named(station, str(platform.name).trim_prefix("Platform"))
		var pieces := platform.get_children()
		var first := pieces[0] as MeshInstance3D
		var last := pieces[-1] as MeshInstance3D
		var middle := (first.global_position + last.global_position) * 0.5
		var box := first.mesh as BoxMesh
		found.append([track, _beside(station, track, middle),
				first.global_position.distance_to(last.global_position) + box.size.z, box.size.x])
	return found


func test_central_has_an_island_by_the_loop_and_an_outer_platform_by_the_south_main() -> void:
	var platforms := _platforms(central)
	for entry in platforms:
		note("Central: along %s, %.2f m to the right, %.1f m long, %.1f m wide" % [
				(entry[0] as InterestTrack).name, (entry[1] as Vector3).z, entry[2], entry[3]])
	assert_eq(platforms.size(), 2, "the north main, 5 m from the south one, has no room for a platform of its own")
	var sides: Dictionary[String, float] = {}
	for entry in platforms:
		sides[str((entry[0] as InterestTrack).name)] = (entry[1] as Vector3).z
	assert_true(sides.has("Loop"), "an island along the loop")
	assert_near(sides.get("Loop", 0.0), 5.0, 0.1, "halfway between the loop and the north main")
	assert_true(sides.has("South"), "an outer platform along the south main")
	assert_near(sides.get("South", 0.0), Station.PLATFORM_EDGE + Station.PLATFORM_WIDTH * 0.5, 0.1,
			"on the south main's outer side, towards the building")


func test_a_two_track_halt_has_a_platform_on_each_outer_side() -> void:
	var sides: Array[float] = []
	for entry in _platforms(halt):
		sides.append((entry[1] as Vector3).z)
	sides.sort()
	assert_eq(sides.size(), 2, "the Halt has two platforms")
	if sides.size() == 2:
		var outer := Station.PLATFORM_EDGE + Station.PLATFORM_WIDTH * 0.5
		assert_near(sides[0], -outer, 0.1, "one north of the north main")
		assert_near(sides[1], outer, 0.1, "one south of the south main")


func test_a_platform_runs_the_length_of_its_track_and_stands_low() -> void:
	for station: Station in [central, halt, factory]:
		for entry in _platforms(station):
			var track := entry[0] as InterestTrack
			var at := entry[1] as Vector3
			# Measured end to end beside the track: on the outside of a curve - the
			# factory's - a little longer than along the rail.
			assert_near(entry[2] as float, track.platform_length, 1.0,
					"%s/%s's platform is as long as the track's" % [station.label(), track.name])
			assert_near(at.x, 0.0, 0.5, "%s/%s's platform is centred on the mark" % [
					station.label(), track.name])
	# The tops: PLATFORM_HEIGHT above the railhead.
	var piece := halt.platforms()[0].get_child(0) as MeshInstance3D
	var box := piece.mesh as BoxMesh
	var top := piece.global_position.y + box.size.y * 0.5
	assert_near(top, halt.tracks()[0].position().y + Station.PLATFORM_HEIGHT, 0.05,
			"a platform's top is just above the railhead")


func test_a_platform_follows_its_tracks_length() -> void:
	var track := _track_named(halt, "North")
	track.platform_length = 60.0
	await frames(1)
	for entry in _platforms(halt):
		if entry[0] == track:
			assert_near(entry[2] as float, 60.0, 0.5, "a shorter platform is rebuilt shorter")


func test_the_platforms_are_in_the_stations_colour() -> void:
	await frames(2)
	var piece := central.platforms()[0].get_child(0) as MeshInstance3D
	var material := piece.material_override as StandardMaterial3D
	assert_eq(material.albedo_color, central.color().lightened(0.25),
			"a platform is a lighter shade of the station's colour")
	central.use_custom_color = true
	central.custom_color = Color(0.1, 0.6, 0.15)
	await frames(2)
	assert_eq(material.albedo_color, Color(0.1, 0.6, 0.15).lightened(0.25),
			"a colour set by hand repaints the platforms")
#endregion

#region Exit and entry signals
func test_a_station_track_finds_its_exit_signals_whatever_they_show() -> void:
	var north := _track_named(central, "North")
	assert_eq(north.guarding_signal(1), signal_named("CentralEastExitNorth"),
			"Central's north track is left eastwards past CentralEastExitNorth")
	assert_eq(north.guarding_signal(-1), signal_named("CentralWestExitNorth"), "and westwards past CentralWestExitNorth")
	clear(["CentralEastExitNorth"])
	assert_eq(north.guarding_signal(1), signal_named("CentralEastExitNorth"), "at clear it is still the exit signal")


func test_a_signal_applies_to_its_direction_whatever_it_shows_and_blocks_only_at_danger() -> void:
	var exit_signal := signal_named("CentralEastExitNorth")
	assert_true(exit_signal.applies_to(north_main, 1), "an eastbound train sees the eastbound signal")
	assert_false(exit_signal.applies_to(north_main, -1), "a westbound one does not")
	assert_false(exit_signal.applies_to(south_main, 1), "nor does a train on another rail")
	assert_true(exit_signal.blocks(north_main, 1), "at danger it stops the eastbound train")
	clear(["CentralEastExitNorth"])
	assert_true(exit_signal.applies_to(north_main, 1), "at clear it still applies")
	assert_false(exit_signal.blocks(north_main, 1), "but stops nothing")
	var walk := TrackWalker.walk(north_main, mark(central, north_main), 1, 500.0,
			TrackWalker.OBEY_ALL_SIGNALS, [], true)
	assert_eq(walk.blocking_signal, exit_signal, "a walk taking any aspect still ends at it")
	walk = TrackWalker.walk(north_main, mark(central, north_main), 1, 500.0,
			TrackWalker.OBEY_ALL_SIGNALS)
	assert_ne(walk.blocking_signal, exit_signal, "a walk obeying aspects goes past it at clear")


func test_a_signal_beyond_the_points_is_no_exit_signal() -> void:
	var track_b := _track_named(mine, "TrackB")
	var own := signal_named("MineExitTrackB")
	assert_eq(track_b.guarding_signal(-1), own, "loading track B is left past MineExitTrackB")
	own.get_parent().remove_child(own)
	assert_null(track_b.guarding_signal(-1),
			"without it there is none: the junction's signal is beyond the points")
	demo.get_node("Signals").add_child(own)


func test_a_station_track_without_an_exit_signal_is_warned_about() -> void:
	assert_true(central._get_configuration_warnings().is_empty(), "Central starts without warnings")
	var exit_signal := signal_named("CentralEastExitNorth")
	exit_signal.get_parent().remove_child(exit_signal)
	var warnings := central._get_configuration_warnings()
	note(", ".join(warnings))
	assert_eq(warnings.size(), 1, "one way off one track has lost its exit signal")
	assert_true(warnings.size() == 1 and warnings[0].contains("North"), "the north track is named")
	demo.get_node("Signals").add_child(exit_signal)
	assert_true(central._get_configuration_warnings().is_empty(), "and the warning goes with the signal back")


func test_an_exit_signal_on_the_platform_is_warned_about() -> void:
	var track := _track_named(central, "North")
	var exit_signal := signal_named("CentralEastExitNorth")
	var was := exit_signal.distance
	exit_signal.distance = track.stop_distance(1) + Station.EXIT_CLEARANCE - 1.0
	var warnings := central._get_configuration_warnings()
	note(", ".join(warnings))
	assert_eq(warnings.size(), 1, "an exit signal %.0f m past the platform's end is warned about" % (
			Station.EXIT_CLEARANCE - 1.0))
	assert_true(warnings.size() == 1 and warnings[0].contains("stands on the platform"),
			"as standing on the platform")
	exit_signal.distance = track.stop_distance(1) + Station.EXIT_CLEARANCE + 0.5
	assert_true(central._get_configuration_warnings().is_empty(),
			"%.1f m past it is far enough" % (Station.EXIT_CLEARANCE + 0.5))
	exit_signal.distance = was
	track.platform_length = 200.0
	assert_false(central._get_configuration_warnings().is_empty(),
			"a platform lengthened past its exit signals is warned about")
	track.platform_length = 120.0
	assert_true(central._get_configuration_warnings().is_empty(), "and the warning goes with it")


func test_a_dead_end_needs_no_exit_signal_towards_the_buffer() -> void:
	var siding := _track_named(factory, "Siding")
	assert_null(siding.guarding_signal(1), "nothing guards the factory siding towards its buffer")
	assert_true(factory._get_configuration_warnings().is_empty(), "and the factory is not warned about it")
	var exit_signal := signal_named("FactoryExitSiding")
	exit_signal.get_parent().remove_child(exit_signal)
	assert_false(factory._get_configuration_warnings().is_empty(),
			"the way out towards the junction does need one")
	demo.get_node("Signals").add_child(exit_signal)


func test_a_gate_track_that_takes_trains_needs_an_entry_signal() -> void:
	var north := west_gate.tracks()[0]
	assert_eq(north.guarding_signal(1), signal_named("CentralWestEntryNorth"),
			"the west gate's north track is entered past CentralWestEntryNorth")
	var entry := signal_named("CentralWestEntryNorth")
	entry.get_parent().remove_child(entry)
	var warnings := west_gate._get_configuration_warnings()
	note(", ".join(warnings))
	assert_eq(warnings.size(), 1, "the gate warns of the missing entry signal")
	north.role = InterestTrack.Role.OUT
	assert_true(west_gate._get_configuration_warnings().is_empty(),
			"a track that only takes trains off the level needs none")
	north.role = InterestTrack.Role.BOTH
	demo.get_node("Signals").add_child(entry)
	assert_true(west_gate._get_configuration_warnings().is_empty(), "and with the signal back the warning goes")
#endregion
