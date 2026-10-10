extends SceneTree
## Builds the playground, [code]scenes/main.tscn[/code], and bakes the terrain under it.
##
## [codeblock]
## Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/build_playground.gd
## [/codeblock]
##
## The level is drawn here as plain geometry - straights and circular arcs, each rail
## a turtle walk - and written out as a hand-readable [code].tscn[/code] like the demo
## scenes, together with [code]scenes/main_heights.res[/code], the heightmap its ground
## is carved from. Running it again regenerates both from scratch, so an edit made to
## main.tscn in the editor is lost unless it is made here as well. What the level
## contains, and why it is shaped the way it is, is in docs/level_authoring.md.
##
## Coordinates below are the layout's own: x east, z south, the oval centred on the
## origin. [constant SHIFT] moves the whole level on the way out.

const SCENE_PATH := "res://scenes/main.tscn"
const HEIGHTS_PATH := "res://scenes/main_heights.res"

#region Layout
## Moves the layout so that the level as a whole - oval, wye and hill - sits centred
## on the ground, which is centred on the origin.
const SHIFT := Vector2(-110.0, 0.0)
## Every rail runs at this height, and the ground is carved to fit it.
const RAILHEAD := 0.25
## How far the bed sits under the railhead: [member Rail.surface_offset].
const BED_DEPTH := 0.25

## The double-track oval. Straights run from -STRAIGHT to +STRAIGHT along x, the outer
## track at z = +-OUTER and the inner one 5 m inside it; each end is a semicircle about
## (+-STRAIGHT, 0). The inner track has no east end of its own: it merges into the outer
## one at MERGE_X on both straights, so the east curve - where the wye leaves - is single.
const STRAIGHT := 130.0
const OUTER := 50.0
const INNER := 45.0
const MERGE_X := 100.0
## Crossovers, scissors and the merges all change track over this length.
const LINK_LENGTH := 36.0
const CROSSOVER_X := 0.0
const SCISSORS_X := 0.0
## Where the freight line crosses both south straights at right angles.
const DIAMOND_X := -60.0

## The balloon: a loop off the outer north straight, leaving at BALLOON_EAST_X and coming
## back at BALLOON_WEST_X - a quarter circle and three quarters of another, round a pond.
const LOOP_RADIUS := 32.0
const BALLOON_WEST_X := -90.0
const BALLOON_EAST_X := BALLOON_WEST_X + 2.0 * LOOP_RADIUS

## The wye: one leg off each straight at the east end, meeting at an apex further east,
## and a tail from the apex over a bridge and through a hill to a dead end.
const WYE_STRAIGHT := 20.0
const WYE_RADIUS := 60.0
const TAIL_END_X := 400.0

## The freight line: from a dead end south of the oval, straight north over both tracks,
## then east into the middle of the oval to cross the yard lead in the double slip.
const FREIGHT_START_Z := 120.0
const FREIGHT_TURN_Z := 30.0
const FREIGHT_TURN_RADIUS := 35.0
const GOODS_END_X := 120.0

## The yard, inside the oval: a lead off the inner north straight, the double slip where
## it crosses the freight line, then a three-way fanning into three dead-end roads.
const YARD_ENTRY_X := -100.0
const LEAD_RADIUS := 35.0
const LEAD_SWING := 50.0
const SLIP_X := 0.0
## The two tracks of the double slip cross at twice this, like the demo's.
const SLIP_HALF_ANGLE := 6.0
## How far either side of the diamond the slip's four sets of points stand.
const SLIP_REACH := 14.0
const THREE_WAY_AT := 40.0
const THREE_WAY_STAGGER := 4.0
const ROAD_RADIUS := 110.0
const ROAD_SWING := 12.0
const YARD_END_X := 125.0

## How far ahead of a junction its signals stand. Facing the points, a train only has
## to stop short of them; trailing in, it has to stop clear of the other leg.
const FACING_SIGNAL := 8.0
const TRAILING_SIGNAL := 30.0
const CROSSING_SIGNAL := 10.0
#endregion

#region Terrain
## Ground centred on the origin; a vertex every GRID metres.
const GROUND_SIZE := Vector2(660.0, 320.0)
const GRID := 2.0
## A hill across the wye's tail, high enough over the track for a tunnel.
const HILL_X := 345.0
const HILL_HALF_WIDTH := 45.0
const HILL_HEIGHT := 14.0
const HILL_FULL_Z := 60.0
const HILL_END_Z := 110.0
## A gully across the tail between the apex and the hill, deep enough for a bridge. It
## runs off the edge of the ground both ways, a stream in its bottom.
const GULLY_X := 285.0
const GULLY_HALF_WIDTH := 16.0
const GULLY_DEPTH := 6.0
const STREAM_LEVEL := -5.4
## A shallow pond inside the balloon loop.
const POND_DEPTH := 1.2
const POND_RADIUS := 24.0
const POND_LEVEL := -0.4
## Carving, as on the desert level: a flat bed either side of the centre line, cuttings at
## 1:1 and banks at 1:1.6 beyond it. Ground this far over the railhead is a tunnel and is
## kept a roof's height above it; ground this far under the bed is a bridge and is left be.
const BED_HALF_WIDTH := 3.0
const CUT_SLOPE := 1.0
const BANK_SLOPE := 1.6
const TUNNEL_COVER := 7.0
const TUNNEL_ROOF := 6.5
const BRIDGE_DROP := 1.5
const CARVE_REACH := 24.0
#endregion

const _CLEARANCE := 4.6

enum Kind { TRACK, TUNNEL, BRIDGE }


## A rail drawn as a turtle walk in plan: a list of poses, each a point and the heading
## the track has there in degrees clockwise from +X seen from above - 0 is east, 90 is
## south. Consecutive poses become one cubic segment of the curve.
class Track:
	var points: Array[Vector2] = []
	var headings: Array[float] = []

	func _init(start: Vector2, toward: float) -> void:
		points.append(start)
		headings.append(toward)


	func position() -> Vector2:
		return points[-1]


	func heading() -> float:
		return headings[-1]


	func line(length: float) -> Track:
		return to(position() + direction(heading()) * length, heading())


	## Straight on until x reaches [param x].
	func line_to_x(x: float) -> Track:
		return line((x - position().x) / direction(heading()).x)


	## Straight on until z reaches [param z].
	func line_to_z(z: float) -> Track:
		return line((z - position().y) / direction(heading()).y)


	## Right for positive [param degrees], left for negative. Split into steps of at most
	## 45 degrees, which a cubic follows to within a few millimetres.
	func arc(radius: float, degrees: float) -> Track:
		var steps := maxi(1, ceili(absf(degrees) / 45.0 - 1e-6))
		var step := degrees / float(steps)
		for _i in steps:
			var centre := position() + direction(heading() + 90.0 * signf(degrees)) * radius
			var arm := (position() - centre).rotated(deg_to_rad(step))
			to(centre + arm, heading() + step)
		return self


	## Any pose at all, joined to the last by a cubic leaving and arriving along the two
	## headings - an S-bend when they are parallel.
	func to(point: Vector2, toward: float) -> Track:
		points.append(point)
		headings.append(toward)
		return self


	static func direction(degrees: float) -> Vector2:
		return Vector2.from_angle(deg_to_rad(degrees))


var _tracks: Dictionary[String, Track] = {}
var _curves: Dictionary[String, Curve3D] = {}
var _rail_order: Array[String] = []
var _turnouts: Array[Dictionary] = []
var _compounds: Array[Dictionary] = []
var _crossings: Array[Dictionary] = []
var _signals: Array[Dictionary] = []
var _trains: Array[Dictionary] = []
## Where the wye's legs meet, and where the yard lead and the freight line cross.
var _apex := Vector2.ZERO
var _slip := Vector2.ZERO
var _wye_angle := 0.0


func _initialize() -> void:
	_lay_out_rails()
	_place_junctions()
	_place_signals()
	_place_trains()
	_check_clearances()
	var heights := _bake_terrain()
	var error := ResourceSaver.save(heights, HEIGHTS_PATH)
	if error != OK:
		push_error("Could not save %s: %s" % [HEIGHTS_PATH, error_string(error)])
		quit(1)
		return
	var file := FileAccess.open(SCENE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not write %s" % SCENE_PATH)
		quit(1)
		return
	file.store_string(_scene_text())
	file.close()
	print("Wrote %s: %d rails, %d turnouts, %d assemblies, %d crossings, %d signals, %d trains"
			% [SCENE_PATH, _rail_order.size(), _turnout_count(), _compounds.size(),
			_crossings.size(), _signals.size(), _trains.size()])
	quit(0)


#region Rails
func _lay_out_rails() -> void:
	# Each wye leg is a straight and two opposite arcs of WYE_RADIUS, which between them
	# have to cover the OUTER metres from a straight to the apex - so each turns this far.
	_wye_angle = rad_to_deg(acos(1.0 - OUTER / (2.0 * WYE_RADIUS)))
	_apex = Vector2(STRAIGHT + WYE_STRAIGHT + 2.0 * WYE_RADIUS * sin(deg_to_rad(_wye_angle)), 0.0)

	# Two rails only ever meet at a turnout, and a rail welded to itself draws a
	# warning, so every loop is cut where something else leaves it. The outer track is
	# two rails: NorthLine runs from the wye's apex along the north straight and round
	# the balloon, and OuterLine from the balloon's other end round the rest of the oval
	# to the foot of the north wye leg.
	_add("NorthLine", Track.new(_apex, 180.0)
			.arc(WYE_RADIUS, _wye_angle).arc(WYE_RADIUS, -_wye_angle).line(WYE_STRAIGHT)
			.line_to_x(MERGE_X).line_to_x(CROSSOVER_X).line_to_x(BALLOON_EAST_X)
			.arc(LOOP_RADIUS, 90.0).arc(LOOP_RADIUS, -270.0))
	_add("OuterLine", Track.new(Vector2(BALLOON_EAST_X, -OUTER), 180.0)
			.line_to_x(BALLOON_WEST_X).line_to_x(-STRAIGHT).arc(OUTER, -180.0)
			.line_to_x(DIAMOND_X).line_to_x(SCISSORS_X).line_to_x(SCISSORS_X + LINK_LENGTH)
			.line_to_x(MERGE_X).line_to_x(STRAIGHT).arc(OUTER, -180.0))
	# The inner track starts and ends on the outer one, at the two merges.
	_add("InnerLine", Track.new(Vector2(MERGE_X, OUTER), 180.0)
			.to(Vector2(MERGE_X - LINK_LENGTH, INNER), 180.0)
			.line_to_x(SCISSORS_X + LINK_LENGTH).line_to_x(SCISSORS_X).line_to_x(DIAMOND_X)
			.line_to_x(-STRAIGHT).arc(INNER, 180.0).line_to_x(YARD_ENTRY_X)
			.line_to_x(CROSSOVER_X + LINK_LENGTH).line_to_x(MERGE_X - LINK_LENGTH)
			.to(Vector2(MERGE_X, -OUTER), 0.0))
	# From the dead end beyond the hill, west to the apex and down the south leg.
	_add("HillLine", Track.new(Vector2(TAIL_END_X, 0.0), 180.0)
			.line_to_x(_apex.x).arc(WYE_RADIUS, -_wye_angle).arc(WYE_RADIUS, _wye_angle)
			.line(WYE_STRAIGHT))

	_add("CrossoverLink", Track.new(Vector2(CROSSOVER_X, -OUTER), 0.0)
			.to(Vector2(CROSSOVER_X + LINK_LENGTH, -INNER), 0.0))
	_add("ScissorsDown", Track.new(Vector2(SCISSORS_X, INNER), 0.0)
			.to(Vector2(SCISSORS_X + LINK_LENGTH, OUTER), 0.0))
	_add("ScissorsUp", Track.new(Vector2(SCISSORS_X, OUTER), 0.0)
			.to(Vector2(SCISSORS_X + LINK_LENGTH, INNER), 0.0))

	var freight := (Track.new(Vector2(DIAMOND_X, FREIGHT_START_Z), 270.0)
			.line_to_z(OUTER).line_to_z(INNER).line_to_z(FREIGHT_TURN_Z)
			.arc(FREIGHT_TURN_RADIUS, 90.0 - SLIP_HALF_ANGLE).line_to_x(SLIP_X))
	_slip = freight.position()
	_add("FreightLine", freight.line_to_x(GOODS_END_X))

	# The lead swings south off the inner track, runs straight, and swings back onto the
	# line through the slip's centre. The straight's length is whatever puts it there,
	# and since only the straight moves the end, the miss is linear in it.
	var short := _off_slip_line(_yard_lead(0.0).position())
	var long := _off_slip_line(_yard_lead(10.0).position())
	var straight := -short * 10.0 / (long - short)
	assert(straight > 0.0, "the yard lead cannot reach the slip")
	_add("YardLead", _yard_lead(straight).line_to_x(_slip.x).line_to_x(YARD_END_X))

	# Each slip road leaves one track before the diamond and joins the other after it.
	_add("SlipRoadNorth", Track.new(_on_lead(-SLIP_REACH), SLIP_HALF_ANGLE)
			.to(_on_freight(SLIP_REACH), -SLIP_HALF_ANGLE))
	_add("SlipRoadSouth", Track.new(_on_freight(-SLIP_REACH), -SLIP_HALF_ANGLE)
			.to(_on_lead(SLIP_REACH), SLIP_HALF_ANGLE))
	_add("YardLeft", Track.new(_on_lead(THREE_WAY_AT), SLIP_HALF_ANGLE)
			.arc(ROAD_RADIUS, -ROAD_SWING).arc(ROAD_RADIUS, ROAD_SWING).line_to_x(YARD_END_X))
	_add("YardRight", Track.new(_on_lead(THREE_WAY_AT + THREE_WAY_STAGGER), SLIP_HALF_ANGLE)
			.arc(ROAD_RADIUS, ROAD_SWING).arc(ROAD_RADIUS, -ROAD_SWING).line_to_x(YARD_END_X))


func _yard_lead(straight: float) -> Track:
	return (Track.new(Vector2(YARD_ENTRY_X, -INNER), 0.0).arc(LEAD_RADIUS, LEAD_SWING)
			.line(straight).arc(LEAD_RADIUS, -(LEAD_SWING - SLIP_HALF_ANGLE)))


## Signed distance of [param point] from the yard lead's line through the slip.
func _off_slip_line(point: Vector2) -> float:
	return (point - _slip).dot(Track.direction(SLIP_HALF_ANGLE + 90.0))


## [param along] metres from the slip's centre on the yard lead, east positive.
func _on_lead(along: float) -> Vector2:
	return _slip + Track.direction(SLIP_HALF_ANGLE) * along


## The same on the freight line.
func _on_freight(along: float) -> Vector2:
	return _slip + Track.direction(-SLIP_HALF_ANGLE) * along


func _add(rail: String, track: Track) -> void:
	_tracks[rail] = track
	_curves[rail] = _curve(track)
	_rail_order.append(rail)


## The track as a [Curve3D]: one point per pose, with handles along the headings. A
## segment between two poses on an arc gets the handles that make it follow the arc;
## a straight or an S-bend gets a third of its chord.
func _curve(track: Track) -> Curve3D:
	var curve := Curve3D.new()
	for point in track.points:
		curve.add_point(_world(point))
	for i in track.points.size() - 1:
		var chord := track.points[i].distance_to(track.points[i + 1])
		var turn := deg_to_rad(absf(wrapf(track.headings[i + 1] - track.headings[i],
				-180.0, 180.0)))
		var handle := chord / 3.0
		if turn > 1e-4:
			handle = chord * 2.0 / 3.0 * tan(turn / 4.0) / sin(turn / 2.0)
		var out := Track.direction(track.headings[i]) * handle
		var back := Track.direction(track.headings[i + 1]) * -handle
		curve.set_point_out(i, Vector3(out.x, 0.0, out.y))
		curve.set_point_in(i + 1, Vector3(back.x, 0.0, back.y))
	return curve


func _world(point: Vector2) -> Vector3:
	return Vector3(point.x + SHIFT.x, RAILHEAD, point.y + SHIFT.y)


## Metres along [param rail] to the point nearest [param point].
func _distance(rail: String, point: Vector2) -> float:
	return _curves[rail].get_closest_offset(_world(point))


func _length(rail: String) -> float:
	return _curves[rail].get_baked_length()
#endregion


#region Junctions
func _place_junctions() -> void:
	var start := Turnout.DivergeTowards.RAIL_START
	var end := Turnout.DivergeTowards.RAIL_END
	var first := Turnout.RailEnd.START
	var last := Turnout.RailEnd.END
	var balloon_west := Vector2(BALLOON_WEST_X, -OUTER)
	var balloon_east := Vector2(BALLOON_EAST_X, -OUTER)

	# The diverging route is not necessarily the one that looks like a branch: at the
	# balloon, the merges and the north wye leg the main rail runs on round whichever
	# way keeps every rail from being welded to itself.
	_turnouts.append(_turnout("BalloonWest", "Turnouts", "OuterLine", balloon_west, end,
			"NorthLine", last))
	_turnouts.append(_turnout("BalloonEast", "Turnouts", "NorthLine", balloon_east, end,
			"OuterLine", first))
	_turnouts.append(_turnout("NorthMerge", "Turnouts", "NorthLine", Vector2(MERGE_X, -OUTER),
			end, "InnerLine", last))
	_turnouts.append(_turnout("SouthMerge", "Turnouts", "OuterLine", Vector2(MERGE_X, OUTER),
			start, "InnerLine", first))
	_turnouts.append(_turnout("WyeNorth", "Turnouts", "NorthLine", Vector2(STRAIGHT, -OUTER),
			start, "OuterLine", last))
	_turnouts.append(_turnout("WyeSouth", "Turnouts", "OuterLine", Vector2(STRAIGHT, OUTER),
			end, "HillLine", last))
	_turnouts.append(_turnout("WyeEast", "Turnouts", "HillLine", _apex, end, "NorthLine", first))
	_turnouts.append(_turnout("YardEntry", "Turnouts", "InnerLine",
			Vector2(YARD_ENTRY_X, -INNER), end, "YardLead", first))

	var crossover := "Compounds/NorthCrossover"
	_compounds.append({"name": "NorthCrossover", "kind": CompoundTurnout.Kind.CROSSOVER,
			"members": [
				_turnout("OuterPoints", crossover, "NorthLine", Vector2(CROSSOVER_X, -OUTER),
						start, "CrossoverLink", first),
				_turnout("InnerPoints", crossover, "InnerLine",
						Vector2(CROSSOVER_X + LINK_LENGTH, -INNER), start, "CrossoverLink", last),
			]})
	var scissors := "Compounds/SouthScissors"
	_compounds.append({"name": "SouthScissors", "kind": CompoundTurnout.Kind.DOUBLE_CROSSOVER,
			"members": [
				_turnout("NorthWest", scissors, "InnerLine", Vector2(SCISSORS_X, INNER), start,
						"ScissorsDown", first),
				_turnout("SouthEast", scissors, "OuterLine",
						Vector2(SCISSORS_X + LINK_LENGTH, OUTER), start, "ScissorsDown", last),
				_turnout("SouthWest", scissors, "OuterLine", Vector2(SCISSORS_X, OUTER), end,
						"ScissorsUp", first),
				_turnout("NorthEast", scissors, "InnerLine",
						Vector2(SCISSORS_X + LINK_LENGTH, INNER), end, "ScissorsUp", last),
			]})
	var slip := "Compounds/YardSlip"
	_compounds.append({"name": "YardSlip", "kind": CompoundTurnout.Kind.DOUBLE_SLIP,
			"members": [
				_turnout("WestOne", slip, "YardLead", _on_lead(-SLIP_REACH), end,
						"SlipRoadNorth", first),
				_turnout("EastTwo", slip, "FreightLine", _on_freight(SLIP_REACH), start,
						"SlipRoadNorth", last),
				_turnout("WestTwo", slip, "FreightLine", _on_freight(-SLIP_REACH), end,
						"SlipRoadSouth", first),
				_turnout("EastOne", slip, "YardLead", _on_lead(SLIP_REACH), start,
						"SlipRoadSouth", last),
			]})
	var three_way := "Compounds/YardThreeWay"
	_compounds.append({"name": "YardThreeWay", "kind": CompoundTurnout.Kind.THREE_WAY,
			"members": [
				_turnout("LeftPoints", three_way, "YardLead", _on_lead(THREE_WAY_AT), end,
						"YardLeft", first),
				_turnout("RightPoints", three_way, "YardLead",
						_on_lead(THREE_WAY_AT + THREE_WAY_STAGGER), end, "YardRight", first),
			]})

	_crossings.append(_crossing("OuterDiamond", "OuterLine", "FreightLine",
			Vector2(DIAMOND_X, OUTER)))
	_crossings.append(_crossing("InnerDiamond", "InnerLine", "FreightLine",
			Vector2(DIAMOND_X, INNER)))
	_crossings.append(_crossing("SouthScissorsMiddle", "ScissorsDown", "ScissorsUp",
			Vector2(SCISSORS_X + LINK_LENGTH * 0.5, (OUTER + INNER) * 0.5)))
	_crossings.append(_crossing("YardSlipMiddle", "YardLead", "FreightLine", _slip))


func _turnout(name: String, parent: String, main: String, at: Vector2, diverge: int,
		branch: String, end: int) -> Dictionary:
	return {"name": name, "parent": parent, "main": main, "distance": _distance(main, at),
			"diverge": diverge, "branch": branch, "end": end, "at": at}


func _crossing(name: String, rail_a: String, rail_b: String, at: Vector2) -> Dictionary:
	return {"name": name, "a": rail_a, "distance_a": _distance(rail_a, at), "b": rail_b,
			"distance_b": _distance(rail_b, at), "at": at}


func _turnout_count() -> int:
	var count := _turnouts.size()
	for compound in _compounds:
		count += (compound["members"] as Array).size()
	return count
#endregion


#region Signals
## Every way into every junction, both ways along every track. Each signal is named for
## the junction it protects and the side a train comes at it from, stands
## [constant FACING_SIGNAL], [constant TRAILING_SIGNAL] or [constant CROSSING_SIGNAL]
## out from it, and governs the direction that train is travelling along the rail.
func _place_signals() -> void:
	var towards_end := RailSignal.Governs.TOWARDS_RAIL_END
	var towards_start := RailSignal.Governs.TOWARDS_RAIL_START
	var balloon_west := Vector2(BALLOON_WEST_X, -OUTER)
	var balloon_east := Vector2(BALLOON_EAST_X, -OUTER)
	var crossover_outer := Vector2(CROSSOVER_X, -OUTER)
	var crossover_inner := Vector2(CROSSOVER_X + LINK_LENGTH, -INNER)
	var north_merge := Vector2(MERGE_X, -OUTER)
	var south_merge := Vector2(MERGE_X, OUTER)
	var wye_north := Vector2(STRAIGHT, -OUTER)
	var wye_south := Vector2(STRAIGHT, OUTER)
	var yard_entry := Vector2(YARD_ENTRY_X, -INNER)

	# The balloon. OuterLine runs west past BalloonWest, NorthLine west past BalloonEast
	# and on round the loop, so it arrives back at BalloonWest heading east.
	_add_signal("BalloonWestFromEast", "OuterLine",
			_distance("OuterLine", balloon_west) - FACING_SIGNAL, towards_end)
	_add_signal("BalloonWestFromWest", "OuterLine",
			_distance("OuterLine", balloon_west) + TRAILING_SIGNAL, towards_start)
	_add_signal("BalloonWestFromLoop", "NorthLine",
			_length("NorthLine") - TRAILING_SIGNAL, towards_end)
	_add_signal("BalloonEastFromEast", "NorthLine",
			_distance("NorthLine", balloon_east) - FACING_SIGNAL, towards_end)
	_add_signal("BalloonEastFromLoop", "NorthLine",
			_distance("NorthLine", balloon_east) + TRAILING_SIGNAL, towards_start)
	_add_signal("BalloonEastFromWest", "OuterLine", TRAILING_SIGNAL, towards_start)

	# The north straight: NorthLine runs west along the outer track, InnerLine east along
	# the inner one.
	_add_signal("NorthCrossoverOuterFromEast", "NorthLine",
			_distance("NorthLine", crossover_outer) - TRAILING_SIGNAL, towards_end)
	_add_signal("NorthCrossoverOuterFromWest", "NorthLine",
			_distance("NorthLine", crossover_outer) + FACING_SIGNAL, towards_start)
	_add_signal("NorthCrossoverInnerFromWest", "InnerLine",
			_distance("InnerLine", crossover_inner) - TRAILING_SIGNAL, towards_end)
	_add_signal("NorthCrossoverInnerFromEast", "InnerLine",
			_distance("InnerLine", crossover_inner) + FACING_SIGNAL, towards_start)
	_add_signal("NorthMergeFromEast", "NorthLine",
			_distance("NorthLine", north_merge) - FACING_SIGNAL, towards_end)
	_add_signal("NorthMergeFromWest", "NorthLine",
			_distance("NorthLine", north_merge) + TRAILING_SIGNAL, towards_start)
	_add_signal("NorthMergeFromInner", "InnerLine",
			_length("InnerLine") - TRAILING_SIGNAL, towards_end)
	_add_signal("YardEntryFromWest", "InnerLine",
			_distance("InnerLine", yard_entry) - FACING_SIGNAL, towards_end)
	_add_signal("YardEntryFromEast", "InnerLine",
			_distance("InnerLine", yard_entry) + TRAILING_SIGNAL, towards_start)
	_add_signal("YardEntryFromYard", "YardLead", TRAILING_SIGNAL, towards_start)

	# The wye. NorthLine starts at the apex, HillLine runs from the tail through the apex
	# and down the south leg, and OuterLine ends coming round the east curve.
	_add_signal("WyeNorthFromWest", "NorthLine",
			_distance("NorthLine", wye_north) + FACING_SIGNAL, towards_start)
	_add_signal("WyeNorthFromWye", "NorthLine",
			_distance("NorthLine", wye_north) - TRAILING_SIGNAL, towards_end)
	_add_signal("WyeNorthFromCurve", "OuterLine",
			_length("OuterLine") - TRAILING_SIGNAL, towards_end)
	_add_signal("WyeSouthFromWest", "OuterLine",
			_distance("OuterLine", wye_south) - FACING_SIGNAL, towards_end)
	_add_signal("WyeSouthFromCurve", "OuterLine",
			_distance("OuterLine", wye_south) + TRAILING_SIGNAL, towards_start)
	_add_signal("WyeSouthFromWye", "HillLine",
			_length("HillLine") - TRAILING_SIGNAL, towards_end)
	_add_signal("WyeEastFromTail", "HillLine",
			_distance("HillLine", _apex) - FACING_SIGNAL, towards_end)
	_add_signal("WyeEastFromSouth", "HillLine",
			_distance("HillLine", _apex) + TRAILING_SIGNAL, towards_start)
	_add_signal("WyeEastFromNorth", "NorthLine", TRAILING_SIGNAL, towards_start)

	# The south straight: OuterLine runs east, InnerLine west.
	_add_signal("SouthMergeFromEast", "OuterLine",
			_distance("OuterLine", south_merge) + FACING_SIGNAL, towards_start)
	_add_signal("SouthMergeFromWest", "OuterLine",
			_distance("OuterLine", south_merge) - TRAILING_SIGNAL, towards_end)
	_add_signal("SouthMergeFromInner", "InnerLine", TRAILING_SIGNAL, towards_start)
	_add_signal("SouthScissorsOuterFromWest", "OuterLine",
			_distance("OuterLine", Vector2(SCISSORS_X, OUTER)) - FACING_SIGNAL, towards_end)
	_add_signal("SouthScissorsOuterFromEast", "OuterLine",
			_distance("OuterLine", Vector2(SCISSORS_X + LINK_LENGTH, OUTER)) + FACING_SIGNAL,
			towards_start)
	_add_signal("SouthScissorsInnerFromWest", "InnerLine",
			_distance("InnerLine", Vector2(SCISSORS_X, INNER)) + FACING_SIGNAL, towards_start)
	_add_signal("SouthScissorsInnerFromEast", "InnerLine",
			_distance("InnerLine", Vector2(SCISSORS_X + LINK_LENGTH, INNER)) - FACING_SIGNAL,
			towards_end)

	# The two diamonds are 5 m apart, so they are protected as one: from both ends of
	# both tracks and from both ends of the freight line, which runs north here.
	var outer_diamond := Vector2(DIAMOND_X, OUTER)
	var inner_diamond := Vector2(DIAMOND_X, INNER)
	_add_signal("DiamondOuterFromWest", "OuterLine",
			_distance("OuterLine", outer_diamond) - CROSSING_SIGNAL, towards_end)
	_add_signal("DiamondOuterFromEast", "OuterLine",
			_distance("OuterLine", outer_diamond) + CROSSING_SIGNAL, towards_start)
	_add_signal("DiamondInnerFromWest", "InnerLine",
			_distance("InnerLine", inner_diamond) + CROSSING_SIGNAL, towards_start)
	_add_signal("DiamondInnerFromEast", "InnerLine",
			_distance("InnerLine", inner_diamond) - CROSSING_SIGNAL, towards_end)
	_add_signal("DiamondFromSouth", "FreightLine",
			_distance("FreightLine", outer_diamond) - CROSSING_SIGNAL, towards_end)
	_add_signal("DiamondFromNorth", "FreightLine",
			_distance("FreightLine", inner_diamond) + CROSSING_SIGNAL, towards_start)

	# The yard. Both the lead and the freight line run east through the slip.
	_add_signal("YardSlipLeadFromWest", "YardLead",
			_distance("YardLead", _on_lead(-SLIP_REACH)) - FACING_SIGNAL, towards_end)
	_add_signal("YardSlipFreightFromWest", "FreightLine",
			_distance("FreightLine", _on_freight(-SLIP_REACH)) - FACING_SIGNAL, towards_end)
	_add_signal("YardSlipLeadFromEast", "YardLead",
			_distance("YardLead", _on_lead(SLIP_REACH)) + FACING_SIGNAL, towards_start)
	_add_signal("YardSlipFreightFromEast", "FreightLine",
			_distance("FreightLine", _on_freight(SLIP_REACH)) + FACING_SIGNAL, towards_start)
	_add_signal("YardThreeWayFromWest", "YardLead",
			_distance("YardLead", _on_lead(THREE_WAY_AT)) - FACING_SIGNAL, towards_end)
	_add_signal("YardThreeWayFromLeft", "YardLeft", TRAILING_SIGNAL, towards_start)
	_add_signal("YardThreeWayFromMiddle", "YardLead",
			_distance("YardLead", _on_lead(THREE_WAY_AT + THREE_WAY_STAGGER)) + TRAILING_SIGNAL,
			towards_start)
	_add_signal("YardThreeWayFromRight", "YardRight", TRAILING_SIGNAL, towards_start)


func _add_signal(name: String, rail: String, distance: float, governs: int) -> void:
	assert(distance > 0.0 and distance < _length(rail), "%s is off %s" % [name, rail])
	_signals.append({"name": name, "rail": rail, "distance": distance, "governs": governs})
#endregion


#region Trains
## Four trains, each a few seconds short of a signal at danger, so the level opens with
## every one of them waiting for the dispatcher.
func _place_trains() -> void:
	_trains.append({"name": "Express", "rail": "NorthLine",
			"distance": _distance("NorthLine", Vector2(75.0, -OUTER)), "facing": 1,
			"speed": 18.0, "end": Train.EndBehavior.TURN_AROUND, "length": 14.0,
			"width": 2.9, "height": 3.4})
	_trains.append({"name": "Freight", "rail": "HillLine", "distance": 20.0, "facing": 1,
			"speed": 9.0, "end": Train.EndBehavior.TURN_AROUND, "length": 22.0,
			"width": 3.1, "height": 3.9})
	_trains.append({"name": "Regional", "rail": "FreightLine", "distance": 30.0, "facing": 1,
			"speed": 12.0, "end": Train.EndBehavior.TURN_AROUND, "length": 16.0,
			"width": 2.9, "height": 3.4})
	_trains.append({"name": "Shunter", "rail": "YardRight", "distance": 50.0, "facing": -1,
			"speed": 6.0, "end": Train.EndBehavior.REVERSE, "length": 8.0,
			"width": 2.8, "height": 3.2})
#endregion


#region Checks
## Reports any two stretches of track closer than [constant _CLEARANCE] in plan away
## from a junction, where they are meant to meet. Only a report: the layout constants
## are what to change.
func _check_clearances() -> void:
	var meeting: Array[Vector2] = []
	for turnout in _turnouts:
		meeting.append(turnout["at"] as Vector2)
	for compound in _compounds:
		for member: Dictionary in compound["members"]:
			meeting.append(member["at"] as Vector2)
	for crossing in _crossings:
		meeting.append(crossing["at"] as Vector2)

	var samples: Array[Dictionary] = []
	var cells: Dictionary[Vector2i, Array] = {}
	for rail in _rail_order:
		var curve := _curves[rail]
		var along := 0.0
		while along <= curve.get_baked_length():
			var at := curve.sample_baked(along, true)
			var plan := Vector2(at.x, at.z) - SHIFT
			var near := false
			for point in meeting:
				if plan.distance_to(point) < 40.0:
					near = true
					break
			if not near:
				var cell := Vector2i(floori(plan.x / 6.0), floori(plan.y / 6.0))
				if not cells.has(cell):
					cells[cell] = []
				cells[cell].append(samples.size())
				samples.append({"rail": rail, "along": along, "plan": plan})
			along += 1.0

	var worst: Dictionary[String, float] = {}
	for i in samples.size():
		var sample := samples[i]
		var plan: Vector2 = sample["plan"]
		var cell := Vector2i(floori(plan.x / 6.0), floori(plan.y / 6.0))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for j: int in cells.get(cell + Vector2i(dx, dz), []):
					if j <= i:
						continue
					var other := samples[j]
					if sample["rail"] == other["rail"] and absf(
							float(sample["along"]) - float(other["along"])) < 60.0:
						continue
					var gap := plan.distance_to(other["plan"] as Vector2)
					if gap >= _CLEARANCE:
						continue
					var key := "%s / %s" % [sample["rail"], other["rail"]]
					worst[key] = minf(worst.get(key, INF), gap)
	for key in worst:
		print("  clearance: %s come within %.2f m of each other" % [key, worst[key]])
	if worst.is_empty():
		print("  clearance: every stretch of track is at least %.1f m from every other"
				% _CLEARANCE)
#endregion


#region Terrain
## The ground before any track: flat, but for the hill, the gully and the pond.
func _natural(point: Vector2) -> float:
	var height := 0.0
	var across := (point.x - HILL_X) / HILL_HALF_WIDTH
	if absf(across) < 1.0:
		var ridge := 1.0 - smoothstep(HILL_FULL_Z, HILL_END_Z, absf(point.y))
		height += HILL_HEIGHT * pow(cos(across * PI * 0.5), 2.0) * ridge
	var gully := (point.x - GULLY_X) / GULLY_HALF_WIDTH
	if absf(gully) < 1.0:
		height -= GULLY_DEPTH * pow(cos(gully * PI * 0.5), 2.0)
	var pond := point.distance_to(_pond_centre()) / POND_RADIUS
	if pond < 1.0:
		height -= POND_DEPTH * pow(cos(pond * PI * 0.5), 2.0)
	return height


func _pond_centre() -> Vector2:
	return Vector2(BALLOON_WEST_X, -OUTER - LOOP_RADIUS)


## What the track needs of the ground where it stands on [param natural] ground.
func _kind(natural: float) -> Kind:
	if natural > RAILHEAD + TUNNEL_COVER:
		return Kind.TUNNEL
	if natural < RAILHEAD - BED_DEPTH - BRIDGE_DROP:
		return Kind.BRIDGE
	return Kind.TRACK


## The natural ground, carved to the track and baked into the heightmap
## [member Ground.heightmap] reads: [constant Image.FORMAT_RF], first row at -Z.
##
## Each grid vertex takes its orders from the nearest point of each rail. On ordinary
## track that is a bed and slopes away from it; in a tunnel, a roof over it; on a
## bridge, nothing - the gully is left where it is. Nearest point, not every point in
## reach, so that the cutting up to a tunnel mouth stops at the mouth instead of
## eating its slopes some way into the hill.
func _bake_terrain() -> Image:
	var columns := roundi(GROUND_SIZE.x / GRID) + 1
	var rows := roundi(GROUND_SIZE.y / GRID) + 1
	var half := GROUND_SIZE * 0.5
	var natural := PackedFloat32Array()
	var ceiling := PackedFloat32Array()
	var floor_height := PackedFloat32Array()
	natural.resize(columns * rows)
	ceiling.resize(columns * rows)
	floor_height.resize(columns * rows)
	for row in rows:
		for column in columns:
			var index := row * columns + column
			var world := Vector2(-half.x + float(column) * GRID, -half.y + float(row) * GRID)
			natural[index] = _natural(world - SHIFT)
			ceiling[index] = INF
			floor_height[index] = -INF

	var reach := ceili(CARVE_REACH / GRID)
	var tunnels := 0.0
	var bridges := 0.0
	for rail in _rail_order:
		var curve := _curves[rail]
		var nearest := PackedFloat32Array()
		var kinds := PackedByteArray()
		var railheads := PackedFloat32Array()
		nearest.resize(columns * rows)
		nearest.fill(INF)
		kinds.resize(columns * rows)
		railheads.resize(columns * rows)
		var along := 0.0
		while along <= curve.get_baked_length():
			var at := curve.sample_baked(along, true)
			var plan := Vector2(at.x, at.z)
			along += 0.5
			if _is_flat_around(plan - SHIFT):
				continue
			var kind := _kind(_natural(plan - SHIFT))
			if kind == Kind.TUNNEL:
				tunnels += 0.5
			elif kind == Kind.BRIDGE:
				bridges += 0.5
			var centre_column := roundi((plan.x + half.x) / GRID)
			var centre_row := roundi((plan.y + half.y) / GRID)
			for row in range(maxi(centre_row - reach, 0), mini(centre_row + reach + 1, rows)):
				for column in range(maxi(centre_column - reach, 0),
						mini(centre_column + reach + 1, columns)):
					var vertex := Vector2(-half.x + float(column) * GRID,
							-half.y + float(row) * GRID)
					var gap := vertex.distance_to(plan)
					var index := row * columns + column
					if gap < nearest[index]:
						nearest[index] = gap
						kinds[index] = kind
						railheads[index] = at.y
		for index in columns * rows:
			var gap := nearest[index]
			if gap > CARVE_REACH:
				continue
			var bed := railheads[index] - BED_DEPTH
			var beyond := maxf(gap - BED_HALF_WIDTH, 0.0)
			match kinds[index]:
				Kind.TRACK:
					ceiling[index] = minf(ceiling[index], bed + beyond * CUT_SLOPE)
					floor_height[index] = maxf(floor_height[index], bed - beyond / BANK_SLOPE)
				Kind.BRIDGE:
					ceiling[index] = minf(ceiling[index], bed + beyond * CUT_SLOPE)
				Kind.TUNNEL:
					if gap < BED_HALF_WIDTH + 1.0:
						floor_height[index] = maxf(floor_height[index],
								railheads[index] + TUNNEL_ROOF)
	print("  terrain: %d x %d vertices, %.0f m of track in tunnels, %.0f m on bridges"
			% [columns, rows, tunnels, bridges])

	var image := Image.create_empty(columns, rows, false, Image.FORMAT_RF)
	for row in rows:
		for column in columns:
			var index := row * columns + column
			var height := maxf(minf(natural[index], ceiling[index]), floor_height[index])
			image.set_pixel(column, row, Color(height, 0.0, 0.0))
	return image


## Whether the natural ground is level at [param point] and all round it as far as
## carving reaches - where track on its bed changes nothing, and the sample can be
## skipped. The hill, the gully and the pond are all far wider than the spacing here.
func _is_flat_around(point: Vector2) -> bool:
	for offset: Vector2 in [Vector2.ZERO, Vector2(CARVE_REACH, 0.0), Vector2(-CARVE_REACH, 0.0),
			Vector2(0.0, CARVE_REACH), Vector2(0.0, -CARVE_REACH),
			Vector2(CARVE_REACH, CARVE_REACH) * 0.7, Vector2(-CARVE_REACH, CARVE_REACH) * 0.7,
			Vector2(CARVE_REACH, -CARVE_REACH) * 0.7, Vector2(-CARVE_REACH, -CARVE_REACH) * 0.7]:
		if absf(_natural(point + offset)) > 1e-3:
			return false
	return true
#endregion


#region Scene text
func _scene_text() -> String:
	var lines := PackedStringArray()
	var resources := 13 + 6 + _rail_order.size()
	lines.append("[gd_scene load_steps=%d format=3]" % (resources + 1))
	lines.append("")
	for entry: Array in [
		["Script", "res://scripts/world/ground.gd", "1_ground"],
		["Script", "res://scripts/rails/rail.gd", "2_rail"],
		["Script", "res://scripts/trains/train.gd", "3_train"],
		["Script", "res://scripts/debug/camera_rig.gd", "4_camera"],
		["Script", "res://scripts/debug/train_debug_panel.gd", "5_panel"],
		["Script", "res://scripts/rails/turnout.gd", "6_turnout"],
		["Script", "res://scripts/debug/turnout_debug_panel.gd", "7_tpanel"],
		["Script", "res://scripts/ui/marker_overlay.gd", "8_overlay"],
		["Script", "res://scripts/rails/rail_signal.gd", "9_signal"],
		["Script", "res://scripts/debug/signal_debug_panel.gd", "10_spanel"],
		["Script", "res://scripts/rails/compound_turnout.gd", "11_compound"],
		["Script", "res://scripts/rails/crossing.gd", "12_crossing"],
		["Image", HEIGHTS_PATH, "13_heights"],
	]:
		lines.append('[ext_resource type="%s" path="%s" id="%s"]' % entry)
	lines.append("")
	lines.append_array(_environment_text())
	for rail in _rail_order:
		lines.append_array(_curve_text(rail))

	lines.append('[node name="Main" type="Node3D"]')
	lines.append("")
	lines.append('[node name="WorldEnvironment" type="WorldEnvironment" parent="."]')
	lines.append('environment = SubResource("Environment_1")')
	lines.append("")
	lines.append('[node name="Sun" type="DirectionalLight3D" parent="."]')
	lines.append("transform = Transform3D(0.6452, -0.628, 0.4352, 0, 0.5696, 0.822, -0.764, "
			+ "-0.5303, 0.3675, 0, 60, 0)")
	lines.append("light_energy = 1.3")
	lines.append("shadow_enabled = true")
	lines.append("directional_shadow_max_distance = 500.0")
	lines.append("")
	lines.append('[node name="Ground" type="MeshInstance3D" parent="." groups=["snap_surface"]]')
	lines.append('script = ExtResource("1_ground")')
	lines.append("size = Vector2(%s, %s)" % [_num(GROUND_SIZE.x), _num(GROUND_SIZE.y)])
	lines.append('heightmap = ExtResource("13_heights")')
	lines.append("low_color = Color(0.27, 0.4, 0.21, 1)")
	lines.append("high_color = Color(0.4, 0.52, 0.28, 1)")
	lines.append("steep_color = Color(0.46, 0.4, 0.3, 1)")
	lines.append("steep_amount = 0.8")
	lines.append("")
	var pond := _pond_centre() + SHIFT
	lines.append('[node name="Pond" type="MeshInstance3D" parent="."]')
	lines.append("transform = Transform3D(16, 0, 0, 0, 1, 0, 0, 0, 16, %s, %s, %s)"
			% [_num(pond.x), _num(POND_LEVEL), _num(pond.y)])
	lines.append('mesh = SubResource("CylinderMesh_pond")')
	lines.append('material_override = SubResource("StandardMaterial3D_water")')
	lines.append("")
	lines.append('[node name="Stream" type="MeshInstance3D" parent="."]')
	lines.append("transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, %s, 0)"
			% [_num(GULLY_X + SHIFT.x), _num(STREAM_LEVEL)])
	lines.append('mesh = SubResource("BoxMesh_stream")')
	lines.append('material_override = SubResource("StandardMaterial3D_water")')
	lines.append("")

	lines.append('[node name="Rails" type="Node3D" parent="."]')
	lines.append("")
	for rail in _rail_order:
		lines.append('[node name="%s" type="Path3D" parent="Rails" '
				% rail + 'node_paths=PackedStringArray("surface_root")]')
		lines.append('curve = SubResource("Curve3D_%s")' % rail)
		lines.append('script = ExtResource("2_rail")')
		lines.append('surface_root = NodePath("../../Ground")')
		lines.append("surface_offset = %s" % _num(BED_DEPTH))
		lines.append("snap_on_ready = false")
		lines.append("")

	lines.append('[node name="Turnouts" type="Node3D" parent="."]')
	lines.append("")
	for turnout in _turnouts:
		lines.append_array(_turnout_text(turnout))

	lines.append('[node name="Compounds" type="Node3D" parent="."]')
	lines.append("")
	for compound in _compounds:
		var paths := PackedStringArray()
		for member: Dictionary in compound["members"]:
			paths.append('NodePath("%s")' % member["name"])
		lines.append('[node name="%s" type="Node3D" parent="Compounds" ' % compound["name"]
				+ 'groups=["compound_turnouts"] node_paths=PackedStringArray("members")]')
		lines.append('script = ExtResource("11_compound")')
		lines.append("kind = %d" % compound["kind"])
		lines.append("members = [%s]" % ", ".join(paths))
		lines.append("")
		for member: Dictionary in compound["members"]:
			lines.append_array(_turnout_text(member))

	lines.append('[node name="Crossings" type="Node3D" parent="."]')
	lines.append("")
	for crossing in _crossings:
		lines.append('[node name="%s" type="Node3D" parent="Crossings" groups=["crossings"] '
				% crossing["name"] + 'node_paths=PackedStringArray("rail_a", "rail_b")]')
		lines.append('script = ExtResource("12_crossing")')
		lines.append('rail_a = NodePath("../../Rails/%s")' % crossing["a"])
		lines.append("distance_a = %s" % _num(crossing["distance_a"]))
		lines.append('rail_b = NodePath("../../Rails/%s")' % crossing["b"])
		lines.append("distance_b = %s" % _num(crossing["distance_b"]))
		lines.append("")

	lines.append('[node name="Signals" type="Node3D" parent="."]')
	lines.append("")
	for rail_signal in _signals:
		lines.append('[node name="%s" type="Node3D" parent="Signals" groups=["signals"] '
				% rail_signal["name"] + 'node_paths=PackedStringArray("rail")]')
		lines.append('script = ExtResource("9_signal")')
		lines.append('rail = NodePath("../../Rails/%s")' % rail_signal["rail"])
		lines.append("distance = %s" % _num(rail_signal["distance"]))
		lines.append("governs = %d" % rail_signal["governs"])
		lines.append("")

	lines.append('[node name="Trains" type="Node3D" parent="."]')
	lines.append("")
	for train in _trains:
		lines.append('[node name="%s" type="Node3D" parent="Trains" groups=["trains"] '
				% train["name"] + 'node_paths=PackedStringArray("rail")]')
		lines.append('script = ExtResource("3_train")')
		lines.append('rail = NodePath("../../Rails/%s")' % train["rail"])
		lines.append("distance = %s" % _num(train["distance"]))
		lines.append("facing = %d" % train["facing"])
		lines.append("speed = %s" % _num(train["speed"]))
		lines.append("end_behavior = %d" % train["end"])
		lines.append("body_length = %s" % _num(train["length"]))
		lines.append("body_width = %s" % _num(train["width"]))
		lines.append("body_height = %s" % _num(train["height"]))
		lines.append("")

	lines.append_array(_camera_and_ui_text())
	return "\n".join(lines)


func _environment_text() -> PackedStringArray:
	return PackedStringArray([
		'[sub_resource type="ProceduralSkyMaterial" id="ProceduralSkyMaterial_1"]',
		"sky_horizon_color = Color(0.66, 0.7, 0.74, 1)",
		"ground_bottom_color = Color(0.22, 0.24, 0.24, 1)",
		"ground_horizon_color = Color(0.66, 0.7, 0.74, 1)",
		"",
		'[sub_resource type="Sky" id="Sky_1"]',
		'sky_material = SubResource("ProceduralSkyMaterial_1")',
		"",
		'[sub_resource type="Environment" id="Environment_1"]',
		"background_mode = 2",
		'sky = SubResource("Sky_1")',
		"tonemap_mode = 2",
		"ssao_enabled = true",
		"",
		'[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_water"]',
		"albedo_color = Color(0.22, 0.42, 0.5, 1)",
		"metallic = 0.2",
		"roughness = 0.08",
		"",
		'[sub_resource type="CylinderMesh" id="CylinderMesh_pond"]',
		"top_radius = 1.0",
		"bottom_radius = 1.0",
		"height = 0.02",
		"radial_segments = 64",
		"rings = 1",
		"",
		'[sub_resource type="BoxMesh" id="BoxMesh_stream"]',
		"size = Vector3(7, 0.02, %s)" % _num(GROUND_SIZE.y),
		"",
	])


## [code]in[/code], [code]out[/code], [code]position[/code] per point, handles relative
## to their point - see CLAUDE.md.
func _curve_text(rail: String) -> PackedStringArray:
	var curve := _curves[rail]
	var numbers := PackedStringArray()
	var tilts := PackedStringArray()
	for i in curve.point_count:
		for v: Vector3 in [curve.get_point_in(i), curve.get_point_out(i),
				curve.get_point_position(i)]:
			numbers.append_array([_num(v.x), _num(v.y), _num(v.z)])
		tilts.append("0")
	return PackedStringArray([
		'[sub_resource type="Curve3D" id="Curve3D_%s"]' % rail,
		"_data = {",
		'"points": PackedVector3Array(%s),' % ", ".join(numbers),
		'"tilts": PackedFloat32Array(%s)' % ", ".join(tilts),
		"}",
		"point_count = %d" % curve.point_count,
		"",
	])


func _turnout_text(turnout: Dictionary) -> PackedStringArray:
	var parent: String = turnout["parent"]
	var up := "../".repeat(parent.count("/") + 2)
	return PackedStringArray([
		'[node name="%s" type="Node3D" parent="%s" groups=["turnouts"] ' % [turnout["name"],
				parent] + 'node_paths=PackedStringArray("main_rail", "branch_rail")]',
		'script = ExtResource("6_turnout")',
		'main_rail = NodePath("%sRails/%s")' % [up, turnout["main"]],
		"main_distance = %s" % _num(turnout["distance"]),
		"diverge_towards = %d" % turnout["diverge"],
		'branch_rail = NodePath("%sRails/%s")' % [up, turnout["branch"]],
		"branch_end = %d" % turnout["end"],
		"",
	])


func _camera_and_ui_text() -> PackedStringArray:
	return PackedStringArray([
		'[node name="CameraRig" type="Node3D" parent="." node_paths=PackedStringArray("camera")]',
		"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -40, 2, 0)",
		'script = ExtResource("4_camera")',
		'camera = NodePath("Camera3D")',
		"yaw_degrees = -15.0",
		"pitch_degrees = -55.0",
		"zoom = 360.0",
		"max_zoom = 700.0",
		"",
		'[node name="Camera3D" type="Camera3D" parent="CameraRig"]',
		"far = 3000.0",
		"",
		'[node name="DebugUi" type="CanvasLayer" parent="."]',
		"",
		'[node name="Panels" type="VBoxContainer" parent="DebugUi"]',
		"offset_left = 12.0",
		"offset_top = 12.0",
		"mouse_filter = 2",
		"theme_override_constants/separation = 8",
		"",
		'[node name="TrainDebugPanel" type="PanelContainer" parent="DebugUi/Panels"]',
		"layout_mode = 2",
		"size_flags_horizontal = 0",
		"mouse_filter = 2",
		'script = ExtResource("5_panel")',
		"",
		'[node name="TurnoutDebugPanel" type="PanelContainer" parent="DebugUi/Panels" '
				+ 'node_paths=PackedStringArray("overlay")]',
		"layout_mode = 2",
		"size_flags_horizontal = 0",
		"mouse_filter = 2",
		'script = ExtResource("7_tpanel")',
		'overlay = NodePath("../../MarkerOverlay")',
		"",
		'[node name="SignalDebugPanel" type="PanelContainer" parent="DebugUi/Panels" '
				+ 'node_paths=PackedStringArray("overlay")]',
		"layout_mode = 2",
		"size_flags_horizontal = 0",
		"mouse_filter = 2",
		'script = ExtResource("10_spanel")',
		'overlay = NodePath("../../MarkerOverlay")',
		"",
		'[node name="MarkerOverlay" type="Control" parent="DebugUi" '
				+ 'node_paths=PackedStringArray("camera")]',
		"anchor_right = 1.0",
		"anchor_bottom = 1.0",
		"mouse_filter = 2",
		'script = ExtResource("8_overlay")',
		'camera = NodePath("../../CameraRig/Camera3D")',
		"",
	])


## Four decimals, no trailing zeros, and no negative zero.
func _num(value: float) -> String:
	if absf(value) < 5e-5:
		return "0"
	return String.num(value, 4)
#endregion
