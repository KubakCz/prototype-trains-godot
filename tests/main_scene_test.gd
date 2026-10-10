extends TestCase
## The playground, scenes/main.tscn: every kind of junction the prototype has on one
## small layout, every way into every one of them protected by a signal, four trains
## waiting at red, and one carved corner with a bridge and a tunnel.
##
## The layout, built by tools/build_playground.gd:
##
## - A double-track oval. The outer track is NorthLine (from the wye's apex, west
##   along the north straight and round the balloon) and OuterLine (from the balloon
##   round the rest of the oval to the foot of the north wye leg). The inner track,
##   InnerLine, leaves the outer one at SouthMerge and rejoins it at NorthMerge, so the
##   east curve is single track.
## - NorthCrossover on the north straight, SouthScissors on the south one.
## - A balloon loop round a pond, off the outer north straight at BalloonEast and back
##   at BalloonWest.
## - A wye at the east end: WyeNorth, WyeSouth and the apex WyeEast, whose tail -
##   HillLine - crosses a gully on a bridge and a hill in a tunnel to a dead end.
## - FreightLine from a dead end south of the oval, over both south tracks on two
##   diamonds, into the middle of the oval, through YardSlip to a goods stub.
## - The yard: YardLead off the inner track at YardEntry, crossing the freight line in
##   YardSlip, then YardThreeWay fanning into three dead-end roads.
##
## Built once and run for 1100 physics frames (18 s of game time) in before_all: long
## enough for the freight train to come out of the tunnel and reach its signal. Tests
## after that either read the settled state or walk the network, putting back
## whatever points they set.

const MAIN_SCENE := "res://scenes/main.tscn"
const SETTLE_FRAMES := 1100
## Ground this far above the railhead is over the roof of a train: a tunnel.
const TUNNEL_CLEARANCE := 4.5
## Ground this close under the railhead, or above it, is in the way of a train.
const BED_CLEARANCE := -0.1
## Railhead this far above the ground is track in the air: a bridge.
const FLOATING := -1.0

var _scene: Node
## Every turnout, including the members of compound assemblies.
var _turnouts: Array[Turnout] = []
var _compounds: Array[CompoundTurnout] = []
var _crossings: Array[Crossing] = []
var _signals: Array[RailSignal] = []
var _trains: Array[Train] = []
var _rails: Array[Rail] = []


func before_all() -> void:
	_scene = await load_scene(MAIN_SCENE)
	for turnout: Turnout in _scene.get_node("Turnouts").get_children():
		_turnouts.append(turnout)
	for compound: CompoundTurnout in _scene.get_node("Compounds").get_children():
		_compounds.append(compound)
		_turnouts.append_array(compound.members)
	for crossing: Crossing in _scene.get_node("Crossings").get_children():
		_crossings.append(crossing)
	for rail_signal: RailSignal in _scene.get_node("Signals").get_children():
		_signals.append(rail_signal)
	for train: Train in _scene.get_node("Trains").get_children():
		_trains.append(train)
	for rail: Rail in _scene.get_node("Rails").get_children():
		_rails.append(rail)
	await physics_frames(SETTLE_FRAMES)


func test_every_turnout_is_welded_to_its_branch() -> void:
	for turnout: Turnout in _turnouts:
		var gap := turnout.points_position().distance_to(
				turnout.branch_rail.sample_position(turnout.branch_distance()))
		note("%-12s on %-11s @ %6.1f m  %-5s hand  gap %.4f m  tangent %.2f deg"
				% [turnout.name, turnout.main_rail.name, turnout.points_distance(),
				"right" if turnout.branch_side() > 0 else "left", gap,
				turnout.diverge_angle_degrees()])
		assert_less(gap, 0.05, "%s: the branch is welded to the points" % turnout.name)


func test_the_level_has_no_configuration_warnings() -> void:
	var nodes: Array[Node] = []
	nodes.append_array(_turnouts)
	nodes.append_array(_compounds)
	nodes.append_array(_crossings)
	nodes.append_array(_signals)
	for node: Node in nodes:
		var warnings: PackedStringArray = node._get_configuration_warnings()
		if not warnings.is_empty():
			note("%s: %s" % [node.name, ", ".join(warnings)])
		assert_true(warnings.is_empty(), "%s: no configuration warnings" % node.name)


## One of each kind the prototype has, so the playground really is all of it.
func test_the_level_has_one_of_every_kind_of_junction() -> void:
	var kinds: Array[CompoundTurnout.Kind] = []
	for compound in _compounds:
		kinds.append(compound.kind)
	for kind: CompoundTurnout.Kind in CompoundTurnout.Kind.values():
		assert_true(kinds.has(kind), "there is a %s"
				% CompoundTurnout.Kind.keys()[kind].to_lower().replace("_", " "))
	var plain := 0
	for crossing in _crossings:
		if not _is_inside_an_assembly(crossing):
			plain += 1
	note("%d turnouts (%d of them in assemblies), %d crossings (%d plain), %d signals"
			% [_turnouts.size(), _turnouts.size() - _scene.get_node("Turnouts").get_child_count(),
			_crossings.size(), plain, _signals.size()])
	assert_greater(float(plain), 0.0, "and a plain diamond crossing")
	var hands: Array[int] = []
	for turnout: Turnout in _scene.get_node("Turnouts").get_children():
		if not hands.has(turnout.branch_side()):
			hands.append(turnout.branch_side())
	assert_eq(hands.size(), 2, "simple turnouts of both hands")


#region Starting state
## The level opens with every train already waiting for the dispatcher, each at a
## red signal in a different part of the layout, throttle still open.
func test_every_train_is_held_at_a_red_signal() -> void:
	var expected := {
		"Express": "NorthCrossoverOuterFromEast",
		"Freight": "WyeEastFromTail",
		"Regional": "DiamondFromSouth",
		"Shunter": "YardThreeWayFromRight",
	}
	for train: Train in _trains:
		note("%-9s on %-11s @ %6.1f m  %s" % [train.name, train.rail.name, train.distance,
				train.blocked_description()])
		var rail_signal: RailSignal = _scene.get_node("Signals/%s" % expected[str(train.name)])
		assert_eq(train.blocking_signal, rail_signal, "%s is held at %s" % [train.name,
				rail_signal.name])
		assert_eq(train.throttle, 1, "%s still has its throttle open" % train.name)


func test_every_signal_starts_at_danger() -> void:
	for rail_signal in _signals:
		assert_eq(rail_signal.aspect, RailSignal.Aspect.DANGER, "%s is at danger" % rail_signal.name)


## A train's body is a chord, so its origin sits inside the arc on a bend. What must
## hold whatever the curvature is the arc position: the chord midpoint is symmetric
## about the train's own distance, so projecting the origin back onto the curve has
## to return that distance.
func test_every_train_sits_at_the_arc_position_its_distance_says() -> void:
	for train: Train in _trains:
		var projected := train.rail.curve.get_closest_offset(
				train.rail.to_local(train.global_position))
		var inset := train.global_position.distance_to(
				train.rail.sample_position(train.rail.clamp_distance(train.distance)))
		note("%-9s on %-11s distance %6.1f m, projects back to %6.1f m, chord inset %.2f m"
				% [train.name, train.rail.name, train.distance, projected, inset])
		assert_near(projected, train.distance, 0.6,
				"%s sits at the arc position its distance says" % train.name)
		assert_less(inset, 2.5, "%s is not flung off %s" % [train.name, train.rail.name])
#endregion


#region Signalling
## The rule the level is built to: from wherever a train can come at a junction, it
## meets a signal governing its way in before it reaches the junction - so no train
## ever has to be let into one without the dispatcher's say.
##
## Checked from the junction's side: walking out along every track that leads in,
## the first thing on the rail is that signal, before any other points and before
## the end of the line. Crossings are passed over rather than stopped at, because
## the two diamonds stand 5 m apart and are protected as one; the crossings in the
## middle of the scissors and the slip belong to their assemblies, whose outer legs
## are what is checked.
func test_every_way_into_every_junction_is_protected() -> void:
	var ways_in: Array[Array] = []
	for turnout: Turnout in _scene.get_node("Turnouts").get_children():
		for leg: Turnout.Leg in [Turnout.Leg.TOE, Turnout.Leg.THROUGH, Turnout.Leg.DIVERGING]:
			ways_in.append([str(turnout.name), turnout.leg_exit(leg)])
	for compound in _compounds:
		for entry in compound.outer_legs():
			var member: Turnout = entry["member"]
			ways_in.append(["%s/%s" % [compound.name, member.name],
					member.leg_exit(entry["leg"] as Turnout.Leg)])
	for crossing in _crossings:
		if _is_inside_an_assembly(crossing):
			continue
		for rail: Rail in [crossing.rail_a, crossing.rail_b]:
			for direction: int in [1, -1]:
				ways_in.append([str(crossing.name), Turnout.Exit.new(rail,
						crossing.distances_on(rail)[0], direction)])
	# The two diamonds share the freight line's pair, so ways in outnumber signals; what
	# has to hold the other way is that no signal stands there protecting nothing.
	var protecting: Dictionary[RailSignal, bool] = {}
	for way_in in ways_in:
		var rail_signal := _assert_protected(way_in[0] as String, way_in[1] as Turnout.Exit)
		if rail_signal != null:
			protecting[rail_signal] = true
	note("%d ways in, protected by %d of the %d signals" % [ways_in.size(), protecting.size(),
			_signals.size()])
	for rail_signal in _signals:
		assert_true(protecting.has(rail_signal), "%s protects a way in" % rail_signal.name)


## The signal protecting the way in along [param out], failing if there is none.
func _assert_protected(junction: String, out: Turnout.Exit) -> RailSignal:
	var found := _first_on_the_way(out)
	var rail_signal := found as RailSignal
	if rail_signal == null:
		fail("%s is protected from %s, %s" % [junction, out.rail.name,
				"rising" if out.direction > 0 else "falling"],
				"walking out from %.1f m the first thing met is %s" % [out.distance,
				str(found.name) if found != null else "the end of the rail"])
		return null
	note("%-28s <- %-28s %5.1f m out along %s" % [junction, rail_signal.name,
			absf(rail_signal.signal_distance() - out.distance), out.rail.name])
	succeed("%s is protected by %s" % [junction, rail_signal.name])
	return rail_signal


## The nearest turnout, or signal governing back the way [param out] came, strictly
## beyond [param out]'s distance along its rail; null when the rail ends first.
func _first_on_the_way(out: Turnout.Exit) -> Node:
	var best: Node = null
	var best_at := INF
	for node in out.rail.attachments():
		var at := PackedFloat64Array()
		if node is Turnout:
			at = (node as Turnout).distances_on(out.rail)
		elif node is RailSignal and (node as RailSignal).governed_direction() == -out.direction:
			at = (node as RailSignal).distances_on(out.rail)
		for distance in at:
			var ahead := (distance - out.distance) * float(out.direction)
			if ahead > TrackWalker.EPSILON and ahead < best_at:
				best_at = ahead
				best = node
	return best


## Whether every way out of [param crossing] runs into the points of an assembly
## before anything else - the middle of a scissors or a double slip.
func _is_inside_an_assembly(crossing: Crossing) -> bool:
	for rail: Rail in [crossing.rail_a, crossing.rail_b]:
		for direction: int in [1, -1]:
			var first := _first_on_the_way(Turnout.Exit.new(rail,
					crossing.distances_on(rail)[0], direction)) as Turnout
			if first == null or first.assembly == null:
				return false
	return true
#endregion


#region Routes
## Into the loop at its west end, round the pond, and back onto the north straight
## heading the other way.
func test_the_balloon_loop_turns_a_train_round() -> void:
	var outer := _rail("OuterLine")
	var west: Turnout = _scene.get_node("Turnouts/BalloonWest")
	var step := _walk(outer, west.points_distance() - 20.0, 1, 260.0,
			{"Turnouts/BalloonWest": Turnout.Position.REVERSE})
	note("westbound off the A-B stretch: %s @ %.1f m heading %+d  %s" % [step.rail.name,
			step.distance, step.direction, step.describe()])
	assert_eq(step.rail, _rail("NorthLine"), "it comes back onto the north straight")
	assert_eq(step.direction, -1, "heading east, the way it came")
	assert_false(step.is_blocked(), "without being held on the way")


## Up the north leg into the tail, where the line ends beyond the hill; and from
## there back down the south leg onto the oval.
func test_the_wye_leads_into_the_tail_and_back_out_onto_the_other_straight() -> void:
	var hill := _rail("HillLine")
	var wye_north: Turnout = _scene.get_node("Turnouts/WyeNorth")
	var out := _walk(_rail("NorthLine"), wye_north.points_distance() + 40.0, -1, 600.0,
			{"Turnouts/WyeEast": Turnout.Position.REVERSE})
	note("eastbound on the north straight: %s @ %.1f m  %s" % [out.rail.name, out.distance,
			out.describe()])
	assert_eq(out.rail, hill, "the north leg leads into the tail")
	assert_true(out.at_dead_end, "which ends beyond the hill")
	assert_true(out.covers(_rail("HillLine"), 60.0), "through the tunnel")

	var back := _walk(hill, 0.0, 1, 400.0, {"Turnouts/WyeSouth": Turnout.Position.REVERSE})
	note("back out of the tail: %s @ %.1f m heading %+d  %s" % [back.rail.name, back.distance,
			back.direction, back.describe()])
	assert_eq(back.rail, _rail("OuterLine"), "the south leg leads onto the south straight")
	assert_eq(back.direction, -1, "heading west")
	assert_false(back.is_blocked(), "without being held on the way")


func test_the_north_crossover_moves_an_eastbound_train_onto_the_inner_track() -> void:
	var points: Turnout = _scene.get_node("Compounds/NorthCrossover/OuterPoints")
	var start := points.points_distance() + 30.0
	var parallel := _walk(_rail("NorthLine"), start, -1, 80.0, {})
	var crossed := _walk(_rail("NorthLine"), start, -1, 80.0,
			{"Compounds/NorthCrossover": 1})
	note("parallel: %s @ %.1f m  %s" % [parallel.rail.name, parallel.distance,
			parallel.describe()])
	note("cross:    %s @ %.1f m  %s" % [crossed.rail.name, crossed.distance, crossed.describe()])
	assert_eq(parallel.rail, _rail("NorthLine"), "parallel keeps it on the outer track")
	assert_eq(crossed.rail, _rail("InnerLine"), "cross puts it on the inner track")
	assert_eq(crossed.direction, 1, "still heading east")


## A scissors crosses both ways: set to cross, an eastbound train on the outer track
## comes out on the inner one, and a westbound one on the outer track does too.
func test_the_south_scissors_crosses_both_ways() -> void:
	var outer := _rail("OuterLine")
	var west: Turnout = _scene.get_node("Compounds/SouthScissors/SouthWest")
	var east: Turnout = _scene.get_node("Compounds/SouthScissors/SouthEast")
	var cross := {"Compounds/SouthScissors": 1}
	var eastbound := _walk(outer, west.points_distance() - 20.0, 1, 80.0, cross)
	var westbound := _walk(outer, east.points_distance() + 20.0, -1, 80.0, cross)
	note("eastbound: %s @ %.1f m heading %+d  %s" % [eastbound.rail.name, eastbound.distance,
			eastbound.direction, eastbound.describe()])
	note("westbound: %s @ %.1f m heading %+d  %s" % [westbound.rail.name, westbound.distance,
			westbound.direction, westbound.describe()])
	assert_eq(eastbound.rail, _rail("InnerLine"), "eastbound, the outer track leads onto the inner")
	assert_eq(eastbound.direction, -1, "still heading east")
	assert_eq(westbound.rail, _rail("InnerLine"), "and so does westbound")
	assert_eq(westbound.direction, 1, "still heading west")


## Whichever track a train comes into the slip on, straight keeps it there and slip
## puts it on the other.
func test_the_yard_slip_takes_either_track_onto_either() -> void:
	var lead := _rail("YardLead")
	var freight := _rail("FreightLine")
	var middle: Crossing = _scene.get_node("Crossings/YardSlipMiddle")
	for case: Array in [[lead, freight], [freight, lead]]:
		var from: Rail = case[0]
		var start := middle.distances_on(from)[0] - 30.0
		var straight := _walk(from, start, 1, 60.0, {})
		var slipped := _walk(from, start, 1, 60.0, {"Compounds/YardSlip": 1})
		note("from %-11s straight: %-11s slip: %s" % [from.name, straight.rail.name,
				slipped.rail.name])
		assert_eq(straight.rail, from, "straight keeps a train from %s on it" % from.name)
		assert_eq(slipped.rail, case[1] as Rail, "slip puts it on %s" % (case[1] as Rail).name)


func test_the_yard_three_way_fans_into_three_roads() -> void:
	var three_way: CompoundTurnout = _scene.get_node("Compounds/YardThreeWay")
	var start := three_way.members[0].points_distance() - 20.0
	var expected: Array[String] = ["YardLead", "YardLeft", "YardRight"]
	for index in three_way.position_count():
		var step := _walk(_rail("YardLead"), start, 1, 200.0, {"Compounds/YardThreeWay": index})
		note("%-8s %s @ %.1f m  %s" % [three_way.position_label(index), step.rail.name,
				step.distance, step.describe()])
		assert_eq(str(step.rail.name), expected[index], "%s leads onto %s"
				% [three_way.position_label(index), expected[index]])
		assert_true(step.at_dead_end, "which ends at buffers")


## From the dead end south of the oval, straight across both tracks of it and on
## through the middle of the yard to the goods stub.
func test_the_freight_line_crosses_the_oval_on_the_level() -> void:
	var freight := _rail("FreightLine")
	var step := _walk(freight, 0.0, 1, 400.0, {})
	note("from the south: %s @ %.1f m  %s" % [step.rail.name, step.distance, step.describe()])
	assert_eq(step.rail, freight, "it stays on the freight line")
	assert_true(step.at_dead_end, "all the way to the goods stub")
	for name: String in ["OuterDiamond", "InnerDiamond"]:
		var crossing: Crossing = _scene.get_node("Crossings/%s" % name)
		assert_true(step.covers(freight, crossing.distances_on(freight)[0]),
				"crossing the oval at %s" % name)


## The inner track is a long loop off the outer one: from the north straight it
## rejoins the outer track at NorthMerge, and from the south one it leaves it at
## SouthMerge.
func test_the_inner_track_rejoins_the_outer_one_at_the_merges() -> void:
	var inner := _rail("InnerLine")
	var to_north := _walk(inner, inner.rail_length() - 60.0, 1, 100.0,
			{"Turnouts/NorthMerge": Turnout.Position.REVERSE})
	var to_south := _walk(inner, 60.0, -1, 100.0,
			{"Turnouts/SouthMerge": Turnout.Position.REVERSE})
	note("eastbound on the inner north: %s heading %+d  %s" % [to_north.rail.name,
			to_north.direction, to_north.describe()])
	note("eastbound on the inner south: %s heading %+d  %s" % [to_south.rail.name,
			to_south.direction, to_south.describe()])
	assert_eq(to_north.rail, _rail("NorthLine"), "the inner north straight runs onto NorthLine")
	assert_eq(to_south.rail, _rail("OuterLine"), "the inner south straight onto OuterLine")
	assert_false(to_north.is_blocked() or to_south.is_blocked(), "without being held")
#endregion


#region Terrain
## Only the corner beyond the wye was carved; the rest is flat, and the track lies on
## its bed. Along every rail, metre by metre, the ground is either under the
## sleepers or over the roof, except at a tunnel mouth, where a heightfield can only
## rise from the bed to the roof across one grid cell.
func test_the_ground_never_rises_into_a_passing_train() -> void:
	for rail: Rail in _rails:
		var kinds := _clearance_profile(rail)
		var runs: Array[Vector2i] = []
		for i in kinds.size():
			if kinds[i] != &"in_the_way":
				continue
			if not runs.is_empty() and runs[-1].y == i - 1:
				runs[-1].y = i
			else:
				runs.append(Vector2i(i, i))
		for run in runs:
			var before := kinds[maxi(run.x - 1, 0)]
			var after := kinds[mini(run.y + 1, kinds.size() - 1)]
			assert_true(before == &"tunnel" or after == &"tunnel",
					"%s %d-%d m: ground in the way only at a tunnel mouth" % [rail.name, run.x,
					run.y])
			assert_less(float(run.y - run.x + 1), 4.0,
					"%s %d m: a tunnel mouth no deeper than two grid cells" % [rail.name, run.x])
		if rail.name != "HillLine":
			assert_eq(kinds.count(&"bed"), kinds.size(), "%s lies on its bed all the way"
					% rail.name)


## The tail crosses one gully on one bridge and goes through one hill in one tunnel,
## and nothing else on the level is anything but flat.
func test_the_tail_crosses_a_bridge_and_runs_through_a_tunnel() -> void:
	var hill := _rail("HillLine")
	var kinds := _clearance_profile(hill)
	for kind: StringName in [&"floating", &"tunnel"]:
		var first := kinds.find(kind)
		var last := kinds.rfind(kind)
		var count := kinds.count(kind)
		var at := hill.sample_position(float(first + last) * 0.5)
		note("%s: HillLine %d-%d m, at (%.0f, %.0f)" % [kind, first, last, at.x, at.z])
		assert_eq(last - first + 1, count, "the %s is one stretch" % kind)
		assert_between(float(count), 10.0, 60.0, "of a sensible length")
	assert_less(float(kinds.find(&"tunnel")), float(kinds.find(&"floating")),
			"coming from the dead end, first the tunnel and then the bridge")


## Every rail sampled once a metre, each sample one of: on its bed, in the way, in a
## tunnel, or in the air.
func _clearance_profile(rail: Rail) -> Array[StringName]:
	var kinds: Array[StringName] = []
	var along := 0.0
	while along <= rail.rail_length():
		var railhead := rail.sample_position(along)
		var ground = rail.ground_height_at(railhead)
		var clearance := float(ground) - railhead.y if ground != null else -INF
		if clearance > TUNNEL_CLEARANCE:
			kinds.append(&"tunnel")
		elif clearance > BED_CLEARANCE:
			kinds.append(&"in_the_way")
		elif clearance < FLOATING:
			kinds.append(&"floating")
		else:
			kinds.append(&"bed")
		along += 1.0
	return kinds
#endregion


func _rail(rail_name: String) -> Rail:
	return _scene.get_node("Rails/%s" % rail_name)


## Walks with some points set, then puts them back as they were. [param settings]
## maps a turnout's or an assembly's path to the position it is to be in.
func _walk(rail: Rail, distance: float, direction: int, length: float,
		settings: Dictionary) -> TrackWalker.Step:
	var saved := {}
	for path: String in settings:
		var node := _scene.get_node(path)
		if node is CompoundTurnout:
			saved[node] = (node as CompoundTurnout).compound_position
			(node as CompoundTurnout).compound_position = settings[path]
		else:
			saved[node] = (node as Turnout).turnout_position
			(node as Turnout).turnout_position = settings[path]
	var step := TrackWalker.walk(rail, distance, direction, length)
	for node: Node in saved:
		if node is CompoundTurnout:
			(node as CompoundTurnout).compound_position = saved[node]
		else:
			(node as Turnout).turnout_position = saved[node]
	return step
