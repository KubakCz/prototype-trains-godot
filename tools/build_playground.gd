extends SceneTree
## Builds the playground, [code]scenes/main.tscn[/code], and bakes the terrain under it.
##
## [codeblock]
## godot --headless --path . --script res://tools/build_playground.gd
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

const Kit := preload("res://tools/scene_kit.gd")
const Track := Kit.Track

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
## How far either side of the track carving reaches; the rest of the rules are
## [code]Kit[/code]'s.
const CARVE_REACH := 24.0
#endregion

const _CLEARANCE := 4.6

var _curves: Dictionary[String, Curve3D] = {}
var _rail_order: Array[String] = []
var _turnouts: Array[Dictionary] = []
var _compounds: Array[Dictionary] = []
var _crossings: Array[Dictionary] = []
var _signals: Array[Dictionary] = []
var _trains: Array[Dictionary] = []
## Every stretch of track carving found in a tunnel or on a bridge, as a
## [Tunnel] or [Bridge] to put in the scene: kind, rail, from, to.
var _structures: Array[Dictionary] = []
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
	if not Kit.save_heights(_bake_terrain(), HEIGHTS_PATH) \
			or not Kit.write_scene(SCENE_PATH, _scene_text()):
		quit(1)
		return
	print("Wrote %s: %d rails, %d turnouts, %d assemblies, %d crossings, %d signals, %d trains"
			% [SCENE_PATH, _rail_order.size(), Kit.all_turnouts(_turnouts, _compounds).size(),
			_compounds.size(), _crossings.size(), _signals.size(), _trains.size()])
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
	_curves[rail] = Kit.curve(track, RAILHEAD, SHIFT)
	_rail_order.append(rail)


func _world(point: Vector2) -> Vector3:
	return Kit.world(point, RAILHEAD, SHIFT)


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

#endregion


#region Signals
## Every way into every junction, both ways along every track. Each signal is named for
## the junction it protects and the side a train comes at it from, stands
## [constant FACING_SIGNAL], [constant TRAILING_SIGNAL] or [constant CROSSING_SIGNAL]
## out from it, and governs the direction that train is travelling along the rail.
##
## A row is name, rail, where on it the junction is - a point in plan, or the rail's
## "start" or "end" for a junction its end is welded into - and how far from there the
## signal stands. Short of the junction along the rail is towards its end, so a
## negative offset governs [constant RailSignal.Governs.TOWARDS_RAIL_END] and a positive
## one [constant RailSignal.Governs.TOWARDS_RAIL_START].
func _place_signals() -> void:
	var balloon_west := Vector2(BALLOON_WEST_X, -OUTER)
	var balloon_east := Vector2(BALLOON_EAST_X, -OUTER)
	var crossover_outer := Vector2(CROSSOVER_X, -OUTER)
	var crossover_inner := Vector2(CROSSOVER_X + LINK_LENGTH, -INNER)
	var north_merge := Vector2(MERGE_X, -OUTER)
	var south_merge := Vector2(MERGE_X, OUTER)
	var wye_north := Vector2(STRAIGHT, -OUTER)
	var wye_south := Vector2(STRAIGHT, OUTER)
	var yard_entry := Vector2(YARD_ENTRY_X, -INNER)
	# The two diamonds are 5 m apart, so they are protected as one: from both ends of
	# both tracks and from both ends of the freight line, which runs north here.
	var outer_diamond := Vector2(DIAMOND_X, OUTER)
	var inner_diamond := Vector2(DIAMOND_X, INNER)

	for row: Array in [
		# The balloon. OuterLine runs west past BalloonWest, NorthLine west past
		# BalloonEast and on round the loop, so it arrives back at BalloonWest heading east.
		["BalloonWestFromEast", "OuterLine", balloon_west, -FACING_SIGNAL],
		["BalloonWestFromWest", "OuterLine", balloon_west, TRAILING_SIGNAL],
		["BalloonWestFromLoop", "NorthLine", "end", -TRAILING_SIGNAL],
		["BalloonEastFromEast", "NorthLine", balloon_east, -FACING_SIGNAL],
		["BalloonEastFromLoop", "NorthLine", balloon_east, TRAILING_SIGNAL],
		["BalloonEastFromWest", "OuterLine", "start", TRAILING_SIGNAL],

		# The north straight: NorthLine runs west along the outer track, InnerLine east
		# along the inner one.
		["NorthCrossoverOuterFromEast", "NorthLine", crossover_outer, -TRAILING_SIGNAL],
		["NorthCrossoverOuterFromWest", "NorthLine", crossover_outer, FACING_SIGNAL],
		["NorthCrossoverInnerFromWest", "InnerLine", crossover_inner, -TRAILING_SIGNAL],
		["NorthCrossoverInnerFromEast", "InnerLine", crossover_inner, FACING_SIGNAL],
		["NorthMergeFromEast", "NorthLine", north_merge, -FACING_SIGNAL],
		["NorthMergeFromWest", "NorthLine", north_merge, TRAILING_SIGNAL],
		["NorthMergeFromInner", "InnerLine", "end", -TRAILING_SIGNAL],
		["YardEntryFromWest", "InnerLine", yard_entry, -FACING_SIGNAL],
		["YardEntryFromEast", "InnerLine", yard_entry, TRAILING_SIGNAL],
		["YardEntryFromYard", "YardLead", "start", TRAILING_SIGNAL],

		# The wye. NorthLine starts at the apex, HillLine runs from the tail through the
		# apex and down the south leg, and OuterLine ends coming round the east curve.
		["WyeNorthFromWest", "NorthLine", wye_north, FACING_SIGNAL],
		["WyeNorthFromWye", "NorthLine", wye_north, -TRAILING_SIGNAL],
		["WyeNorthFromCurve", "OuterLine", "end", -TRAILING_SIGNAL],
		["WyeSouthFromWest", "OuterLine", wye_south, -FACING_SIGNAL],
		["WyeSouthFromCurve", "OuterLine", wye_south, TRAILING_SIGNAL],
		["WyeSouthFromWye", "HillLine", "end", -TRAILING_SIGNAL],
		["WyeEastFromTail", "HillLine", _apex, -FACING_SIGNAL],
		["WyeEastFromSouth", "HillLine", _apex, TRAILING_SIGNAL],
		["WyeEastFromNorth", "NorthLine", "start", TRAILING_SIGNAL],

		# The south straight: OuterLine runs east, InnerLine west.
		["SouthMergeFromEast", "OuterLine", south_merge, FACING_SIGNAL],
		["SouthMergeFromWest", "OuterLine", south_merge, -TRAILING_SIGNAL],
		["SouthMergeFromInner", "InnerLine", "start", TRAILING_SIGNAL],
		["SouthScissorsOuterFromWest", "OuterLine", Vector2(SCISSORS_X, OUTER),
				-FACING_SIGNAL],
		["SouthScissorsOuterFromEast", "OuterLine", Vector2(SCISSORS_X + LINK_LENGTH, OUTER),
				FACING_SIGNAL],
		["SouthScissorsInnerFromWest", "InnerLine", Vector2(SCISSORS_X, INNER),
				FACING_SIGNAL],
		["SouthScissorsInnerFromEast", "InnerLine", Vector2(SCISSORS_X + LINK_LENGTH, INNER),
				-FACING_SIGNAL],

		["DiamondOuterFromWest", "OuterLine", outer_diamond, -CROSSING_SIGNAL],
		["DiamondOuterFromEast", "OuterLine", outer_diamond, CROSSING_SIGNAL],
		["DiamondInnerFromWest", "InnerLine", inner_diamond, CROSSING_SIGNAL],
		["DiamondInnerFromEast", "InnerLine", inner_diamond, -CROSSING_SIGNAL],
		["DiamondFromSouth", "FreightLine", outer_diamond, -CROSSING_SIGNAL],
		["DiamondFromNorth", "FreightLine", inner_diamond, CROSSING_SIGNAL],

		# The yard. Both the lead and the freight line run east through the slip.
		["YardSlipLeadFromWest", "YardLead", _on_lead(-SLIP_REACH), -FACING_SIGNAL],
		["YardSlipFreightFromWest", "FreightLine", _on_freight(-SLIP_REACH), -FACING_SIGNAL],
		["YardSlipLeadFromEast", "YardLead", _on_lead(SLIP_REACH), FACING_SIGNAL],
		["YardSlipFreightFromEast", "FreightLine", _on_freight(SLIP_REACH), FACING_SIGNAL],
		["YardThreeWayFromWest", "YardLead", _on_lead(THREE_WAY_AT), -FACING_SIGNAL],
		["YardThreeWayFromLeft", "YardLeft", "start", TRAILING_SIGNAL],
		["YardThreeWayFromMiddle", "YardLead", _on_lead(THREE_WAY_AT + THREE_WAY_STAGGER),
				TRAILING_SIGNAL],
		["YardThreeWayFromRight", "YardRight", "start", TRAILING_SIGNAL],
	]:
		var rail: String = row[1]
		var from := 0.0
		if row[2] is Vector2:
			from = _distance(rail, row[2] as Vector2)
		elif row[2] == "end":
			from = _length(rail)
		var offset: float = row[3]
		_add_signal(row[0] as String, rail, from + offset,
				RailSignal.Governs.TOWARDS_RAIL_END if offset < 0.0
				else RailSignal.Governs.TOWARDS_RAIL_START)


func _add_signal(name: String, rail: String, distance: float, governs: int) -> void:
	assert(distance > 0.0 and distance < _length(rail), "%s is off %s" % [name, rail])
	_signals.append({"name": name, "rail": rail, "distance": distance, "governs": governs})
#endregion


#region Trains
## Rolling stock the playground's trains are made of, and the ids the scene knows them by.
const _STOCK := {
	"passenger": ["res://rolling_stock/passenger_locomotive.tres", "14_passenger"],
	"freight": ["res://rolling_stock/freight_locomotive.tres", "15_freight"],
	"shunting": ["res://rolling_stock/shunting_locomotive.tres", "16_shunting"],
	"coach": ["res://rolling_stock/coach.tres", "18_coach"],
	"freight_wagon": ["res://rolling_stock/freight_wagon.tres", "19_freight_wagon"],
}

## Four trains, each a little way short of a signal at danger, so the level opens with
## every one of them running up to it and waiting for the dispatcher. Placed by the
## nose: [param gap] is how far it stands short of the signal, and the rest of the train
## goes behind, however long its consist is.
func _place_trains() -> void:
	_add_train("Express", "NorthCrossoverOuterFromEast", 14.0, 18.0,
			Train.EndBehavior.TURN_AROUND, "passenger", ["coach"])
	_add_train("Freight", "WyeEastFromTail", 30.0, 9.0, Train.EndBehavior.TURN_AROUND,
			"freight", ["freight_wagon", "freight_wagon", "freight_wagon"], 1.0)
	_add_train("Regional", "DiamondFromSouth", 12.0, 12.0, Train.EndBehavior.TURN_AROUND,
			"passenger", ["coach"])
	_add_train("Shunter", "YardThreeWayFromRight", 10.0, 6.0, Train.EndBehavior.REVERSE,
			"shunting", ["freight_wagon", "freight_wagon"])


func _add_train(name: String, signal_name: String, gap: float, speed: float, end: int,
		locomotive: String, wagons: Array[String], load_factor := 0.0) -> void:
	var held_at: Dictionary = {}
	for rail_signal in _signals:
		if rail_signal["name"] == signal_name:
			held_at = rail_signal
	assert(not held_at.is_empty(), "no signal %s" % signal_name)
	var length := (load(_STOCK[locomotive][0]) as CarType).length
	for wagon in wagons:
		length += Train.COUPLING_GAP + (load(_STOCK[wagon][0]) as CarType).length
	# The train runs the way the signal governs, nose towards it.
	var facing := 1 if held_at["governs"] == RailSignal.Governs.TOWARDS_RAIL_END else -1
	var centre: float = held_at["distance"] - float(facing) * (gap + length * 0.5)
	var rail: String = held_at["rail"]
	assert(centre - length * 0.5 > 0.0 and centre + length * 0.5 < _length(rail),
			"%s does not fit on %s" % [name, rail])
	_trains.append({"name": name, "rail": rail, "distance": centre, "facing": facing,
			"speed": speed, "end": end, "locomotive": locomotive, "wagons": wagons,
			"load": load_factor})
#endregion


#region Checks
## Reports any two stretches of track closer than [constant _CLEARANCE] in plan away
## from a junction, where they are meant to meet. Only a report: the layout constants
## are what to change.
func _check_clearances() -> void:
	var meeting: Array[Vector2] = []
	for turnout in Kit.all_turnouts(_turnouts, _compounds):
		meeting.append(turnout["at"] as Vector2)
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
		var run_kind := Kit.Kind.TRACK
		var run_start := 0.0
		while along <= curve.get_baked_length():
			var at := curve.sample_baked(along, true)
			var plan := Vector2(at.x, at.z)
			var here := along
			along += 0.5
			var kind := Kit.Kind.TRACK
			if not _is_flat_around(plan - SHIFT):
				kind = Kit.kind(_natural(plan - SHIFT), RAILHEAD, BED_DEPTH)
			if kind != run_kind:
				_close_structure(rail, run_kind, run_start, here)
				run_kind = kind
				run_start = here
			if kind == Kit.Kind.TRACK and _is_flat_around(plan - SHIFT):
				continue
			if kind == Kit.Kind.TUNNEL:
				tunnels += 0.5
			elif kind == Kit.Kind.BRIDGE:
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
		_close_structure(rail, run_kind, run_start, curve.get_baked_length())
		for index in columns * rows:
			var gap := nearest[index]
			if gap > CARVE_REACH:
				continue
			var kind := kinds[index] as Kit.Kind
			ceiling[index] = minf(ceiling[index],
					Kit.cut_limit(kind, gap, railheads[index], BED_DEPTH))
			floor_height[index] = maxf(floor_height[index],
					Kit.fill_limit(kind, gap, railheads[index], BED_DEPTH))
	print("  terrain: %d x %d vertices, %.0f m of track in tunnels, %.0f m on bridges"
			% [columns, rows, tunnels, bridges])

	var image := Image.create_empty(columns, rows, false, Image.FORMAT_RF)
	for row in rows:
		for column in columns:
			var index := row * columns + column
			var height := maxf(minf(natural[index], ceiling[index]), floor_height[index])
			image.set_pixel(column, row, Color(height, 0.0, 0.0))
	return image


## Records a finished run of tunnel or bridge along [param rail], for the scene.
## The stone arch is the playground's bridge; the structures demo has the rest.
func _close_structure(rail: String, kind: Kit.Kind, from: float, to: float) -> void:
	if kind == Kit.Kind.TRACK or to - from < 2.0:
		return
	_structures.append({"kind": kind, "rail": rail, "from": from, "to": to})


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
	var resources := 13 + _STOCK.size() + 1 + 3 + 6 + _rail_order.size()
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
		["Script", "res://scripts/trains/wagon_type.gd", "17_wagon_type"],
		["Script", "res://scripts/track/track_mesher.gd", "18_mesher"],
		["Script", "res://scripts/track/bridge.gd", "19_bridge"],
		["Script", "res://scripts/track/tunnel.gd", "20_tunnel"],
	]:
		lines.append('[ext_resource type="%s" path="%s" id="%s"]' % entry)
	for stock: String in _STOCK:
		lines.append('[ext_resource type="Resource" path="%s" id="%s"]' % _STOCK[stock])
	lines.append("")
	lines.append_array(_environment_text())
	for rail in _rail_order:
		lines.append_array(Kit.curve_text(rail, _curves[rail]))

	lines.append('[node name="Main" type="Node3D"]')
	lines.append("")
	lines.append_array(Kit.world_environment_and_sun_text(500.0))
	lines.append_array(Kit.heightmap_ground_text("1_ground", GROUND_SIZE, "13_heights"))
	var pond := _pond_centre() + SHIFT
	lines.append('[node name="Pond" type="MeshInstance3D" parent="."]')
	lines.append("transform = Transform3D(16, 0, 0, 0, 1, 0, 0, 0, 16, %s, %s, %s)"
			% [Kit.num(pond.x), Kit.num(POND_LEVEL), Kit.num(pond.y)])
	lines.append('mesh = SubResource("CylinderMesh_pond")')
	lines.append('material_override = SubResource("StandardMaterial3D_water")')
	lines.append("")
	lines.append('[node name="Stream" type="MeshInstance3D" parent="."]')
	lines.append("transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, %s, 0)"
			% [Kit.num(GULLY_X + SHIFT.x), Kit.num(STREAM_LEVEL)])
	lines.append('mesh = SubResource("BoxMesh_stream")')
	lines.append('material_override = SubResource("StandardMaterial3D_water")')
	lines.append("")

	lines.append_array(Kit.rails_text(_rail_order, "2_rail", BED_DEPTH))
	lines.append_array(Kit.turnouts_text(_turnouts, _compounds, "6_turnout", "11_compound"))
	lines.append_array(Kit.crossings_text(_crossings, "12_crossing"))

	lines.append_array(Kit.group("Structures"))
	var counts := {}
	for structure in _structures:
		var is_bridge: bool = structure["kind"] == Kit.Kind.BRIDGE
		var stem := "%s%s" % ["Bridge" if is_bridge else "Tunnel", structure["rail"]]
		counts[stem] = int(counts.get(stem, 0)) + 1
		var label: String = stem if counts[stem] == 1 else "%s%d" % [stem, counts[stem]]
		lines.append('[node name="%s" type="Node3D" parent="Structures" ' % label
				+ 'node_paths=PackedStringArray("rail")]')
		lines.append('script = ExtResource("%s")' % ("19_bridge" if is_bridge else "20_tunnel"))
		lines.append('rail = NodePath("../../Rails/%s")' % structure["rail"])
		lines.append("from_distance = %s" % Kit.num(snappedf(structure["from"], 0.5)))
		lines.append("to_distance = %s" % Kit.num(snappedf(structure["to"], 0.5)))
		lines.append("")

	lines.append_array(Kit.signals_text(_signals, "9_signal"))
	lines.append_array(Kit.trains_text(_trains, "3_train", "17_wagon_type", _STOCK))

	lines.append('[node name="Track" type="Node3D" parent="."]')
	lines.append('script = ExtResource("18_mesher")')
	lines.append("")

	lines.append_array(_camera_and_ui_text())
	return "\n".join(lines)


## The water under the pond and the stream, after the sky.
func _environment_text() -> PackedStringArray:
	var lines := Kit.environment_text()
	lines.append_array([
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
		"size = Vector3(7, 0.02, %s)" % Kit.num(GROUND_SIZE.y),
		"",
	])
	return lines


func _camera_and_ui_text() -> PackedStringArray:
	return Kit.camera_and_ui_text({"script": "4_camera", "origin": Vector3i(-40, 2, 0),
			"yaw": -15.0, "pitch": -55.0, "zoom": 360.0, "max_zoom": 700.0}, [
		["TrainDebugPanel", "5_panel", false],
		["TurnoutDebugPanel", "7_tpanel", true],
		["SignalDebugPanel", "10_spanel", true],
	], "8_overlay")
#endregion
