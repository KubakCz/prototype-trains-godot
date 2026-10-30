extends TestCase
## scenes/levels/desert.tscn: a level rebuilt from a reference layout, on a baked
## terrain. Its rails are not snapped to the ground - the ground was carved to fit
## them - so the things worth asserting are that the two agree, that every
## junction connects the way the reference does, and that the level opens with a
## train waiting at each entry signal.
##
## Built once and run for 1800 physics frames (30 s of game time) in before_all:
## long enough for the three arrivals to come out of their tunnels and reach their
## signals. Every test after that either reads the settled state or walks the
## network, putting back whatever points it set.

const LEVEL := "res://scenes/levels/desert.tscn"
const SETTLE_FRAMES := 1800
## Ground this far above the railhead is over the roof of a train: a tunnel.
const TUNNEL_CLEARANCE := 4.5
## Ground this close under the railhead, or above it, is in the way of a train.
const BED_CLEARANCE := -0.1
## Railhead this far above the ground is track in the air: a bridge.
const FLOATING := -1.0

var _scene: Node
## Every turnout, including the members of compound assemblies.
var _turnouts: Array[Turnout] = []
var _rails: Array[Rail] = []


func before_all() -> void:
	_scene = await load_scene(LEVEL)
	for turnout: Turnout in _scene.get_node("Turnouts").get_children():
		_turnouts.append(turnout)
	for compound: CompoundTurnout in _scene.get_node("Compounds").get_children():
		_turnouts.append_array(compound.members)
	for rail: Rail in _scene.get_node("Rails").get_children():
		_rails.append(rail)
	await physics_frames(SETTLE_FRAMES)


func test_every_turnout_is_welded_to_its_branch() -> void:
	for turnout: Turnout in _turnouts:
		var gap := turnout.points_position().distance_to(
				turnout.branch_rail.sample_position(turnout.branch_distance()))
		note("%-15s on %-10s @ %7.1f m  %-5s hand  gap %.4f m  tangent %.2f deg"
				% [turnout.name, turnout.main_rail.name, turnout.points_distance(),
				"right" if turnout.branch_side() > 0 else "left", gap,
				turnout.diverge_angle_degrees()])
		assert_less(gap, 0.05, "%s: the branch is welded to the points" % turnout.name)


func test_the_level_has_no_configuration_warnings() -> void:
	var nodes: Array[Node] = []
	nodes.append_array(_turnouts)
	for group: StringName in [&"compound_turnouts", &"crossings", &"signals", &"trains"]:
		nodes.append_array(tree.get_nodes_in_group(group))
	for node: Node in nodes:
		var warnings: PackedStringArray = node._get_configuration_warnings()
		if not warnings.is_empty():
			note("%s: %s" % [node.name, ", ".join(warnings)])
		assert_true(warnings.is_empty(), "%s: no configuration warnings" % node.name)


## The terrain was carved to the track rather than the track snapped to the
## terrain, so this is the one thing that could quietly go wrong: ground rising
## into the space a train drives through. Along every rail, metre by metre, the
## ground is either under the sleepers or over the roof. The only exception is a
## tunnel mouth, where a heightfield can only rise from the bed to the roof across
## one grid cell - so a stretch that is neither must run straight into a tunnel.
func test_the_ground_never_rises_into_a_passing_train() -> void:
	for rail: Rail in _rails:
		var kinds := _clearance_profile(rail)
		var tunnel := 0
		var floating := 0
		var runs: Array[Vector2i] = []
		for i in kinds.size():
			match kinds[i]:
				&"tunnel":
					tunnel += 1
				&"floating":
					floating += 1
				&"in_the_way":
					if not runs.is_empty() and runs[-1].y == i - 1:
						runs[-1].y = i
					else:
						runs.append(Vector2i(i, i))
		var faces := PackedStringArray()
		for run in runs:
			faces.append("%d m" % run.x)
		note("%-12s %6.0f m: %4d m in tunnels, %3d m on bridges, tunnel mouths at %s"
				% [rail.name, rail.rail_length(), tunnel, floating, ", ".join(faces)])
		for run in runs:
			var before := kinds[maxi(run.x - 1, 0)]
			var after := kinds[mini(run.y + 1, kinds.size() - 1)]
			assert_true(before == &"tunnel" or after == &"tunnel",
					"%s %d-%d m: ground in the way only at a tunnel mouth" % [rail.name, run.x, run.y])
			assert_less(float(run.y - run.x + 1), 8.0,
					"%s %d m: a tunnel mouth no deeper than two grid cells" % [rail.name, run.x])


## The reference has one viaduct, over the gully north of the lake, and nothing
## else in the air: the terrain is below the railhead only there.
func test_the_track_leaves_the_ground_only_on_the_bridge() -> void:
	var loop: Rail = _scene.get_node("Rails/LoopLine")
	for rail: Rail in _rails:
		var kinds := _clearance_profile(rail)
		var floating := kinds.count(&"floating")
		if rail != loop:
			assert_eq(floating, 0, "%s never leaves the ground" % rail.name)
			continue
		var first := kinds.find(&"floating")
		var last := kinds.rfind(&"floating")
		var bridge_at := rail.sample_position(float(first + last) * 0.5)
		note("the bridge: %s %d-%d m, at (%.0f, %.0f)" % [rail.name, first, last,
				bridge_at.x, bridge_at.z])
		assert_eq(last - first + 1, floating, "the bridge is one span")
		assert_between(float(floating), 10.0, 40.0, "and a bridge-sized one")


## The ridge line crosses over the tunnel line near the middle of the level - in
## the reference the second is drawn dashed where it runs underneath. Both are the
## same rail, LoopLine, a good 1000 m apart along it: the first pass is somewhere
## in its first 750 metres, the second in its last 375.
func test_the_ridge_line_crosses_the_tunnel_line_well_above_it() -> void:
	var loop: Rail = _scene.get_node("Rails/LoopLine")
	var length := loop.rail_length()
	# Coarse over both stretches, then fine around the best pair.
	var pair := _closest_in_plan(loop, Vector2(0.0, 750.0), Vector2(length - 375.0, length), 4.0)
	pair = _closest_in_plan(loop, Vector2(pair.x - 6.0, pair.x + 6.0),
			Vector2(pair.y - 6.0, pair.y + 6.0), 0.1)
	var over := loop.sample_position(pair.x)
	var under := loop.sample_position(pair.y)
	var best := Vector2(over.x - under.x, over.z - under.z).length()
	note("the two passes meet %.2f m apart in plan, %.1f m apart in height, at (%.0f, %.0f)"
			% [best, over.y - under.y, over.x, over.z])
	assert_less(best, 1.5, "the loop line crosses itself in plan")
	assert_greater(over.y - under.y, 6.0, "with the first pass well over the second")
	var ground = loop.ground_height_at(under)
	if assert_not_null(ground, "there is ground over the crossing"):
		assert_greater(float(ground) - under.y, TUNNEL_CLEARANCE,
				"and the lower one is in a tunnel there")


## Every train comes out of a tunnel at the edge of the level and runs up to the
## first signal, which is at danger - the level is meant to open with the
## dispatcher's first decisions already waiting.
func test_each_arrival_is_held_at_its_entry_signal() -> void:
	for pair: Array in [["WestArrival", "WestEntry"], ["NorthArrival", "NorthEntry"],
			["EastArrival", "EastEntry"]]:
		var train: Train = _scene.get_node("Trains/" + str(pair[0]))
		var rail_signal: RailSignal = _scene.get_node("Signals/" + str(pair[1]))
		note("%-12s on %-10s @ %6.1f m  %s" % [train.name, train.rail.name, train.distance,
				train.blocked_description()])
		assert_eq(train.blocking_signal, rail_signal, "%s is held at %s" % [train.name,
				rail_signal.name])


## The loop round the lake is a balloon: a train leaving the north line over the
## bridge comes back through the tunnel onto the same line, facing the other way.
func test_the_balloon_loop_turns_a_train_round() -> void:
	var north: Rail = _scene.get_node("Rails/NorthLine")
	var step := _walk(north, 300.0, 1, 1400.0,
			{"BridgeJunction": Turnout.Position.REVERSE, "TunnelJunction": Turnout.Position.REVERSE})
	note("westbound off the north line: %s @ %.1f m heading %+d  %s" % [step.rail.name,
			step.distance, step.direction, step.describe()])
	assert_eq(step.rail, north, "it comes back onto the north line")
	assert_eq(step.direction, -1, "heading east, the way it came")


## The wye east of the hill: from each of its three legs a train reaches both of
## the others, given the points.
func test_the_wye_joins_each_of_its_legs_to_both_others() -> void:
	var loop: Rail = _scene.get_node("Rails/LoopLine")
	var east: Rail = _scene.get_node("Rails/EastLine")
	var bottom: Rail = _scene.get_node("Rails/BottomLine")
	var wye_north: Turnout = _scene.get_node("Turnouts/WyeNorth")
	var wye_south: Turnout = _scene.get_node("Turnouts/WyeSouth")
	var wye_east: Turnout = _scene.get_node("Turnouts/WyeEast")
	var normal := Turnout.Position.NORMAL
	var reverse := Turnout.Position.REVERSE
	# Just outside each corner, heading in.
	var from_north := wye_north.points_distance() + 40.0
	var from_south := wye_south.points_distance() - 30.0
	var from_east := wye_east.points_distance() + 40.0
	var cases := [
		["north -> south", loop, from_north, -1, {"WyeNorth": normal, "WyeSouth": normal,
				"SouthJunction": reverse}, bottom, -1],
		["north -> east", loop, from_north, -1, {"WyeNorth": reverse, "WyeEast": normal},
				east, 1],
		["south -> north", loop, from_south, 1, {"WyeSouth": normal, "WyeNorth": normal},
				loop, 1],
		["south -> east", loop, from_south, 1, {"WyeSouth": reverse, "WyeEast": reverse},
				east, 1],
		["east -> north", east, from_east, -1, {"WyeEast": normal, "WyeNorth": reverse},
				loop, 1],
		["east -> south", east, from_east, -1, {"WyeEast": reverse, "WyeSouth": reverse,
				"SouthJunction": reverse}, bottom, -1],
	]
	for case: Array in cases:
		var step := _walk(case[1], case[2], case[3], 330.0, case[4])
		note("%-15s %s @ %6.1f m heading %+d  %s" % [case[0], step.rail.name, step.distance,
				step.direction, step.describe()])
		assert_eq(step.rail, case[5], "%s ends on %s" % [case[0], (case[5] as Rail).name])
		assert_eq(step.direction, case[6], "%s heading %+d" % [case[0], case[6]])
		assert_false(step.is_blocked(), "%s is not held on the way" % case[0])


## Where the loop touches the bottom line south of the lake, a scissors crossover
## lets a train change line in either direction.
func test_the_lake_scissors_crosses_both_ways() -> void:
	var loop: Rail = _scene.get_node("Rails/LoopLine")
	var bottom: Rail = _scene.get_node("Rails/BottomLine")
	var scissors: CompoundTurnout = _scene.get_node("Compounds/LakeScissors")
	var west: Turnout = _scene.get_node("Compounds/LakeScissors/SouthWest")
	var east: Turnout = _scene.get_node("Compounds/LakeScissors/NorthEast")
	var was := scissors.compound_position
	scissors.compound_position = 1
	var eastbound := TrackWalker.walk(bottom, west.points_distance() - 20.0, 1, 80.0)
	var westbound := TrackWalker.walk(loop, east.points_distance() + 20.0, -1, 80.0)
	scissors.compound_position = was
	note("eastbound on the bottom line: %s @ %.1f m  %s" % [eastbound.rail.name,
			eastbound.distance, eastbound.describe()])
	note("westbound on the loop line:   %s @ %.1f m  %s" % [westbound.rail.name,
			westbound.distance, westbound.describe()])
	assert_eq(eastbound.rail, loop, "set to cross, the bottom line leads onto the loop")
	assert_eq(westbound.rail, bottom, "and the loop leads onto the bottom line")


## Every rail sampled once a metre, each sample one of: on its bed, in the way,
## in a tunnel, or in the air.
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


## The pair of distances, one in each range, at which [param rail] comes closest
## to itself in plan, searched every [param step] metres.
func _closest_in_plan(rail: Rail, first: Vector2, second: Vector2, step: float) -> Vector2:
	var best := INF
	var found := Vector2.ZERO
	var a := first.x
	while a <= first.y:
		var p := rail.sample_position(a)
		var b := second.x
		while b <= second.y:
			var q := rail.sample_position(b)
			var gap := Vector2(p.x - q.x, p.z - q.z).length()
			if gap < best:
				best = gap
				found = Vector2(a, b)
			b += step
		a += step
	return found


## Walks with some points set, then puts them back as they were.
func _walk(rail: Rail, distance: float, direction: int, length: float,
		settings: Dictionary) -> TrackWalker.Step:
	var saved: Dictionary = {}
	for name: String in settings:
		var turnout: Turnout = _scene.get_node("Turnouts/" + name)
		saved[turnout] = turnout.turnout_position
		turnout.turnout_position = settings[name]
	var step := TrackWalker.walk(rail, distance, direction, length)
	for turnout: Turnout in saved:
		turnout.turnout_position = saved[turnout]
	return step
