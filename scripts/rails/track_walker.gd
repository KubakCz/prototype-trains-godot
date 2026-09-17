class_name TrackWalker
extends RefCounted
## Measures arc length along the network rather than along a single [Rail].
##
## Everything a train does is expressed as "move this far from here": driving is
## moving the centre, and placing the body is moving out to each end. Doing that
## with plain arithmetic on [member Train.distance] stops at the rail's own ends,
## which is exactly what turnouts exist to get past - so it is done here instead,
## crossing every [Turnout] on the way that is set to allow it.
##
## Because it is the same walk in both cases, a train straddling the points has
## its two ends on two different rails and is drawn as the chord between them,
## and a train is refused by a turnout the moment its *leading end* touches the
## points rather than when its middle does.
##
## Step 8's block locking wants exactly this walk with the length turned up: look
## ahead from a train and report what it will reach.

## Distances closer together than this count as the same point on a rail. Also
## what stops a turnout the walk has just crossed from being found again
## immediately, so two turnouts on one rail have to be at least this far apart.
const EPSILON := 1e-3

## How far past the points a crossing always carries the walk.
##
## A rail distance exactly at a turnout does not say which side of the points the
## train is on - the main rail runs through them, so the same distance means both
## "about to arrive" and "just left". The walk therefore never comes to rest in
## that zone: it either stops more than [constant EPSILON] short of the points,
## or ends up at least this far past them. Costs a few millimetres of over-travel
## per crossing, and removes the whole class of bug where a train resuming from
## being held cannot see the points it is standing on.
const CLEARANCE := 4.0 * EPSILON

## A layout that sends the walk through more turnouts than this is looping.
const MAX_HOPS := 64


## Where a walk ended up, and why it stopped there.
class Step:
	var rail: Rail
	var distance: float
	## Travel direction on [member rail], towards increasing distance when +1.
	var direction: int
	## Arc length actually covered. Less than what was asked for when the walk
	## ran into something.
	var travelled: float
	## The turnout that refused passage, if one did. A train here has to wait for
	## it to be thrown.
	var blocking_turnout: Turnout
	## True when the walk ran off the end of a rail with nothing attached to it.
	var at_dead_end: bool

	func is_blocked() -> bool:
		return blocking_turnout != null or at_dead_end


	func describe() -> String:
		if blocking_turnout != null:
			return "held at %s" % blocking_turnout.name
		return "at end of %s" % rail.name if at_dead_end else "clear"


## Moves [param length] metres from [param distance] on [param rail], travelling
## towards increasing distance when [param direction] is positive, crossing any
## turnouts that admit the move.
static func walk(rail: Rail, distance: float, direction: int, length: float) -> Step:
	var step := Step.new()
	step.rail = rail
	step.direction = 1 if direction >= 0 else -1
	if rail == null:
		return step
	step.distance = rail.clamp_distance(distance)
	var remaining := maxf(length, 0.0)

	for _hop in MAX_HOPS:
		if remaining <= EPSILON:
			return step
		var ahead := _next_stop(step)
		var turnout := ahead.turnout
		var gap := absf(ahead.distance - step.distance)
		# `gap - EPSILON`, not `gap`: travel that would leave the walk resting a
		# hair short of the points crosses them instead. See CLEARANCE.
		if remaining < gap - EPSILON:
			step.distance += float(step.direction) * remaining
			step.travelled += remaining
			return step

		step.travelled += gap
		remaining -= gap
		step.distance = ahead.distance
		if turnout == null:
			step.at_dead_end = true
			return step
		var exit := turnout.traverse(step.rail, step.distance, step.direction)
		if exit == null:
			step.blocking_turnout = turnout
			return step
		step.rail = exit.rail
		step.distance = exit.rail.clamp_distance(exit.distance)
		step.direction = exit.direction
		remaining = maxf(remaining, CLEARANCE)

	push_warning(("TrackWalker gave up after %d turnouts. A rail layout is looping back "
			+ "into itself, or two turnouts sit at the same point on one rail.") % MAX_HOPS)
	return step


## The next thing on the current rail that the walk has to deal with.
class _Stop:
	var distance: float
	## The turnout there, or [code]null[/code] when this is the rail's own end.
	var turnout: Turnout


## The nearest turnout strictly ahead of [param step] on its current rail, and
## how far along it sits. Falls back to the rail's own end when there is none,
## which is where a walk runs out of track.
static func _next_stop(step: Step) -> _Stop:
	var stop := _Stop.new()
	stop.distance = step.rail.rail_length() if step.direction > 0 else 0.0
	for node in step.rail.attachments():
		var candidate := node as Turnout
		if candidate == null:
			continue
		for at in candidate.distances_on(step.rail):
			# Strictly ahead, so the turnout the walk has just come through is
			# not picked up again, and no closer than one already found.
			if step.direction > 0:
				if at > step.distance + EPSILON and at <= stop.distance:
					stop.distance = at
					stop.turnout = candidate
			elif at < step.distance - EPSILON and at >= stop.distance:
				stop.distance = at
				stop.turnout = candidate
	return stop
