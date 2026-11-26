class_name JunctionProtection
extends RefCounted
## The rule every level is built to, shared by the level suites: from wherever a train
## can come at a junction, it meets a signal governing its way in before it reaches the
## junction - so no train ever has to be let into one without the dispatcher's say.
##
## Checked from the junction's side: walking out along every track that leads in, the
## first thing on the rail is that signal, before any other points and before the end
## of the line. Crossings are passed over rather than stopped at, because two diamonds
## may stand a few metres apart and be protected as one; the crossings in the middle of
## a scissors or a slip belong to their assemblies, whose outer legs are what is
## checked.


## Every way into a junction, as [code][junction name, Turnout.Exit][/code]: each leg
## of every lone turnout, each outer leg of every assembly, and both ways along both
## rails of every crossing that is not inside an assembly.
static func ways_in(turnouts: Array[Turnout], compounds: Array[CompoundTurnout],
		crossings: Array[Crossing]) -> Array[Array]:
	var found: Array[Array] = []
	for turnout in turnouts:
		if turnout.assembly != null:
			continue
		for leg: Turnout.Leg in [Turnout.Leg.TOE, Turnout.Leg.THROUGH, Turnout.Leg.DIVERGING]:
			found.append([str(turnout.name), turnout.leg_exit(leg)])
	for compound in compounds:
		for entry in compound.outer_legs():
			var member: Turnout = entry["member"]
			found.append(["%s/%s" % [compound.name, member.name],
					member.leg_exit(entry["leg"] as Turnout.Leg)])
	for crossing in crossings:
		if is_inside_an_assembly(crossing):
			continue
		for rail: Rail in [crossing.rail_a, crossing.rail_b]:
			for direction: int in [1, -1]:
				found.append([str(crossing.name), Turnout.Exit.new(rail,
						crossing.distances_on(rail)[0], direction)])
	return found


## Asserts on [param case] that every one of [param ways] is protected, and returns the
## signals that protect them.
static func check(case: TestCase, ways: Array[Array]) -> Dictionary[RailSignal, bool]:
	var protecting: Dictionary[RailSignal, bool] = {}
	for way_in in ways:
		var rail_signal := assert_protected(case, way_in[0] as String, way_in[1] as Turnout.Exit)
		if rail_signal != null:
			protecting[rail_signal] = true
	return protecting


## The signal protecting the way in along [param out], failing on [param case] if there
## is none.
static func assert_protected(case: TestCase, junction: String, out: Turnout.Exit) -> RailSignal:
	var found := first_on_the_way(out)
	var rail_signal := found as RailSignal
	if rail_signal == null:
		case.fail("%s is protected from %s, %s" % [junction, out.rail.name,
				"rising" if out.direction > 0 else "falling"],
				"walking out from %.1f m the first thing met is %s" % [out.distance,
				str(found.name) if found != null else "the end of the rail"])
		return null
	case.note("%-28s <- %-28s %5.1f m out along %s" % [junction, rail_signal.name,
			absf(rail_signal.signal_distance() - out.distance), out.rail.name])
	case.succeed("%s is protected by %s" % [junction, rail_signal.name])
	return rail_signal


## The nearest turnout, or signal governing back the way [param out] came, strictly
## beyond [param out]'s distance along its rail; null when the rail ends first.
static func first_on_the_way(out: Turnout.Exit) -> Node:
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
static func is_inside_an_assembly(crossing: Crossing) -> bool:
	for rail: Rail in [crossing.rail_a, crossing.rail_b]:
		for direction: int in [1, -1]:
			var first := first_on_the_way(Turnout.Exit.new(rail,
					crossing.distances_on(rail)[0], direction)) as Turnout
			if first == null or first.assembly == null:
				return false
	return true


## The rule a level signalled the way stations are is built to, rather than one signal
## per junction: from every one of [param ways] every way back - through any points, in
## either position - meets a signal governing towards the junction before the end of the
## line. A station's throat and the junctions between stations have no signals of their
## own: a train coming at them has passed an entry or an exit signal on the way.
## Asserts on [param case]; returns the signals met.
static func check_signalled(case: TestCase, ways: Array[Array]) -> Dictionary[RailSignal, bool]:
	var protecting: Dictionary[RailSignal, bool] = {}
	for way_in in ways:
		var junction: String = way_in[0]
		var frontier: Array[Turnout.Exit] = [way_in[1] as Turnout.Exit]
		var seen: Dictionary[String, bool] = {}
		var met: Array[String] = []
		var open := true
		while not frontier.is_empty() and open:
			var out: Turnout.Exit = frontier.pop_back()
			var found := first_on_the_way(out)
			if found is RailSignal:
				protecting[found as RailSignal] = true
				met.append(str(found.name))
				continue
			var turnout := found as Turnout
			if turnout == null:
				case.fail("%s is signalled from %s, %s" % [junction, out.rail.name,
						"rising" if out.direction > 0 else "falling"],
						"walking out from %.1f m the end of %s comes before any signal" % [
						out.distance, out.rail.name])
				open = false
				continue
			var arriving := _leg_arrived_by(turnout, out)
			var onward: Array[Turnout.Leg] = [Turnout.Leg.TOE]
			if arriving == Turnout.Leg.TOE:
				onward = [Turnout.Leg.THROUGH, Turnout.Leg.DIVERGING]
			for leg in onward:
				var key := "%s:%d" % [turnout.get_path(), leg]
				if not seen.has(key):
					seen[key] = true
					frontier.append(turnout.leg_exit(leg))
		if open:
			case.note("%-28s <- %s" % [junction, ", ".join(met)])
			case.succeed("%s is signalled from every way back" % junction)
	return protecting


## The leg of [param turnout] a walk along [param out] comes in by: the one whose way
## out runs back along the same rail.
static func _leg_arrived_by(turnout: Turnout, out: Turnout.Exit) -> Turnout.Leg:
	for leg: Turnout.Leg in [Turnout.Leg.DIVERGING, Turnout.Leg.THROUGH, Turnout.Leg.TOE]:
		var back := turnout.leg_exit(leg)
		if back.rail == out.rail and back.direction == -out.direction:
			return leg
	return Turnout.Leg.TOE
