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
## [RailSignal]s stop the walk too, but only when the caller asks for them - see
## [param signals_from] on [method walk]. A signal is a rule about trains, not
## about track, so the walks that measure where a train's body reaches ignore
## them entirely; only the walk that decides whether a train may move obeys them.
##
## A [Crossing] never stops the walk: both of its rails run straight through it,
## and only [Turnout]s and [RailSignal]s are ever looked for among a rail's
## attachments. Nor does a [CompoundTurnout] exist here - its members are
## ordinary turnouts, walked through one after another.
##
## Every walk records the stretches of rail it covered in [member Step.spans],
## and [method Step.locate] turns an arc length along the walk back into a place
## on a rail - which is how every car of a [Train] finds the track under its two
## ends. Step 9's block locking wants exactly this walk with the length turned
## up: look ahead from a train and report what it will reach.

## Distances closer together than this count as the same point on a rail. Also
## what stops a turnout the walk has just crossed from being found again
## immediately, so two turnouts on one rail have to be at least this far apart.
const EPSILON := 1e-3

## Passed as [param signals_from] by a walk that is measuring track rather than
## asking permission: no signal on it stops it, however it is set.
const IGNORE_SIGNALS := INF

## Passed as [param signals_from] by a walk that obeys every signal it reaches,
## including one standing exactly where the walk begins.
const OBEY_ALL_SIGNALS := 0.0

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


## One stretch of a single rail that a walk covered, from [member from] to
## [member to] in the order it was travelled - so [member from] is greater than
## [member to] when the walk ran against the rail.
class Span:
	var rail: Rail
	var from: float
	var to: float

	func _init(p_rail: Rail, p_from: float, p_to: float) -> void:
		rail = p_rail
		from = p_from
		to = p_to


	## Whether [param at] on [param query_rail] lies within this span, ends included.
	func covers(query_rail: Rail, at: float) -> bool:
		return (query_rail == rail and at >= minf(from, to) - EPSILON
				and at <= maxf(from, to) + EPSILON)


## A place on the network: a rail and a distance along it.
class Location:
	var rail: Rail
	var distance: float

	func _init(p_rail: Rail, p_distance: float) -> void:
		rail = p_rail
		distance = p_distance


	func position() -> Vector3:
		return rail.sample_position(distance)


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
	## The signal at danger the walk stopped at, if it stopped at one. A train
	## here has to wait for it to clear.
	var blocking_signal: RailSignal
	## True when the walk ran off the end of a rail with nothing attached to it.
	var at_dead_end: bool
	## Every stretch of rail covered on the way, in order - one per rail the walk
	## was on. What a train's body is standing on, when the walk is one of the two
	## that place it; see [method Train.occupied_spans].
	var spans: Array[Span] = []


	## Whether the walk passed over [param at] on [param query_rail].
	func covers(query_rail: Rail, at: float) -> bool:
		for span in spans:
			if span.covers(query_rail, at):
				return true
		return false


	## The place [param along] metres into the walk, following it across every
	## rail it changed to. Clamped to the walk's own two ends, so asking past
	## where a walk stopped answers with where it stopped.
	##
	## The spans join up exactly - a span ends at the points and the next starts
	## at the same spot on the other rail - so this is continuous along the walk,
	## and a car whose two ends are located this way is the chord between them.
	func locate(along: float) -> Location:
		var left := maxf(along, 0.0)
		for span in spans:
			var run := absf(span.to - span.from)
			if left <= run:
				return Location.new(span.rail, span.from + signf(span.to - span.from) * left)
			left -= run
		return Location.new(rail, distance)

	func is_blocked() -> bool:
		return blocking_turnout != null or blocking_signal != null or at_dead_end


	func describe() -> String:
		if blocking_turnout != null:
			return "held at %s" % blocking_turnout.name
		if blocking_signal != null:
			return "held at %s (danger)" % blocking_signal.name
		return "at end of %s" % rail.name if at_dead_end else "clear"


## Moves [param length] metres from [param distance] on [param rail], travelling
## towards increasing distance when [param direction] is positive, crossing any
## turnouts that admit the move.
##
## [param signals_from] is how far into the walk signals start to count, and
## defaults to [constant IGNORE_SIGNALS] - never. A train passes half its own
## length: a signal it has already drawn level with is one its nose has passed,
## and a signal only ever stops a train that has not reached it yet. The walks
## that place a train's body pass nothing at all, because where the body reaches
## is a question about track, not about permission.
##
## [param excused] are signals that do not stop this walk whatever they show: the
## ones a train found at danger too late to stop for, and is running past with its
## brakes full on. See [member Train.tripped].
static func walk(rail: Rail, distance: float, direction: int, length: float,
		signals_from := IGNORE_SIGNALS, excused: Array[RailSignal] = []) -> Step:
	var step := Step.new()
	step.rail = rail
	step.direction = 1 if direction >= 0 else -1
	if rail == null:
		return step
	step.distance = rail.clamp_distance(distance)
	var remaining := maxf(length, 0.0)
	var span := Span.new(step.rail, step.distance, step.distance)
	step.spans.append(span)

	for _hop in MAX_HOPS:
		if remaining <= EPSILON:
			return step
		var ahead := _next_stop(step, signals_from, excused)
		var turnout := ahead.turnout
		var gap := absf(ahead.distance - step.distance)
		# `gap - EPSILON`, not `gap`: travel that would leave the walk resting a
		# hair short of the points crosses them instead. See CLEARANCE.
		if remaining < gap - EPSILON:
			step.distance += float(step.direction) * remaining
			step.travelled += remaining
			span.to = step.distance
			return step

		step.travelled += gap
		remaining -= gap
		step.distance = ahead.distance
		span.to = step.distance
		if ahead.rail_signal != null:
			# A signal is never crossed: it either lets the walk through, in
			# which case it is not a stop at all, or it ends it here.
			step.blocking_signal = ahead.rail_signal
			return step
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
		span = Span.new(step.rail, step.distance, step.distance)
		step.spans.append(span)
		remaining = maxf(remaining, CLEARANCE)

	push_warning(("TrackWalker gave up after %d turnouts. A rail layout is looping back "
			+ "into itself, or two turnouts sit at the same point on one rail.") % MAX_HOPS)
	return step


## The next thing on the current rail that the walk has to deal with.
class _Stop:
	var distance: float
	## The turnout there, if it is one.
	var turnout: Turnout
	## The signal there, if it is one. Both null means the rail's own end.
	var rail_signal: RailSignal


## The nearest thing strictly ahead of [param step] on its current rail that the
## walk has to deal with, and how far along it sits. Falls back to the rail's own
## end when there is none, which is where a walk runs out of track.
##
## Turnouts are gathered first and signals second, so a signal standing exactly
## at a set of points wins the tie. Stopping short of points a train was going to
## be allowed through is harmless; being let through points a signal was holding
## it at is not.
static func _next_stop(step: Step, signals_from: float, excused: Array[RailSignal]) -> _Stop:
	var stop := _Stop.new()
	stop.distance = step.rail.rail_length() if step.direction > 0 else 0.0
	for node in step.rail.attachments():
		var turnout := node as Turnout
		if turnout == null:
			continue
		for at in turnout.distances_on(step.rail):
			if _is_ahead(step, at, stop.distance):
				stop.distance = at
				stop.turnout = turnout
	if is_inf(signals_from):
		return stop

	for node in step.rail.attachments():
		var rail_signal := node as RailSignal
		if rail_signal == null or not rail_signal.blocks(step.rail, step.direction):
			continue
		if excused.has(rail_signal):
			continue
		for at in rail_signal.distances_on(step.rail):
			if not _is_ahead(step, at, stop.distance):
				continue
			# A signal nearer than `signals_from` is one the caller has already
			# gone past - for a train, one its nose is beyond.
			if step.travelled + absf(at - step.distance) < signals_from - EPSILON:
				continue
			stop.distance = at
			stop.turnout = null
			stop.rail_signal = rail_signal
	return stop


## Whether [param at] is strictly ahead of the walk and no further than
## [param limit]. Strictly, so the turnout the walk has just come through is not
## picked up again the moment it is behind.
static func _is_ahead(step: Step, at: float, limit: float) -> bool:
	if step.direction > 0:
		return at > step.distance + EPSILON and at <= limit
	return at < step.distance - EPSILON and at >= limit
