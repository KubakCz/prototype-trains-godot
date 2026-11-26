@tool
class_name Train
extends Node3D
## A locomotive and the wagons behind it, driving the network under its own power
## and its own brakes.
##
## Direction is two values, never a signed speed: [member facing] is which way the nose
## points along the rail, [member throttle] whether it drives nose-first, stands or backs
## up; [member current_speed] is never negative. Every frame it looks ahead as far as it
## could need to stop - for a [RailSignal] at danger, the end of the line, or the next
## [Station] of its [member route] - and brakes for it; points set against it are run
## into. Each car is placed by [TrackWalker] walks out from the centre.
##
## The whole design - consist, braking, holding, tripping, derailment, selection - is in
## docs/trains.md; routes and dwelling are in docs/stations.md.

## Nose points towards increasing rail distance.
const ALONG_RAIL := 1
## Nose points towards decreasing rail distance.
const AGAINST_RAIL := -1

## Every train joins this group at runtime. Anything that needs to find trains -
## a [Crossing], another train looking for something to hit - looks here.
const GROUP := &"trains"

## Space between two cars of one train, in metres.
const COUPLING_GAP := CarType.COUPLING_GAP
## The share of the full brake a normal stop uses. Anything harder than this is
## the train stopping for something it found late.
const SERVICE_BRAKE := 0.6
## How far short of a signal at danger or the end of the line a train means to
## stop, in metres. Only a train that cannot stop that short uses the rest.
const STOP_SHORT := 3.0

## What to do at a genuine dead end: a rail end with no turnout attached, and so
## nowhere to be handed on to. Still a placeholder - real levels will end their
## track at buffer stops or at a connection off the level - but it keeps an
## unattended prototype running instead of parking every train.
enum EndBehavior {
	## Stop and drop the throttle.
	STOP,
	## Back up along the rail without turning around: the nose keeps pointing at
	## the end of the line.
	REVERSE,
	## Turn the train around and keep driving nose-first. With wagons that puts
	## the locomotive at the other end - a placeholder's teleport.
	TURN_AROUND,
}

## What the train is doing, and so what colour its front marker shows. Worked out
## every frame from the physics, never set directly.
enum State {
	## Under power, or running at speed. Green.
	DRIVING,
	## Braking for a signal at danger or the end of the line, at whatever rate it
	## takes. Points set against it are not braked for: it runs into them. Red.
	BRAKING,
	## Standing short of one of those, or against points set against it that it
	## reached at a crawl, throttle still open: it goes by itself once the way
	## clears. Red.
	HELD,
	## Braking because its throttle was cut, or reversed. Blinking yellow.
	STOPPING,
	## Standing with its throttle cut. Yellow.
	STOPPED,
	## Found a stop too late to make it even at 100%: full brakes, and waiting for
	## [method release] once it stands. Blinking red.
	TRIPPED,
	## Off the rails, for good. Black.
	DERAILED,
	## Standing at a station, for as long as the stop lasts. Cyan.
	DWELLING,
}

## Speeds below this, in m/s, are standing still.
const _STANDING := 1e-3
## Within this of an obstruction, a train is up against it.
const _HELD_GAP := 0.01
## Arriving at points or a buffer slower than this counts as stopping against it,
## rather than running into it. Also the slack in deciding a stop is still makeable.
const _CRASH_SPEED := 0.5
## How much further than its stopping distance a train looks ahead.
const _LOOK_MARGIN := 2.0
## Points closer than this to either end of the train are not under it. A train
## held at points stands with its leading end exactly on them, and throwing them is
## how the player lets it through - that must not count as throwing them under it.
const _UNDER_MARGIN := 0.05
## How far ahead a rolling start looks for a signal or dead end to come in under, in
## metres.
const _ROLL_LOOK := 600.0

const _COLOR_GREEN := Color(0.2, 0.95, 0.3)
const _COLOR_RED := Color(0.95, 0.12, 0.1)
const _COLOR_YELLOW := Color(1.0, 0.82, 0.1)
const _COLOR_BLACK := Color(0.02, 0.02, 0.02)
const _COLOR_CYAN := Color(0.2, 0.85, 1.0)
## A freight load changes in steps this big while a train dwells, so the wagons are
## rebuilt a handful of times and not every frame.
const _LOAD_STEP := 0.1

## Emitted once, when the train derails, with why.
signal derailment(reason: String)
## Emitted when the train comes to a stop at a station of its route, which is the
## moment that stop counts as reached.
signal reached(point: InterestPoint)
## Emitted when the train has left the level by its destination, just before it is
## taken off. [param completed] is whether it went through every stop of its route.
signal route_finished(completed: bool)

@export var rail: Rail: set = _set_rail
## Distance of the middle of the whole train along [member rail], in metres. The
## middle rather than the nose, so that a train held with its nose on a set of
## points never has its own position in the ambiguous zone at them - see
## [constant TrackWalker.CLEARANCE].
@export var distance := 0.0: set = _set_distance
@export_enum("Along rail:1", "Against rail:-1") var facing := ALONG_RAIL: set = _set_facing
## -1 backs up, 0 stops, 1 drives nose-first. What the train is told to do: how
## fast it is actually going is [member current_speed].
@export_range(-1, 1, 1) var throttle := 1
## Top speed, in metres per second.
@export_range(0.5, 60.0, 0.5, "suffix:m/s") var max_speed := 12.0
@export var end_behavior := EndBehavior.TURN_AROUND

@export_group("Route")
## Where the train is going, in order, the last an [OutsideConnection]. Empty for a
## train that just drives.
@export var route: Array[InterestPoint] = []: set = _set_route
## How the engine is painted. Null leaves it the same blue as the wagons.
@export var livery: Livery: set = _set_livery

@export_group("Consist")
## Leads the train, with the nose and the front marker. A train without one is
## drawn with a stand-in, and warned about.
@export var locomotive: LocomotiveType: set = _set_locomotive
## Behind the locomotive, nearest first. Empty slots are skipped.
@export var wagons: Array[WagonType] = []: set = _set_wagons
## How full the wagons that carry anything are, from empty to full. Everything it
## carries is weight without brakes.
@export_range(0.0, 1.0, 0.05) var load_factor := 0.0: set = _set_load_factor

## Metres per second in the direction the train is moving. Never negative: which
## way that is - nose-first or backing - only changes at a standstill.
var current_speed := 0.0
## Found a stop too late to make it even at 100%, and braking at 100% because of
## it. Stays set after the train stands, until [method release].
var tripped := false
## Off the rails. Final: nothing clears it.
var derailed := false
## Why it derailed, for the readouts.
var derail_reason := ""
## Points the train is standing at, set against it, throttle open. It goes as soon
## as they are thrown.
var blocking_turnout: Turnout
## The signal at danger the train is standing at, throttle open. It goes as soon
## as it clears.
var blocking_signal: RailSignal
## Whether the train is standing against a dead end.
var at_dead_end := false
## How many stops of [member route] it has reached, so the index of the next one.
var route_index := 0: set = _set_route_index
## The station the train is standing at, while it dwells there.
var dwelling_at: Station
## Set when the train leaves by its destination: whether it went through every stop.
var completed := false
## Counts the trains that have come on to the level, in the order they did. What the
## route list sorts by.
var arrival_index := 0
## What the front marker shows. See [enum State].
var state := State.DRIVING
## The deceleration applied this frame, in m/s². Zero when not braking.
var braking := 0.0
## How far ahead of the leading end the nearest obstruction is, in metres, or INF
## when there is none within stopping distance.
var obstruction_gap := INF
## How far ahead of the leading end the train means to stop: [constant STOP_SHORT]
## short of a signal at danger or the end of the line, or INF when it means to
## keep going - points set against it included.
var stop_gap := INF

static var _selected: Train
static var _arrivals := 0
## Draw the selected train's stopping distance on the track. A debug panel row.
static var show_stopping_strip := true
## Draw every car's collision box. A debug panel row.
static var show_collision_boxes := false

## +1 while moving nose-first, -1 while backing. Follows the throttle, but only
## changes at a standstill: a train told to reverse at speed brakes first.
var _motion := 1
var _cars: Array[TrainCar] = []
## How far behind the nose each car's front end is.
var _car_offsets := PackedFloat64Array()
var _length := 0.0
var _mass := 0.0
var _brake_force := 0.0
var _traction := 0.0
## The materials every car shares. Made once the train is in the tree.
var _paint: TrainPaint
var _bound_types: Array[CarType] = []
## Signals at danger this train found too late and is running past. Forgotten once
## it is past them, or standing and released.
var _excused: Array[RailSignal] = []
## The last look ahead, for the readouts and the stopping strip.
var _ahead: TrackWalker.Step
var _braking_for_obstruction := false
## Every set of points under the body, and how it was set when it went under. A
## change is points thrown under the train. Untyped keys, because a level that
## frees a turnout leaves a freed object here until the next refresh.
var _points_under: Dictionary = {}
var _points_dirty := true
## The two walks out from the centre, to the nose and to the tail, that the train was
## last placed with. Kept, because a [Crossing] asks every train where its body is
## every frame, and so does the check for points thrown under it. Runtime only: in
## the editor the rails can move under a standing train.
var _front: TrackWalker.Step
var _rear: TrackWalker.Step
var _strip: StoppingStrip
var _icons: RouteIcons
var _dwell_left := 0.0
var _dwell_total := 0.0
var _load_before := 0.0
var _pending_click := false
var _click_at := Vector2.ZERO
## Set while a new position is written field by field, so the body is placed once
## at the end instead of after each of the three setters.
var _suspend_placement := false


func _ready() -> void:
	_motion = signi(throttle) if throttle != 0 else 1
	_rebuild_cars()
	_place_on_rail()
	var running := not Engine.is_editor_hint()
	if running:
		_arrivals += 1
		arrival_index = _arrivals
		_icons = RouteIcons.new()
		_icons.name = "RouteIcons"
		add_child(_icons, false, Node.INTERNAL_MODE_BACK)
		_icons.follow(self)
		add_to_group(GROUP)
		# Same as [Turnout] and [RailSignal]: without this a car never sees a click.
		get_viewport().physics_object_picking = true
	# In the editor the train is a preview: it follows inspector edits, but does
	# not drive off on its own.
	set_physics_process(running)
	set_process(running)
	set_process_unhandled_input(running)


func _exit_tree() -> void:
	if _selected == self:
		_selected = null


func _physics_process(delta: float) -> void:
	_take_pending_click()
	if not derailed and rail != null and rail.rail_length() > 0.0:
		_tick(delta)
	_update_state()
	_refresh_strip()


## One frame on the rails. Whatever derails the train ends the frame there.
func _tick(delta: float) -> void:
	_check_points_under()
	if derailed:
		return
	_drive(delta)
	if derailed:
		return
	_check_route_end()
	if derailed or is_queued_for_deletion():
		return
	if _points_dirty:
		_points_under = _find_points_under()
		_points_dirty = false
	_check_collisions()


func _process(_delta: float) -> void:
	_paint_marker()
	for car in _cars:
		car.show_box(show_collision_boxes)


#region Driving
## One frame: look ahead, choose a rate, move, and see what the train is up against.
##
## Two walks: one from the centre out past the leading end, as far as the stopping
## distance, to find what the train is about to run into and so how hard to brake
## and where it has to stop; and one to move the centre.
##
## The look-ahead obeys signals from half a train on - from the leading end
## outwards. A signal nearer than that is one the leading end has already passed,
## and a signal only stops a train that has yet to reach it.
func _drive(delta: float) -> void:
	_clear_holds()
	braking = 0.0
	_braking_for_obstruction = false
	if _dwell_left > 0.0:
		_dwell(delta)
		return
	if current_speed <= _STANDING:
		_stand()
	# Decided before the look ahead, which may trip the train.
	var driving := throttle != 0 and signi(throttle) == _motion and not tripped
	var direction := _motion * facing
	var half := half_length()
	if not _excused.is_empty():
		_forget_passed_signals(direction, half)

	var station := _choose_stop(direction, half, delta)
	var ahead := _ahead
	var limit := obstruction_gap
	var gap := stop_gap
	var rate := _braking_rate(gap, driving)
	braking = rate
	var was := current_speed
	var travel := _integrate(rate, gap, driving, delta)

	# A tripped train is past caring where it meant to stop: only the obstruction
	# itself stops it.
	var stop := limit if tripped else minf(gap, limit)
	if not is_inf(stop) and travel >= stop - _HELD_GAP:
		var arrival := sqrt(maxf(was * was - 2.0 * rate * stop, 0.0))
		if ahead.blocking_signal == null and stop == limit and arrival > _CRASH_SPEED:
			_move(direction, stop)
			derail(_run_into(ahead, arrival))
			return
		travel = stop
		current_speed = 0.0
	if travel > 0.0:
		_move(direction, travel)
	_come_to_rest(ahead, station, stop, travel)


## Standing still: the speed is exactly zero, and, unless it is tripped, the train
## takes the way its throttle points.
func _stand() -> void:
	current_speed = 0.0
	if not tripped:
		# Standing and not running away from anything: a signal it was excused
		# applies again, which matters only if it never got past it.
		_excused.clear()
		if throttle != 0:
			_motion = signi(throttle)


## Looks ahead and decides where the train means to stop, into [member _ahead],
## [member obstruction_gap] and [member stop_gap]. Trips the train for a stop it
## cannot make. Returns the station it is stopping at, or null.
func _choose_stop(direction: int, half: float, delta: float) -> Station:
	var full := full_brake_rate()
	var ahead := _look_ahead(direction, half, delta)
	var limit := _gap_to(ahead, half)
	# A signal at danger the train cannot stop for even at 100% is run past. It is
	# excused, and the train looks again for whatever lies beyond it.
	while ahead.blocking_signal != null and not _can_stop_within(limit, full):
		_excused.append(ahead.blocking_signal)
		tripped = true
		ahead = _look_ahead(direction, half, delta)
		limit = _gap_to(ahead, half)
	# The end of the line: it is going to reach it.
	if ahead.at_dead_end and not _can_stop_within(limit, full):
		tripped = true
	# Where it means to stop. Points set against it are not stopped for - it runs
	# into them, and only a crawl there holds rather than derails it.
	var gap := INF
	if ahead.blocking_signal != null or ahead.at_dead_end:
		gap = maxf(limit - STOP_SHORT, 0.0)
		if not _can_stop_within(gap, full):
			gap = limit
	# The next stop on the route, if it is a station, is stopped at - a signal at clear
	# does not matter - whenever it comes before anything else the train would stop
	# for. A train that is too fast for the brakes to make it simply passes it.
	var station: Station = null
	if not tripped:
		var station_gap := _station_gap(ahead)
		if station_gap < gap and _can_stop_within(station_gap, full):
			gap = station_gap
			station = next_station()
	_ahead = ahead
	obstruction_gap = limit
	stop_gap = gap
	return station


## How hard to brake this frame, to stop [param gap] ahead.
func _braking_rate(gap: float, driving: bool) -> float:
	var full := full_brake_rate()
	var service := service_brake_rate()
	var rate := 0.0
	if tripped:
		rate = full
	else:
		if not is_inf(gap) and current_speed > 0.0:
			# The rate that stops it exactly where it means to. Below the service
			# rate there is no need to brake yet. A hair below counts: riding the
			# service curve lands on it to within rounding, and a frame spent
			# coasting there has to be made up by braking harder than normal.
			var needed := current_speed * current_speed / (2.0 * maxf(gap, 1e-6))
			if needed >= service * (1.0 - 1e-6):
				rate = minf(needed, full)
				_braking_for_obstruction = true
		if not driving and current_speed > 0.0 and rate < service:
			# Throttle cut, or reversed at speed: a normal stop first.
			rate = service
	return rate


## Sets the speed at the end of the frame and returns how far the train goes in it.
## Integrated as constant acceleration over the frame, so a train braking at exactly
## the rate it needs lands exactly where it means to stop.
func _integrate(rate: float, gap: float, driving: bool, delta: float) -> float:
	var service := service_brake_rate()
	var was := current_speed
	var travel := 0.0
	if rate > 0.0:
		current_speed = was - rate * delta
		if current_speed <= 0.0:
			current_speed = 0.0
			travel = was * was / (2.0 * rate)
		else:
			travel = (was + current_speed) * 0.5 * delta
	elif driving:
		var target := max_speed
		if not is_inf(gap):
			# Never faster than it could still stop from at the service rate - from
			# where this frame leaves it, or it meets the curve going a little over.
			target = minf(target, sqrt(2.0 * service * maxf(gap - was * delta, 0.0)))
		if was > target:
			current_speed = maxf(was - service * delta, target)
		else:
			current_speed = minf(was + acceleration_rate() * delta, target)
		travel = (was + current_speed) * 0.5 * delta
	return travel


## Having moved [param travel] towards a stop [param stop] ahead: a train standing on
## its station's mark arrives there, and one standing at whatever it stopped for is
## held by it.
func _come_to_rest(ahead: TrackWalker.Step, station: Station, stop: float,
		travel: float) -> void:
	if station != null and current_speed == 0.0 and stop - travel <= _HELD_GAP:
		_arrive_at(station)
		return
	if (current_speed == 0.0 and throttle != 0 and not is_inf(stop)
			and stop - travel <= _HELD_GAP):
		blocking_turnout = ahead.blocking_turnout
		blocking_signal = ahead.blocking_signal
		at_dead_end = ahead.at_dead_end
		# Points set against the train, or a signal at danger: hold, throttle
		# still open, and go the moment the player changes it. Only a dead end
		# falls back to `end_behavior`.
		if at_dead_end and not tripped:
			_handle_end_of_rail()


## Lets go of whatever the train was standing at.
func _clear_holds() -> void:
	blocking_turnout = null
	blocking_signal = null
	at_dead_end = false


## From the centre, out past the leading end as far as the train could need to
## stop at the service rate, obeying every signal from the leading end on except
## the ones it has been excused.
func _look_ahead(direction: int, half: float, delta: float) -> TrackWalker.Step:
	var reach := (current_speed * delta + stopping_distance(current_speed, service_brake_rate())
			+ STOP_SHORT + _LOOK_MARGIN)
	return TrackWalker.walk(rail, distance, direction, half + reach, half, _excused)


func _gap_to(ahead: TrackWalker.Step, half: float) -> float:
	return maxf(ahead.travelled - half, 0.0) if ahead.is_blocked() else INF


## Whether braking at [param rate] stops the train within [param gap] - or near
## enough, arriving no faster than [constant _CRASH_SPEED].
func _can_stop_within(gap: float, rate: float) -> bool:
	if is_inf(gap) or current_speed <= _STANDING:
		return true
	var arrival_squared := current_speed * current_speed - 2.0 * rate * gap
	return arrival_squared <= _CRASH_SPEED * _CRASH_SPEED


## Drops the excused signals the train is now past: anywhere under its body, short
## of its leading end.
func _forget_passed_signals(direction: int, half: float) -> void:
	var lead := TrackWalker.walk(rail, distance, direction, maxf(half - 0.05, 0.0))
	var trail := TrackWalker.walk(rail, distance, -direction, half)
	for rail_signal: RailSignal in _excused.duplicate():
		var at := rail_signal.signal_distance()
		if lead.covers(rail_signal.rail, at) or trail.covers(rail_signal.rail, at):
			_excused.erase(rail_signal)


func _move(direction: int, travel: float) -> void:
	var moved := TrackWalker.walk(rail, distance, direction, travel)
	# The rail underneath may have changed. The nose has not turned round, so
	# `facing` becomes whichever direction on the new rail still points that way.
	_apply_state(moved.rail, moved.distance, moved.direction * _motion)


## Nothing is attached to this rail end, so there is nowhere to be handed on to.
func _handle_end_of_rail() -> void:
	match end_behavior:
		EndBehavior.STOP:
			throttle = 0
		EndBehavior.REVERSE:
			throttle = -throttle
		EndBehavior.TURN_AROUND:
			facing = -facing


## Sets the train moving at [param speed] straight away, the way its throttle
## says - a rolling start, for a train that arrives rather than starts. Capped at
## [member max_speed]; nothing at all for a derailed train or a closed throttle.
func roll(speed: float) -> void:
	if derailed or throttle == 0:
		return
	_motion = signi(throttle)
	current_speed = clampf(speed, 0.0, max_speed)


## A rolling start that the train can still stop from: [param speed], less if the first
## red signal or dead end ahead is too near to stop for at the service rate at that
## speed. For a train that arrives, so it never comes in too fast for the signal that
## is waiting for it.
func roll_safely(speed: float) -> void:
	if derailed or throttle == 0:
		return
	var cap := speed
	var half := half_length()
	var ahead := TrackWalker.walk(rail, distance, signi(throttle) * facing, _ROLL_LOOK + half, half)
	if ahead.blocking_signal != null or ahead.at_dead_end:
		var gap := maxf(ahead.travelled - half - STOP_SHORT, 0.0)
		cap = minf(cap, sqrt(2.0 * service_brake_rate() * gap))
	roll(cap)


## Lets a tripped train go: the brakes come off and it drives on, past the signal
## it overran if it has not reached it yet. "At any point" - while still braking,
## or standing. Nothing for a train that is not tripped, or a derailed one.
func release() -> void:
	if derailed or not tripped:
		return
	tripped = false
	if throttle == 0:
		throttle = 1
#endregion


#region Physics figures
## Nose to tail, couplings included, in metres.
func train_length() -> float:
	return _length


func half_length() -> float:
	return _length * 0.5


## Locomotive first, then the wagons in order.
func cars() -> Array[TrainCar]:
	return _cars


## Every car's empty weight plus whatever the wagons carry, in tonnes.
func total_mass() -> float:
	return _mass


## Tonnes carried, out of [method total_mass].
func carried_mass() -> float:
	var carried := 0.0
	for type in _car_types():
		carried += _carried(type)
	return carried


## Traction over the whole train's mass, in m/s².
func acceleration_rate() -> float:
	return _traction / _mass if _mass > 0.0 else 0.0


## Deceleration at 100% brake, in m/s²: every car's brakes over the whole mass.
func full_brake_rate() -> float:
	return _brake_force / _mass if _mass > 0.0 else 0.0


## Deceleration of a normal stop, in m/s².
func service_brake_rate() -> float:
	return full_brake_rate() * SERVICE_BRAKE


## Metres it takes to stop from [param speed] braking at [param rate].
static func stopping_distance(speed: float, rate: float) -> float:
	if speed <= 0.0:
		return 0.0
	return speed * speed / (2.0 * rate) if rate > 0.0 else INF


## Where the nose is.
func nose() -> TrackWalker.Step:
	return TrackWalker.walk(rail, distance, facing, half_length())


## +1 while moving (or about to move) nose-first, -1 while backing.
func moving_direction() -> int:
	return _motion
#endregion


#region Derailment
## Takes the train off the rails, for good: it stops dead where it is, every car is
## knocked askew and greyed, and the front marker goes black. Points thrown under
## it, another train touching it, and running into points or a buffer too late all
## end here.
func derail(reason: String) -> void:
	if derailed:
		return
	derailed = true
	derail_reason = reason
	current_speed = 0.0
	braking = 0.0
	tripped = false
	_clear_holds()
	dwelling_at = null
	_dwell_left = 0.0
	_excused.clear()
	# Knocked askew from exactly where each car stands, rather than placed again:
	# with points just thrown under it, walking the train out again would put half
	# of the wreck on the other route.
	for i in _cars.size():
		_cars[i].global_transform = _cars[i].global_transform * _wreck_pose(i)
		_cars[i].place_bogies_under_body()
	_refresh_look()
	_update_state()
	derailment.emit(reason)


## Every set of points that lies under the body, more than [constant _UNDER_MARGIN]
## inside both ends, with the way each is set.
func _find_points_under() -> Dictionary:
	var found := {}
	var reach := half_length() - _UNDER_MARGIN
	if reach <= 0.0:
		return found
	for walk in _body_walks():
		var along := 0.0
		for span in walk.spans:
			for node in span.rail.attachments():
				var turnout := node as Turnout
				if turnout == null:
					continue
				for at in turnout.distances_on(span.rail):
					if span.covers(span.rail, at) and along + absf(at - span.from) < reach:
						found[turnout] = turnout.turnout_position
			along += absf(span.to - span.from)
	return found


## Points thrown since the last frame, with the train over them, derail it.
func _check_points_under() -> void:
	for key: Variant in _points_under:
		if not is_instance_valid(key):
			continue
		var turnout := key as Turnout
		if turnout.turnout_position != int(_points_under[key]):
			derail("%s thrown under it" % _turnout_label(turnout))
			return


## Any car of this train touching any car of another derails both. Trains further
## apart than their two half-lengths cannot touch, which keeps this cheap.
func _check_collisions() -> void:
	for node in get_tree().get_nodes_in_group(GROUP):
		var other := node as Train
		if other == null or other == self or other.rail == null:
			continue
		var reach := half_length() + other.half_length() + 4.0
		if global_position.distance_squared_to(other.global_position) > reach * reach:
			continue
		for car in _cars:
			for other_car in other.cars():
				if car.touches(other_car):
					derail("collided with %s" % other.name)
					other.derail("collided with %s" % name)
					return


func _run_into(ahead: TrackWalker.Step, speed: float) -> String:
	if ahead.blocking_turnout != null:
		return "ran into %s at %.0f m/s" % [_turnout_label(ahead.blocking_turnout), speed]
	return "ran off the end of %s at %.0f m/s" % [ahead.rail.name, speed]


static func _turnout_label(turnout: Turnout) -> String:
	if turnout.assembly != null:
		return "%s/%s" % [turnout.assembly.name, turnout.name]
	return str(turnout.name)


## How each car of a wreck lies: twisted and rolled a few degrees, alternately one
## way and the other down the train. Fixed rather than random, so a test can rely on
## a wreck staying where it is.
static func _wreck_pose(index: int) -> Transform3D:
	var side := 1.0 if index % 2 == 0 else -1.0
	var yaw := deg_to_rad(side * (3.0 + 1.5 * float(index % 3)))
	var tilt := deg_to_rad(-side * (6.0 + 3.0 * float(index % 2)))
	return Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, tilt),
			Vector3(side * 0.3, 0.0, 0.0))
#endregion


#region Route
## The point the train is going to next, or null once the route is done (or with none).
func next_stop() -> InterestPoint:
	return route[route_index] if route_index < route.size() else null


## The next stop, if it is a station: the one the train brakes for.
func next_station() -> Station:
	return next_stop() as Station


## Where the train leaves the level: the last stop, if it is an [OutsideConnection].
func destination() -> OutsideConnection:
	return route.back() as OutsideConnection if not route.is_empty() else null


## The row of shapes floating over the train, once it is running.
func route_icons() -> RouteIcons:
	return _icons


## The stops of the route still to come, nearest first.
func remaining_stops() -> Array[InterestPoint]:
	var left: Array[InterestPoint] = []
	for i in range(route_index, route.size()):
		left.append(route[i])
	return left


## How far the train has to go to stand with its leading end on the next station's
## stop mark for the way it is going ([method InterestTrack.stop_distance]), or INF when
## the next stop is not a station or no stop mark is on what the train looks at ahead.
## The walk starts at the middle, so half the train comes off: what is left is how far
## the middle moves, the same measure as the gap to a signal.
func _station_gap(ahead: TrackWalker.Step) -> float:
	var station := next_station()
	if station == null:
		return INF
	var half := half_length()
	var best := INF
	for track in station.tracks():
		var along := 0.0
		for span in ahead.spans:
			var run := span.to - span.from
			if absf(run) > 0.0:
				var stop := track.stop_distance(signi(run))
				if span.covers(track.rail, stop):
					var gap := along + absf(stop - span.from) - half
					# Already past it by more than a hair: the nose is beyond the stop.
					if gap >= -_HELD_GAP:
						best = minf(best, maxf(gap, 0.0))
			along += absf(run)
	return best


## Stood on a station's stop mark: the stop counts as reached, and the dwell begins.
func _arrive_at(station: Station) -> void:
	route_index += 1
	dwell_at(station)
	reached.emit(station)


## Starts standing at [param station] for its dwell time, as a train that has just come
## to a stop on its mark does. Also how a train is put down at a station when the level
## starts. Leaves the route alone.
func dwell_at(station: Station) -> void:
	current_speed = 0.0
	dwelling_at = station
	_dwell_left = station.dwell_time
	_dwell_total = station.dwell_time
	_load_before = load_factor
	if _dwell_left <= 0.0:
		_apply_cargo(1.0)
		dwelling_at = null


func _dwell(delta: float) -> void:
	current_speed = 0.0
	_dwell_left = maxf(_dwell_left - delta, 0.0)
	_apply_cargo(1.0 - _dwell_left / _dwell_total if _dwell_total > 0.0 else 1.0)
	if _dwell_left <= 0.0:
		dwelling_at = null


## What the station does to the freight, [param progress] of the way through the stop.
func _apply_cargo(progress: float) -> void:
	if dwelling_at == null or dwelling_at.cargo == Station.Cargo.NONE or not _carries_freight():
		return
	var target := 1.0 if dwelling_at.cargo == Station.Cargo.LOAD else 0.0
	var now := target
	if progress < 1.0:
		now = snappedf(lerpf(_load_before, target, progress), _LOAD_STEP)
	if not is_equal_approx(now, load_factor):
		load_factor = now


func _carries_freight() -> bool:
	for wagon in wagons:
		if wagon != null and wagon.capacity > 0.0:
			return true
	return false


## A train with both ends out past the mark of its destination has left the level.
func _check_route_end() -> void:
	var out := destination()
	if out == null or _front == null or Engine.is_editor_hint() or is_queued_for_deletion():
		return
	var half := half_length()
	if out.has_left(_front.locate(half), _rear.locate(half), at_dead_end):
		completed = route_index >= route.size() - 1
		route_finished.emit(completed)
		queue_free()


func _set_route(value: Array[InterestPoint]) -> void:
	route = value
	route_index = 0
	update_configuration_warnings()


func _set_route_index(value: int) -> void:
	route_index = value
	if _icons != null:
		_icons.refresh()
#endregion


#region Selection
## Makes this the selected train, and no other.
func select() -> void:
	var previous := selected_train()
	if previous == self:
		return
	_selected = self
	if previous != null:
		previous._refresh_look()
	_refresh_look()


static func selected_train() -> Train:
	if _selected != null and not is_instance_valid(_selected):
		_selected = null
	return _selected


static func clear_selection() -> void:
	var previous := selected_train()
	_selected = null
	if previous != null:
		previous._refresh_look()


func is_selected() -> bool:
	return selected_train() == self


## A click that reaches unhandled input is one no widget or panel took. Only the
## selected train listens, and it decides on the next physics frame - where the
## space can be asked - whether the click landed on anything clickable at all.
func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and is_selected() and event.is_action_pressed(&"interact"):
		_pending_click = true
		_click_at = button.position


## A click on nothing clears the selection. A click on anything pickable - a car,
## a signal, a set of points - is that thing's own business, so it is left alone.
func _take_pending_click() -> void:
	if not _pending_click:
		return
	_pending_click = false
	var camera := get_viewport().get_camera_3d()
	if camera == null or not is_selected():
		return
	var from := camera.project_ray_origin(_click_at)
	var query := PhysicsRayQueryParameters3D.create(from,
			from + camera.project_ray_normal(_click_at) * camera.far)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var collider: Variant = hit.get("collider")
	if not (collider is CollisionObject3D and (collider as CollisionObject3D).input_ray_pickable):
		clear_selection()
#endregion


#region State and look
func _update_state() -> void:
	if derailed:
		state = State.DERAILED
	elif tripped:
		state = State.TRIPPED
	elif dwelling_at != null:
		state = State.DWELLING
	elif _braking_for_obstruction:
		state = State.BRAKING
	elif blocking_turnout != null or blocking_signal != null or at_dead_end:
		state = State.HELD
	elif braking > 0.0:
		state = State.STOPPING
	elif throttle == 0 and current_speed == 0.0:
		state = State.STOPPED
	else:
		state = State.DRIVING


## The colour the front marker shows in [param of], before any blinking.
static func state_color(of: State) -> Color:
	match of:
		State.BRAKING, State.HELD, State.TRIPPED:
			return _COLOR_RED
		State.STOPPING, State.STOPPED:
			return _COLOR_YELLOW
		State.DERAILED:
			return _COLOR_BLACK
		State.DWELLING:
			return _COLOR_CYAN
		_:
			return _COLOR_GREEN


## Whether the marker blinks in [param of].
static func state_blinks(of: State) -> bool:
	return of == State.STOPPING or of == State.TRIPPED


func state_name() -> String:
	return State.keys()[state]


func _paint_marker() -> void:
	if _paint != null:
		_paint.paint_marker(state_color(state), state_blinks(state), state == State.DERAILED)


func _refresh_look() -> void:
	if _paint == null:
		return
	_paint.refresh(livery, is_selected(), derailed)
	_paint_marker()


## What the locomotive is painted: its livery, or the same as the wagons without one.
func engine_color() -> Color:
	if livery != null and _paint != null:
		return _paint.engine.albedo_color
	return body_color()


## What every car's body is painted: blue, lighter while selected, grey once wrecked.
func body_color() -> Color:
	return _paint.body.albedo_color if _paint != null else TrainPaint.BODY_COLOR


## What is holding or stopping the train, for the readouts.
func blocked_description() -> String:
	if derailed:
		return "derailed: %s" % derail_reason
	if dwelling_at != null:
		return "at %s, %.1f s more" % [dwelling_at.label(), _dwell_left]
	if blocking_signal != null:
		return "held at %s" % _obstruction_text(blocking_signal, null, "")
	if blocking_turnout != null:
		return "held by %s" % _obstruction_text(null, blocking_turnout,
				str(Turnout.Position.keys()[blocking_turnout.turnout_position]))
	if at_dead_end:
		return "at dead end"
	if tripped:
		return "tripped, waiting to be let go"
	return ""


## What the train is braking for or will stop at, and how far off, for the
## readouts. Empty when nothing is within stopping distance.
func ahead_description() -> String:
	if _ahead == null or is_inf(obstruction_gap) or not _ahead.is_blocked():
		return ""
	var what := ""
	if _ahead.blocking_signal != null or _ahead.blocking_turnout != null:
		what = _obstruction_text(_ahead.blocking_signal, _ahead.blocking_turnout, "against")
	else:
		what = "end of %s" % _ahead.rail.name
	return "%s in %.1f m" % [what, obstruction_gap]


## A signal at danger, or else points [param setting], as the readouts name them. A
## member of a compound turnout is named through its assembly, since the assembly is
## the thing the player has to change.
static func _obstruction_text(rail_signal: RailSignal, turnout: Turnout,
		setting: String) -> String:
	if rail_signal != null:
		return "%s (danger)" % rail_signal.name
	return "%s (set %s)" % [_turnout_label(turnout), setting]
#endregion


#region Stopping strip
## How far ahead of the leading end the train would come to rest: at whatever it is
## braking for, else at the rate it is braking at, else at the service rate.
func stopping_reach() -> float:
	if current_speed <= 0.0:
		return 0.0
	if _braking_for_obstruction and not is_inf(stop_gap):
		return stop_gap
	var rate := full_brake_rate() if tripped else service_brake_rate()
	return stopping_distance(current_speed, maxf(rate, braking))


## The selected train's stopping distance, drawn on the track from its leading end.
func _refresh_strip() -> void:
	var shown := show_stopping_strip and is_selected() and not derailed and rail != null
	var reach := stopping_reach() if shown else 0.0
	if reach <= 0.05:
		if _strip != null:
			_strip.visible = false
		return
	if _strip == null:
		_strip = StoppingStrip.new()
		add_child(_strip, false, Node.INTERNAL_MODE_BACK)
	_strip.draw(rail, distance, _motion * facing, half_length(), reach, state_color(state))
#endregion


#region Placement
## Every stretch of rail the train is standing on, nose half and tail half. A
## train crossing points stands on two rails at once, so this is the question to
## ask rather than comparing [member distance] - it is how a [Crossing] knows who
## is on it, and the start of what step 9's block occupancy needs.
func occupied_spans() -> Array[TrackWalker.Span]:
	var spans: Array[TrackWalker.Span] = []
	if rail == null or rail.rail_length() <= 0.0:
		return spans
	for walk in _body_walks():
		spans.append_array(walk.spans)
	return spans


## From the centre to the nose and from the centre to the tail: the walks the train
## was placed with when it has them, else walked now.
func _body_walks() -> Array[TrackWalker.Step]:
	if _front != null and not Engine.is_editor_hint():
		return [_front, _rear]
	var half := half_length()
	return [TrackWalker.walk(rail, distance, facing, half),
			TrackWalker.walk(rail, distance, -facing, half)]


## Whether any part of the train stands over [param at] on [param query_rail].
func occupies(query_rail: Rail, at: float) -> bool:
	for span in occupied_spans():
		if span.covers(query_rail, at):
			return true
	return false


## Puts the train node on the rail at its centre, and every car on the chord
## between the rail positions under its own two ends.
##
## The ends are found by walking rather than by adding to [member distance], so a
## train halfway through a turnout has cars on both rails, and a car straddling
## the points is drawn as the chord across them. One walk each way from the centre
## covers the whole train; [method TrackWalker.Step.locate] finds every end on it.
func _place_on_rail() -> void:
	if _suspend_placement or rail == null or not rail.is_inside_tree() or not is_inside_tree():
		return
	if rail.rail_length() <= 0.0:
		return
	var half := half_length()
	var front := TrackWalker.walk(rail, distance, facing, half)
	var rear := TrackWalker.walk(rail, distance, -facing, half)
	_front = front
	_rear = rear
	var at := rail.clamp_distance(distance)
	global_transform = Transform3D(Rail.basis_from_forward_up(
			rail.sample_forward(at) * float(facing), rail.sample_up(at)), rail.sample_position(at))
	for i in _cars.size():
		var car := _cars[i]
		var nose_side := half - _car_offsets[i]
		var tail_side := nose_side - car.length
		var front_end := _locate(front, rear, nose_side).position()
		var rear_end := _locate(front, rear, tail_side).position()
		var middle := _locate(front, rear, (nose_side + tail_side) * 0.5)
		var forward := front_end - rear_end
		if forward.length_squared() < 1e-9:
			# Squeezed against a dead end. Any orientation will do.
			forward = -global_basis.z
		var placed := Transform3D(Rail.basis_from_forward_up(forward,
				middle.rail.sample_up(middle.distance)), (front_end + rear_end) * 0.5)
		car.global_transform = placed * _wreck_pose(i) if derailed else placed
		if derailed:
			car.place_bogies_under_body()
		else:
			var inset := car.bogie_inset()
			car.place_bogies(_track_frame(_locate(front, rear, nose_side - inset)),
					_track_frame(_locate(front, rear, tail_side + inset)))


## The track's own frame at [param location], for a bogie standing on it. Which
## way along the rail it faces does not matter: a bogie looks the same both ways.
static func _track_frame(location: TrackWalker.Location) -> Transform3D:
	return location.rail.sample_transform(location.distance)


## [param along] metres from the centre towards the nose, or behind it when negative.
static func _locate(front: TrackWalker.Step, rear: TrackWalker.Step,
		along: float) -> TrackWalker.Location:
	return front.locate(along) if along >= 0.0 else rear.locate(-along)


## Writes a whole new position at once, so the setters below do not each re-place
## the train from a half-updated state. The train moved itself, so what is under it
## is looked for again.
func _apply_state(new_rail: Rail, new_distance: float, new_facing: int) -> void:
	_suspend_placement = true
	rail = new_rail
	distance = new_distance
	facing = new_facing
	_suspend_placement = false
	_place_on_rail()
	_points_dirty = true


## Moves the centre [param by] metres towards the nose, or towards the tail when
## negative, leaving the facing alone. How a consist change keeps the nose put.
func _shift_centre(by: float) -> void:
	if rail == null or absf(by) < 1e-6:
		return
	var towards := 1 if by > 0.0 else -1
	var step := TrackWalker.walk(rail, distance, facing * towards, absf(by))
	_apply_state(step.rail, step.distance, step.direction * towards)


## Somebody other than the train moved it. Whatever was under it before is not under
## it now, and nothing it was excused applies any more.
func _teleported() -> void:
	if _suspend_placement:
		return
	_points_under.clear()
	_points_dirty = true
	_excused.clear()


## Any of the three setters: the walks the train was placed with no longer hold.
func _position_changed() -> void:
	_front = null
	_teleported()
	_place_on_rail()
	update_configuration_warnings()


func _set_rail(value: Rail) -> void:
	rail = value
	_position_changed()


func _set_distance(value: float) -> void:
	distance = value
	_position_changed()


func _set_facing(value: int) -> void:
	facing = ALONG_RAIL if value >= 0 else AGAINST_RAIL
	_position_changed()
#endregion


#region Consist
## Couples [param type] on behind the last wagon. The nose stays where it is; the
## train grows backwards.
func add_wagon(type: WagonType) -> void:
	var list := wagons.duplicate()
	list.append(type)
	_recouple(list)


## Uncouples the last wagon, if there is one. The nose stays where it is.
func remove_wagon() -> void:
	if wagons.is_empty():
		return
	var list := wagons.duplicate()
	list.pop_back()
	_recouple(list)


## Puts [param list] in as the wagons, keeping the nose where it is.
func _recouple(list: Array[WagonType]) -> void:
	var before := half_length()
	_suspend_placement = true
	wagons = list
	_suspend_placement = false
	_shift_centre(before - half_length())


## Locomotive first, then every wagon that is set.
func _car_types() -> Array[CarType]:
	var types: Array[CarType] = [locomotive if locomotive != null else LocomotiveType.stand_in()]
	for wagon in wagons:
		if wagon != null:
			types.append(wagon)
	return types


func _carried(type: CarType) -> float:
	var wagon := type as WagonType
	return wagon.capacity * load_factor if wagon != null else 0.0


## Works the figures out again and rebuilds the cars to match.
func _rebuild_cars() -> void:
	_bind_types()
	var types := _car_types()
	_length = 0.0
	_mass = 0.0
	_brake_force = 0.0
	_car_offsets.clear()
	for type in types:
		if not _car_offsets.is_empty():
			_length += COUPLING_GAP
		_car_offsets.append(_length)
		_length += type.length
		_mass += type.mass + _carried(type)
		_brake_force += type.brake_force()
	_traction = (types[0] as LocomotiveType).traction
	_front = null
	if not is_inside_tree():
		return

	if _paint == null:
		_paint = TrainPaint.new()
	while _cars.size() > types.size():
		var spare: TrainCar = _cars.pop_back()
		remove_child(spare)
		spare.queue_free()
	while _cars.size() < types.size():
		var car := TrainCar.new()
		car.name = "Car%d" % _cars.size()
		add_child(car, false, Node.INTERNAL_MODE_BACK)
		car.clicked.connect(select)
		_cars.append(car)
	var painted := livery != null
	for i in types.size():
		var engine := i == 0 and painted
		_cars[i].build(types[i], i == 0, load_factor,
				_paint.engine if engine else _paint.body, _paint.cargo, _paint.marker,
				_paint.stripe if engine and livery.striped else null)
	_update_state()
	_refresh_look()
	_place_on_rail()


## Listens to every type the train is built from, so editing a shared type in the
## inspector rebuilds every train using it.
func _bind_types() -> void:
	for type in _bound_types:
		if type.changed.is_connected(_rebuild_cars):
			type.changed.disconnect(_rebuild_cars)
	_bound_types.clear()
	for type in _car_types():
		if not _bound_types.has(type):
			type.changed.connect(_rebuild_cars)
			_bound_types.append(type)


func _set_locomotive(value: LocomotiveType) -> void:
	locomotive = value
	_rebuild_cars()
	update_configuration_warnings()


func _set_wagons(value: Array[WagonType]) -> void:
	wagons = value
	_rebuild_cars()
	update_configuration_warnings()


func _set_livery(value: Livery) -> void:
	if livery != null and livery.changed.is_connected(_rebuild_cars):
		livery.changed.disconnect(_rebuild_cars)
	livery = value
	if livery != null:
		livery.changed.connect(_rebuild_cars)
	_rebuild_cars()


func _set_load_factor(value: float) -> void:
	load_factor = clampf(value, 0.0, 1.0)
	_rebuild_cars()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if locomotive == null:
		warnings.append("No locomotive set, so a stand-in is drawn. Pick a LocomotiveType "
				+ "from res://rolling_stock/.")
	if wagons.has(null):
		warnings.append("An empty slot in wagons is skipped.")
	if rail == null:
		warnings.append("No rail set.")
		return warnings
	if rail.rail_length() <= 0.0 or not rail.is_inside_tree():
		return warnings
	var half := half_length()
	for direction: int in [facing, -facing]:
		var reach := TrackWalker.walk(rail, distance, direction, half)
		if reach.at_dead_end and reach.travelled < half - 0.01:
			warnings.append("The train's %s runs %.1f m off the end of %s." % [
					"nose" if direction == facing else "tail", half - reach.travelled,
					reach.rail.name])
	return warnings
#endregion
