extends SceneTree
## Builds the stations demo, [code]scenes/demos/stations.tscn[/code].
##
## [codeblock]
## godot --headless --path . --script res://tools/build_stations_demo.gd
## [/codeblock]
##
## A double-track main line across flat ground, west to east, with an S-bend at each
## end and an outside connection beyond each: the West and East gates. In the middle,
## on the straight, Central station spans both mains and a platform loop on the north
## side. West of Central a branch leaves the south main for the Mine, two dead-end
## loading tracks to the south-west; east of it a siding leaves the north main for the
## Factory, to the north-east. A Halt stands on both mains between the factory and the
## East gate.
##
## As at a real station, a train can go from any track of Central or the Halt to any
## track on either side of it: a scissors crossover between the mains at each end of
## both, with Central's loop joining the north main inside its pair. The loop stands
## far enough out for an island platform between it and the north main.
##
## Signalled the way stations are: every signal starts at danger; Central and the Halt
## each have an entry signal on both mains outside their outermost points, and every
## station track an exit signal each way (only away from the buffer on a dead end) a
## few metres past the end of its platform. The points between them - a station's
## throat, the mine's and the factory's junctions - have none of their own: whatever
## way a train comes at them, it has passed an entry or an exit signal on the way. The
## Halt's east entry signals are the East gate's too; Central's west ones the West
## gate's. A new train is put down with its nose on a gate's mark and the rest of it
## outside, so each gate mark has room for the longest train between it and the end of
## the rail. The script is the source: a re-run overwrites the scene, and an edit made
## to it in the editor is lost unless it is made here too.
##
## Coordinates are x east, z south; headings in degrees clockwise from +X seen from
## above (0 east, 90 south).

const Kit := preload("res://tools/scene_kit.gd")
const Track := Kit.Track

const SCENE_PATH := "res://scenes/demos/stations.tscn"

const RAILHEAD := 0.25
const BED_DEPTH := 0.25
const GROUND_SIZE := Vector2(2000.0, 400.0)

## The main line's centre: from the west end at z = -WEST_Z, an S-bend down onto the
## straight at z = 0 from -WEST_STRAIGHT_X to EAST_STRAIGHT_X, and another down to z =
## EAST_Z. The east half is the longer: it holds the Halt and its two crossovers.
const WEST_END_X := 740.0
const EAST_END_X := 980.0
const WEST_STRAIGHT_X := 460.0
const EAST_STRAIGHT_X := 700.0
const WEST_Z := -40.0
const EAST_Z := 40.0
const BEND_RADIUS := 200.0
## The two mains either side of the centre line.
const HALF_SPACING := 2.5
## A scissors crossover changes track over this length.
const LINK_LENGTH := 36.0
## Central's loop runs this far north of the north main - room for an island platform
## between them - and swings out to it over LOOP_BEND.
const LOOP_OFFSET := 10.0
const LOOP_BEND := 60.0

## Junctions, stations and entry signals on the straight, by x, west to east.
const CENTRAL_WEST_ENTRY_X := -420.0
const MINE_JUNCTION_X := -380.0
## A scissors crossover spans from its x to x + LINK_LENGTH.
const WEST_CROSSOVER_X := -330.0
const LOOP_WEST_X := -250.0
const CENTRAL_X := -80.0
const LOOP_EAST_X := 90.0
const EAST_CROSSOVER_X := 130.0
const FACTORY_JUNCTION_X := 220.0
const CENTRAL_EAST_ENTRY_X := 260.0
const HALT_WEST_ENTRY_X := 310.0
const HALT_WEST_CROSSOVER_X := 340.0
const HALT_X := 480.0
const HALT_EAST_CROSSOVER_X := 580.0
const HALT_EAST_ENTRY_X := 650.0

## The mine branch: an arc away south-west, then straight; the split onto the second
## loading track SPLIT along it.
const MINE_RADIUS := 120.0
const MINE_SWING := 40.0
const MINE_BRANCH_LENGTH := 230.0
const MINE_SPLIT := 92.0
const MINE_MARK := 172.0
const MINE_SIDING_RADIUS := 165.0
const MINE_SIDING_SWING := 10.0
const MINE_SIDING_LENGTH := 145.0
const MINE_SIDING_MARK := 95.0
## The factory siding: an arc away north-east, then straight to a buffer.
const FACTORY_RADIUS := 150.0
const FACTORY_SWING := 30.0
const FACTORY_STRAIGHT := 90.0
const FACTORY_MARK := 100.0

## A gate's mark is this far from the end of its rail: room for the longest train the
## routes send in (70 m, a freight) and some.
const GATE_MARK := 80.0
## An exit signal stands this far past the end of its platform.
const EXIT_SIGNAL := 5.0
## Platform lengths, centred on each mark. A train stops with its nose on the end it
## is heading for, and the exit signal that way stands at least 3 m beyond.
const CENTRAL_PLATFORM := 120.0
const PLATFORM := 90.0

## Checked before writing: no station mark this close to any points.
const MARK_CLEAR_OF_POINTS := 50.0

## Short names for the scripts' enum values the layout is written in.
const DIVERGE_START := Turnout.DivergeTowards.RAIL_START
const DIVERGE_END := Turnout.DivergeTowards.RAIL_END
const BRANCH_START := Turnout.RailEnd.START
const BRANCH_END := Turnout.RailEnd.END
const TOWARDS_END := RailSignal.Governs.TOWARDS_RAIL_END
const TOWARDS_START := RailSignal.Governs.TOWARDS_RAIL_START
const COMPOUND_DOUBLE_CROSSOVER := CompoundTurnout.Kind.DOUBLE_CROSSOVER
const CARGO_LOAD := Station.Cargo.LOAD
const CARGO_UNLOAD := Station.Cargo.UNLOAD

const _TRAIN_TYPES := {
	"express": ["res://train_types/express.tres", "type_express"],
	"local": ["res://train_types/local.tres", "type_local"],
	"loaded": ["res://train_types/loaded_freight.tres", "type_loaded"],
	"empty": ["res://train_types/empty_freight.tres", "type_empty"],
}


var _curves: Dictionary[String, Curve3D] = {}
var _rail_order: Array[String] = []
var _turnouts: Array[Dictionary] = []
var _compounds: Array[Dictionary] = []
var _crossings: Array[Dictionary] = []
var _signals: Array[Dictionary] = []
## Interest points in scene order: name, script id, display name, extra lines, tracks.
var _points: Array[Dictionary] = []
var _routes: Array[Dictionary] = []


func _initialize() -> void:
	_lay_out_rails()
	_place_junctions()
	_place_points()
	_place_signals()
	_place_routes()
	var problems := _check()
	if not problems.is_empty():
		for problem in problems:
			push_error(problem)
		quit(1)
		return
	if not Kit.write_scene(SCENE_PATH, _scene_text()):
		quit(1)
		return
	print("Wrote %s: %d rails, %d turnouts, %d crossings, %d signals, %d interest points, %d routes"
			% [SCENE_PATH, _rail_order.size(), Kit.all_turnouts(_turnouts, _compounds).size(),
			_crossings.size(), _signals.size(), _points.size(), _routes.size()])
	quit(0)


#region Rails
func _lay_out_rails() -> void:
	# The S-bends: two opposite arcs that between them shift the line by |WEST_Z|.
	var west_turn := rad_to_deg(acos(1.0 - absf(WEST_Z) / (2.0 * BEND_RADIUS)))
	var east_turn := rad_to_deg(acos(1.0 - absf(EAST_Z) / (2.0 * BEND_RADIUS)))
	var west_reach := 2.0 * BEND_RADIUS * sin(deg_to_rad(west_turn))
	var centre := (Track.new(Vector2(-WEST_END_X, WEST_Z), 0.0)
			.line_to_x(-WEST_STRAIGHT_X - west_reach)
			.arc(BEND_RADIUS, west_turn).arc(BEND_RADIUS, -west_turn)
			.line_to_x(EAST_STRAIGHT_X)
			.arc(BEND_RADIUS, east_turn).arc(BEND_RADIUS, -east_turn)
			.line_to_x(EAST_END_X))
	_add("NorthMain", centre.offset(-HALF_SPACING))
	_add("SouthMain", centre.offset(HALF_SPACING))

	var north := -HALF_SPACING
	var south := HALF_SPACING
	# The platform loop leaves the north main and rejoins it, LOOP_OFFSET further north.
	_add("CentralLoop", Track.new(Vector2(LOOP_WEST_X, north), 0.0)
			.to(Vector2(LOOP_WEST_X + LOOP_BEND, north - LOOP_OFFSET), 0.0)
			.line_to_x(LOOP_EAST_X - LOOP_BEND)
			.to(Vector2(LOOP_EAST_X, north), 0.0))
	# The scissors crossovers: two links each, one down from the north main onto the
	# south one, one up, crossing in the middle.
	for scissors: Array in _scissors():
		var x: float = scissors[1]
		_add("%sDown" % scissors[0], Track.new(Vector2(x, north), 0.0)
				.to(Vector2(x + LINK_LENGTH, south), 0.0))
		_add("%sUp" % scissors[0], Track.new(Vector2(x, south), 0.0)
				.to(Vector2(x + LINK_LENGTH, north), 0.0))

	# The mine branch leaves the south main heading west and swings away south-west.
	var branch := (Track.new(Vector2(MINE_JUNCTION_X, south), 180.0)
			.arc(MINE_RADIUS, -MINE_SWING))
	var arc_length := MINE_RADIUS * deg_to_rad(MINE_SWING)
	_add("MineBranch", branch.line(MINE_BRANCH_LENGTH - arc_length))
	# The second loading track: an S-bend one track over, to the south-east side.
	var split := _at_along("MineBranch", MINE_SPLIT)
	var siding_arcs := 2.0 * MINE_SIDING_RADIUS * deg_to_rad(MINE_SIDING_SWING)
	_add("MineSiding", Track.new(split, branch.heading())
			.arc(MINE_SIDING_RADIUS, -MINE_SIDING_SWING)
			.arc(MINE_SIDING_RADIUS, MINE_SIDING_SWING)
			.line(MINE_SIDING_LENGTH - siding_arcs))

	# The factory siding leaves the north main heading east and swings away north-east.
	_add("FactorySiding", Track.new(Vector2(FACTORY_JUNCTION_X, north), 0.0)
			.arc(FACTORY_RADIUS, -FACTORY_SWING).line(FACTORY_STRAIGHT))


## Each scissors crossover: its name and the x its west end is at.
func _scissors() -> Array[Array]:
	return [
		["WestCrossover", WEST_CROSSOVER_X],
		["EastCrossover", EAST_CROSSOVER_X],
		["HaltWestCrossover", HALT_WEST_CROSSOVER_X],
		["HaltEastCrossover", HALT_EAST_CROSSOVER_X],
	]


## The point [param along] metres down [param rail], in plan.
func _at_along(rail: String, along: float) -> Vector2:
	var at := _curves[rail].sample_baked(along)
	return Vector2(at.x, at.z)


func _add(rail: String, track: Track) -> void:
	_curves[rail] = Kit.curve(track, RAILHEAD)
	_rail_order.append(rail)


## Metres along [param rail] to the point nearest [param point].
func _distance(rail: String, point: Vector2) -> float:
	return _curves[rail].get_closest_offset(Kit.world(point, RAILHEAD))


func _length(rail: String) -> float:
	return _curves[rail].get_baked_length()
#endregion


#region Junctions
func _place_junctions() -> void:
	var north := -HALF_SPACING
	var south := HALF_SPACING
	_turnouts.append(_turnout("MineJunction", "Turnouts", "SouthMain",
			_distance("SouthMain", Vector2(MINE_JUNCTION_X, south)), DIVERGE_START,
			"MineBranch", BRANCH_START))
	_turnouts.append(_turnout("MineSplit", "Turnouts", "MineBranch", MINE_SPLIT, DIVERGE_END,
			"MineSiding", BRANCH_START))
	_turnouts.append(_turnout("LoopWest", "Turnouts", "NorthMain",
			_distance("NorthMain", Vector2(LOOP_WEST_X, north)), DIVERGE_END,
			"CentralLoop", BRANCH_START))
	_turnouts.append(_turnout("LoopEast", "Turnouts", "NorthMain",
			_distance("NorthMain", Vector2(LOOP_EAST_X, north)), DIVERGE_START,
			"CentralLoop", BRANCH_END))
	_turnouts.append(_turnout("FactoryJunction", "Turnouts", "NorthMain",
			_distance("NorthMain", Vector2(FACTORY_JUNCTION_X, north)), DIVERGE_END,
			"FactorySiding", BRANCH_START))

	# Each scissors: the four points, toes facing outwards, and the crossing where its
	# two links cross.
	for scissors: Array in _scissors():
		var name: String = scissors[0]
		var x: float = scissors[1]
		var parent := "Compounds/%s" % name
		var down := "%sDown" % name
		var up := "%sUp" % name
		_compounds.append({"name": name, "kind": COMPOUND_DOUBLE_CROSSOVER, "members": [
			_turnout("NorthWest", parent, "NorthMain", _distance("NorthMain", Vector2(x, north)),
					DIVERGE_END, down, BRANCH_START),
			_turnout("SouthEast", parent, "SouthMain",
					_distance("SouthMain", Vector2(x + LINK_LENGTH, south)), DIVERGE_START, down,
					BRANCH_END),
			_turnout("SouthWest", parent, "SouthMain", _distance("SouthMain", Vector2(x, south)),
					DIVERGE_END, up, BRANCH_START),
			_turnout("NorthEast", parent, "NorthMain",
					_distance("NorthMain", Vector2(x + LINK_LENGTH, north)), DIVERGE_START, up,
					BRANCH_END),
		]})
		var middle := Vector2(x + LINK_LENGTH * 0.5, 0.0)
		_crossings.append({"name": "%sMiddle" % name, "a": down, "distance_a": _distance(down,
				middle), "b": up, "distance_b": _distance(up, middle)})


func _turnout(name: String, parent: String, main: String, distance: float, diverge: int,
		branch: String, end: int) -> Dictionary:
	return {"name": name, "parent": parent, "main": main, "distance": distance,
			"diverge": diverge, "branch": branch, "end": end}

#endregion


#region Signals
## Station signalling: an entry signal on both mains outside each end of Central and
## of the Halt, an exit signal each way off every station track, and nothing at the
## points in between.
func _place_signals() -> void:
	for rail: String in ["NorthMain", "SouthMain"]:
		var stem := "North" if rail == "NorthMain" else "South"
		for entry: Array in [
			["CentralWestEntry", CENTRAL_WEST_ENTRY_X, TOWARDS_END],
			["CentralEastEntry", CENTRAL_EAST_ENTRY_X, TOWARDS_START],
			["HaltWestEntry", HALT_WEST_ENTRY_X, TOWARDS_END],
			["HaltEastEntry", HALT_EAST_ENTRY_X, TOWARDS_START],
		]:
			_add_signal("%s%s" % [entry[0], stem], rail,
					_distance(rail, Vector2(entry[1] as float, 0.0)), entry[2] as int)
	# The exits, past both ends of the platforms; one only, towards the points, off a
	# dead end.
	for point in _points:
		if point["kind"] != "station":
			continue
		var half: float = point["platform"] * 0.5 + EXIT_SIGNAL
		for track: Array in point["tracks"]:
			var rail: String = track[1]
			var mark: float = track[2]
			if rail in ["MineBranch", "MineSiding", "FactorySiding"]:
				_add_signal("%sExit%s" % [point["name"], track[0]], rail, mark - half,
						TOWARDS_START)
			else:
				_add_signal("%sWestExit%s" % [point["name"], track[0]], rail, mark - half,
						TOWARDS_START)
				_add_signal("%sEastExit%s" % [point["name"], track[0]], rail, mark + half,
						TOWARDS_END)


func _add_signal(name: String, rail: String, distance: float, governs: int) -> void:
	assert(distance > 0.0 and distance < _length(rail), "%s is off %s" % [name, rail])
	_signals.append({"name": name, "rail": rail, "distance": distance, "governs": governs})
#endregion


#region Interest points and routes
func _place_points() -> void:
	var gate_west: Array[Array] = []
	var gate_east: Array[Array] = []
	var central: Array[Array] = []
	var halt: Array[Array] = []
	for rail: String in ["NorthMain", "SouthMain"]:
		var stem := "North" if rail == "NorthMain" else "South"
		gate_west.append([stem, rail, GATE_MARK])
		gate_east.append([stem, rail, _length(rail) - GATE_MARK])
		central.append([stem, rail, _distance(rail, Vector2(CENTRAL_X, 0.0))])
		halt.append([stem, rail, _distance(rail, Vector2(HALT_X, 0.0))])
	central.push_front(["Loop", "CentralLoop", _distance("CentralLoop",
			Vector2(CENTRAL_X, -HALF_SPACING - LOOP_OFFSET))])

	_points.append(_point("WestGate", "connection", "West", [], gate_west, 0.0))
	_points.append(_point("Central", "station", "Central", ["dwell_time = 6.0"], central,
			CENTRAL_PLATFORM))
	_points.append(_point("Mine", "station", "Mine",
			["dwell_time = 8.0", "cargo = %d" % CARGO_LOAD],
			[["TrackA", "MineBranch", MINE_MARK], ["TrackB", "MineSiding", MINE_SIDING_MARK]],
			PLATFORM))
	_points.append(_point("Factory", "station", "Factory",
			["dwell_time = 8.0", "cargo = %d" % CARGO_UNLOAD],
			[["Siding", "FactorySiding", FACTORY_MARK]], PLATFORM))
	_points.append(_point("Halt", "station", "Halt", ["dwell_time = 4.0"], halt, PLATFORM))
	_points.append(_point("EastGate", "connection", "East", [], gate_east, 0.0))


func _point(name: String, kind: String, display: String, extra: Array[String],
		tracks: Array[Array], platform: float) -> Dictionary:
	return {"name": name, "kind": kind, "display": display, "extra": extra, "tracks": tracks,
			"platform": platform}


## The mine branch faces trains coming from the east and the factory siding trains
## from the west, so a freight goes in and out by the same gate: it backs out of a
## dead end the way it came.
func _place_routes() -> void:
	_routes.append(_route("Express", ["express"], ["WestGate"], ["Central", "EastGate"]))
	_routes.append(_route("ExpressWest", ["express"], ["EastGate"], ["Central", "WestGate"]))
	_routes.append(_route("Local", ["local"], ["WestGate"], ["Central", "Halt", "EastGate"]))
	_routes.append(_route("LocalWest", ["local"], ["EastGate"], ["Halt", "Central", "WestGate"]))
	_routes.append(_route("Coal", ["empty"], ["EastGate"], ["Mine", "EastGate"]))
	_routes.append(_route("Deliveries", ["loaded"], ["WestGate"], ["Factory", "WestGate"]))
	_routes.append(_route("StationLocal", ["local"], ["Central"], ["Halt", "EastGate"]))


func _route(name: String, types: Array[String], entries: Array[String],
		stops: Array[String]) -> Dictionary:
	return {"name": name, "types": types, "entries": entries, "stops": stops}
#endregion


#region Checks
## The rules the layout is built to, checked on the numbers before anything is written.
## Done again on the loaded scene by a check script; here so that a changed constant
## fails at once.
func _check() -> Array[String]:
	var problems: Array[String] = []
	for point in _points:
		for track: Array in point["tracks"]:
			var rail: String = track[1]
			var mark: float = track[2]
			if point["kind"] == "station":
				for turnout in Kit.all_turnouts(_turnouts, _compounds):
					for at in _turnout_distances(turnout, rail):
						if absf(at - mark) < MARK_CLEAR_OF_POINTS:
							problems.append("%s/%s is %.1f m from %s" % [point["name"], track[0],
									absf(at - mark), turnout["name"]])
	return problems


func _turnout_distances(turnout: Dictionary, rail: String) -> Array[float]:
	var found: Array[float] = []
	if turnout["main"] == rail:
		found.append(turnout["distance"])
	if turnout["branch"] == rail:
		found.append(0.0 if turnout["end"] == BRANCH_START else _length(rail))
	return found
#endregion


#region Scene text
func _scene_text() -> String:
	var lines := PackedStringArray()
	lines.append("[gd_scene format=3]")
	lines.append("")
	for entry: Array in [
		["Script", "res://scripts/world/ground.gd", "ground"],
		["Script", "res://scripts/rails/rail.gd", "rail"],
		# No node uses it, but loading Train early, as the other levels do, keeps the
		# scripts' class-name cycles from holding each other alive at exit: without it a
		# run ends in "resources still in use" errors.
		["Script", "res://scripts/trains/train.gd", "train"],
		["Script", "res://scripts/rails/turnout.gd", "turnout"],
		["Script", "res://scripts/rails/compound_turnout.gd", "compound"],
		["Script", "res://scripts/rails/crossing.gd", "crossing"],
		["Script", "res://scripts/rails/rail_signal.gd", "signal"],
		["Script", "res://scripts/traffic/station.gd", "station"],
		["Script", "res://scripts/traffic/outside_connection.gd", "connection"],
		["Script", "res://scripts/traffic/interest_track.gd", "interest_track"],
		["Script", "res://scripts/traffic/train_route.gd", "route"],
		["Script", "res://scripts/traffic/train_spawner.gd", "spawner"],
		["Script", "res://scripts/trains/train_type.gd", "train_type"],
		["Script", "res://scripts/track/track_mesher.gd", "mesher"],
		["Script", "res://scripts/debug/camera_rig.gd", "camera"],
		["Script", "res://scripts/debug/train_debug_panel.gd", "train_panel"],
		["Script", "res://scripts/debug/turnout_debug_panel.gd", "turnout_panel"],
		["Script", "res://scripts/debug/signal_debug_panel.gd", "signal_panel"],
		["Script", "res://scripts/debug/interest_debug_panel.gd", "interest_panel"],
		["Script", "res://scripts/debug/route_list_panel.gd", "route_panel"],
		["Script", "res://scripts/ui/marker_overlay.gd", "overlay"],
	]:
		lines.append('[ext_resource type="%s" path="%s" id="%s"]' % entry)
	for type: String in _TRAIN_TYPES:
		lines.append('[ext_resource type="Resource" path="%s" id="%s"]' % _TRAIN_TYPES[type])
	lines.append("")
	lines.append_array(Kit.environment_text())
	for rail in _rail_order:
		lines.append_array(Kit.curve_text(rail, _curves[rail]))

	lines.append('[node name="StationsDemo" type="Node3D"]')
	lines.append("")
	lines.append_array(Kit.world_environment_and_sun_text(700.0))
	lines.append('[node name="Ground" type="MeshInstance3D" parent="." groups=["snap_surface"]]')
	lines.append('script = ExtResource("ground")')
	lines.append("size = Vector2(%s, %s)" % [Kit.num(GROUND_SIZE.x), Kit.num(GROUND_SIZE.y)])
	lines.append("subdivisions = 150")
	lines.append("hill_height = 0.0")
	lines.append("")

	lines.append_array(Kit.rails_text(_rail_order, "rail", BED_DEPTH))
	lines.append_array(Kit.turnouts_text(_turnouts, _compounds, "turnout", "compound"))
	lines.append_array(Kit.crossings_text(_crossings, "crossing"))

	lines.append_array(Kit.group("Interest"))
	for point in _points:
		lines.append('[node name="%s" type="Node3D" parent="Interest"]' % point["name"])
		lines.append('script = ExtResource("%s")' % point["kind"])
		lines.append('display_name = "%s"' % point["display"])
		lines.append_array(point["extra"] as Array[String])
		lines.append("")
		for track: Array in point["tracks"]:
			lines.append('[node name="%s" type="Node" parent="Interest/%s" ' % [track[0],
					point["name"]] + 'node_paths=PackedStringArray("rail")]')
			lines.append('script = ExtResource("interest_track")')
			lines.append('rail = NodePath("../../../Rails/%s")' % track[1])
			lines.append("distance = %s" % Kit.num(track[2]))
			if point["kind"] == "station":
				lines.append("platform_length = %s" % Kit.num(point["platform"]))
			lines.append("")

	lines.append_array(Kit.signals_text(_signals, "signal"))
	lines.append_array(Kit.group("Trains"))
	lines.append('[node name="Spawner" type="Node" parent="." '
			+ 'node_paths=PackedStringArray("trains_parent")]')
	lines.append('script = ExtResource("spawner")')
	lines.append("max_trains = 4")
	lines.append("min_spawn_interval = 60.0")
	lines.append("initial_trains = 2")
	lines.append("random_seed = 0")
	lines.append('trains_parent = NodePath("../Trains")')
	lines.append("")
	for route in _routes:
		var types := PackedStringArray()
		for type: String in route["types"]:
			types.append('ExtResource("%s")' % _TRAIN_TYPES[type][1])
		var entries := PackedStringArray()
		for entry: String in route["entries"]:
			entries.append('NodePath("../../Interest/%s")' % entry)
		var stops := PackedStringArray()
		for stop: String in route["stops"]:
			stops.append('NodePath("../../Interest/%s")' % stop)
		lines.append('[node name="%s" type="Node" parent="Spawner" ' % route["name"]
				+ 'node_paths=PackedStringArray("entries", "stops")]')
		lines.append('script = ExtResource("route")')
		lines.append('train_types = Array[ExtResource("train_type")]([%s])' % ", ".join(types))
		lines.append("entries = [%s]" % ", ".join(entries))
		lines.append("stops = [%s]" % ", ".join(stops))
		lines.append("")

	lines.append('[node name="Track" type="Node3D" parent="."]')
	lines.append('script = ExtResource("mesher")')
	lines.append("")
	lines.append_array(_camera_and_ui_text())
	return "\n".join(lines)


func _camera_and_ui_text() -> PackedStringArray:
	return Kit.camera_and_ui_text({"script": "camera", "origin": Vector3i(120, 0, 30),
			"yaw": 0.0, "pitch": -55.0, "zoom": 650.0, "max_zoom": 1400.0}, [
		["TrainDebugPanel", "train_panel", false],
		["TurnoutDebugPanel", "turnout_panel", true],
		["SignalDebugPanel", "signal_panel", true],
		["InterestDebugPanel", "interest_panel", false],
		["RouteListPanel", "route_panel", false],
	], "overlay")
#endregion
