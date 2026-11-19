class_name TrackLayout
extends RefCounted
## What the track is made of, worked out from the rails and the turnouts on them:
## every running rail and where it is cut, the switch blades, check rails,
## sleepers and buffer stops. Geometry only - [TrackMeshBuilder] turns it into
## meshes, and the tests read it directly.
##
## [b]Every rail has two running lines[/b], one either side of its centre line,
## and almost all of the work is deciding where a line must [i]not[/i] be:
##
## - [b]At the points[/b] the two routes share their first metres, so two lines
##   lie on top of each other on each side. On each side one of them is the
##   stock rail and runs on unbroken; the other is a [i]blade[/i] - drawn as a
##   separate, moving mesh as far as its heel and cut out of the static track.
##   Which is which follows from which side the branch leaves on.
## - [b]Wherever one line crosses another[/b] - the frog of a turnout, all four
##   corners of a diamond, everything inside a double slip - both are cut, wide
##   enough that the other line's wheel flange passes through in either
##   direction. This is found by intersecting the lines rather than by knowing
##   what kind of junction it is, so compound turnouts need no special case.
##   Small crossing angles also get check rails on the opposite rail.
##
## Sleepers follow one rule too: where two tracks are too close for each to have
## its own, the higher-ranked one ([method _rank] - a main rail before a branch)
## lays long timbers under both, and the other lays none. That is the "cross ties
## adjusted until the tracks are really split away" of the plan, and again it
## covers a diamond as well as a turnout.

#region Dimensions
## Width of the railhead, and so also the lateral offset between a rail's gauge
## line and its centre line.
const HEAD_WIDTH := 0.07
const HEAD_HEIGHT := 0.04
## Railhead to foot. The railhead is [member Rail.surface_offset] above the
## ground, so rail, sleeper and ballast all have to fit in that.
const RAIL_HEIGHT := 0.13
const WEB_WIDTH := 0.018
const FOOT_WIDTH := 0.13
const FOOT_HEIGHT := 0.014
## Room beside a railhead for a wheel's flange.
const FLANGEWAY := 0.045
## How far an open blade's tip stands off its stock rail.
const BLADE_THROW := 0.11
## Centre-line separation of the two routes at which a blade ends: by then the
## lines are far enough apart for a flange to pass between them.
const HEEL_SEPARATION := HEAD_WIDTH + FLANGEWAY + 0.03
const MIN_HEEL := 1.5
const MAX_HEEL := 15.0
## The tip of a blade is planed thin; full width this far back.
const BLADE_TAPER := 2.0
## Lateral distance from a running rail to a check rail beside it, centre to
## centre: a railhead and a flangeway.
const CHECK_OFFSET := HEAD_WIDTH + FLANGEWAY
## How far a check rail carries on past the gap it guards, before its flare.
const CHECK_RUN := 0.8
## The flared ends: this long, bending this far in towards the middle of the track.
const CHECK_FLARE := 0.5
const CHECK_FLARE_OUT := 0.06
## Beyond this a crossing is square enough that a flange cannot drop into it.
const MAX_CHECK_DEGREES := 30.0
## Below this two lines are taken to be running alongside, not crossing: the
## stock rail and the blade at the points touch at an angle of zero.
const MIN_CROSSING_DEGREES := 1.0
## Longest gap cut beside a crossing, so a near-tangent one stays sane.
const MAX_GAP_HALF := 3.5
## Width of the blunt tip of a frog's V nose: the two nose rails stop where they
## are this far apart, rather than running into a knife edge.
const NOSE_TIP := 0.012
## Lines further apart than this vertically do not meet: a bridge over a tunnel.
const MAX_CROSSING_RISE := 0.5

const SLEEPER_LENGTH := 2.6
const SLEEPER_WIDTH := 0.24
const SLEEPER_HEIGHT := 0.1
const SLEEPER_SPACING := 0.65
## Two tracks whose centre lines are closer than this share their timbers.
const SHARED_TIE_ZONE := SLEEPER_LENGTH + 0.6

## How far the rails run on past a dead end, under the buffer stop.
const BUFFER_RUN := 1.4
## The buffer stop's face, measured from the rail's end: just past where a train
## braking for the end comes to rest.
const BUFFER_FACE := 0.3
## A rail end this close to a turnout's points is welded on, not a dead end.
const WELD_TOLERANCE := 0.5

## Longest step between samples on straight track; curves get as fine as
## [constant _MIN_STEP] so the chords stay within a few millimetres of the arc.
const _MAX_STEP := 4.0
const _MIN_STEP := 0.5
const _SAGITTA := 0.004
const _CELL := 8.0
#endregion


## One running line of a rail: the rail centre line shifted [member lateral]
## metres to the right, cut where something else has to pass.
class Line:
	var rail: Rail
	## -1 for the left rail, +1 for the right, by the rail's own drawn direction.
	var side: int
	var lateral: float
	## Intervals in rail distance where the line is not drawn, as (from, to).
	var cuts: Array[Vector2] = []

	func _init(p_rail: Rail, p_side: int, p_lateral: float) -> void:
		rail = p_rail
		side = p_side
		lateral = p_lateral

	func is_cut(at: float) -> bool:
		for cut in cuts:
			if at > cut.x and at < cut.y:
				return true
		return false

	## Whether [param from]-[param to] overlaps any cut.
	func cut_between(from: float, to: float) -> bool:
		for cut in cuts:
			if cut.x < to and cut.y > from:
				return true
		return false


## A length of rail to extrude: a running rail between two cuts, or a check
## rail. Distances are along [member rail] and may run past either end of it,
## onto the straight run under a buffer stop.
class Piece:
	var rail: Rail
	var lateral: float
	var from: float
	var to: float
	## A check rail's ends bend away from the running rail it guards, towards
	## the middle of the track by [member flare] metres.
	var flare := 0.0
	## Which ends are flared: a wing rail's knuckle end carries straight on from
	## its closure rail instead.
	var flare_from := true
	var flare_to := true
	var is_check := false
	## For a wing rail, the running line it is the continuation of: bent at the
	## knuckle, it is that line's own rail, not another track's.
	var wing_of: Line


## A cut in a running line where another line crosses it. The cut is on one side
## of the crossing only - the arm lying in the other line's flangeway - running
## [member reach] metres from [member at]; the other arm runs on to within
## [member nose] of the crossing and, with the other line's, makes the V nose.
class Gap:
	var line: Line
	var at: float
	## +1/-1: which way along [member line] from [member at] the cut arm lies.
	var cut_direction: int
	var reach: float
	var nose: float
	var angle_degrees: float
	var other: Line
	var other_at: float
	## The same crossing's gap in [member other].
	var partner: Gap

	## The interval of [member line] taken out, as (from, to).
	func cut() -> Vector2:
		if cut_direction > 0:
			return Vector2(at - nose, at + reach)
		return Vector2(at - reach, at + nose)


## One switch blade: the stretch of [member line] from the points to its heel,
## which moves between lying against [member stock] and standing off it.
class Blade:
	var turnout: Turnout
	var line: Line
	## Distance along the blade's rail at the points, and +1/-1 for which way
	## along it the blade runs.
	var start: float
	var direction: int
	var stock: Line
	var stock_start: float
	var stock_direction: int
	var heel: float
	## The points position in which this blade lies closed against its stock rail.
	var closed_when: Turnout.Position


## A sleeper: [member frame] sits on the rail's centre line at sleeper-top
## height, X across the track. It spans [member lo] to [member hi] along X -
## the usual ±half length, or more for a long timber under a second track.
class Sleeper:
	var frame: Transform3D
	var lo: float
	var hi: float
	var rail: Rail
	var distance: float


## A dead end's buffer stop: on the railhead at its face, -Z pointing out of
## the track towards the stop.
class BufferStop:
	var frame: Transform3D
	var rail: Rail
	var distance: float


var rails: Array[Rail] = []
var turnouts: Array[Turnout] = []
var lines: Array[Line] = []
var pieces: Array[Piece] = []
var gaps: Array[Gap] = []
var blades: Array[Blade] = []
var sleepers: Array[Sleeper] = []
var buffer_stops: Array[BufferStop] = []
## Sample distances per rail, including any run past a dead end.
var stations: Dictionary[Rail, PackedFloat64Array] = {}
## How far past each end the rail is drawn: (before its start, after its end).
var overrun: Dictionary[Rail, Vector2] = {}

var _rank: Dictionary[Rail, float] = {}


## Works out everything for [param p_rails]. Turnouts are found through the
## rails' attachments; a turnout whose rails are not both in the list is skipped.
static func build(p_rails: Array[Rail]) -> TrackLayout:
	var layout := TrackLayout.new()
	for rail in p_rails:
		if rail != null and rail.curve != null and rail.rail_length() > 0.1:
			layout.rails.append(rail)
	layout._collect_turnouts()
	layout._find_dead_ends()
	layout._sample_stations()
	layout._make_lines()
	layout._cut_blades()
	layout._cut_crossings()
	layout._make_pieces()
	layout._rank_rails()
	layout._lay_sleepers()
	return layout


#region Sampling
## Transform at [param distance] along [param rail] - beyond either end, the
## straight line carrying on from it.
static func frame_at(rail: Rail, distance: float) -> Transform3D:
	var length := rail.rail_length()
	if distance < 0.0:
		var start := rail.sample_transform(0.0)
		return Transform3D(start.basis, start.origin + start.basis.z * -distance)
	if distance > length:
		var end := rail.sample_transform(length)
		return Transform3D(end.basis, end.origin - end.basis.z * (distance - length))
	return rail.sample_transform(distance)


## Where [param line] is at [param distance]: railhead height, centre of the head.
static func line_point(line: Line, distance: float) -> Vector3:
	var frame := frame_at(line.rail, distance)
	return frame.origin + frame.basis.x * line.lateral


func line_for(rail: Rail, side: int) -> Line:
	for line in lines:
		if line.rail == rail and line.side == side:
			return line
	return null


## Sample distances along [param rail] spaced by curvature, from the start of any
## run before it to the end of any run after it.
func _sample_stations() -> void:
	for rail in rails:
		var length := rail.rail_length()
		var run := overrun.get(rail, Vector2.ZERO) as Vector2
		var at := -run.x
		var end := length + run.y
		var found := PackedFloat64Array([at])
		while at < end - 1e-4:
			var step := _MAX_STEP
			while step > _MIN_STEP:
				var turn := frame_at(rail, at).basis.z.angle_to(
						frame_at(rail, minf(at + step, end)).basis.z)
				# A chord of length s across a turn of t bulges s * t / 8.
				if step * turn / 8.0 <= _SAGITTA:
					break
				step *= 0.5
			at = minf(at + maxf(step, _MIN_STEP), end)
			found.append(at)
		stations[rail] = found


## [param stations] between [param from] and [param to], with both ends added.
static func span_stations(all: PackedFloat64Array, from: float, to: float) -> PackedFloat64Array:
	var found := PackedFloat64Array([from])
	for at in all:
		if at > from + 1e-3 and at < to - 1e-3:
			found.append(at)
	found.append(to)
	return found
#endregion


#region Topology
func _collect_turnouts() -> void:
	for rail in rails:
		for node in rail.attachments():
			var turnout := node as Turnout
			if (turnout != null and turnout.is_usable() and not turnouts.has(turnout)
					and rails.has(turnout.main_rail) and rails.has(turnout.branch_rail)):
				turnouts.append(turnout)


## A rail end with no turnout on it gets a buffer stop, and the rails carry on
## under it.
func _find_dead_ends() -> void:
	for rail in rails:
		var run := Vector2.ZERO
		for end: float in [0.0, rail.rail_length()]:
			if _is_welded(rail, end):
				continue
			var outward := -1.0 if end == 0.0 else 1.0
			var stop := BufferStop.new()
			stop.rail = rail
			stop.distance = end
			var frame := frame_at(rail, end + outward * BUFFER_FACE)
			# -Z out of the track: the rail's -Z already runs towards increasing
			# distance, so only the start end needs turning round.
			var basis := frame.basis if outward > 0.0 else frame.basis.rotated(frame.basis.y, PI)
			stop.frame = Transform3D(basis, frame.origin)
			buffer_stops.append(stop)
			if end == 0.0:
				run.x = BUFFER_RUN
			else:
				run.y = BUFFER_RUN
		overrun[rail] = run


func _is_welded(rail: Rail, end: float) -> bool:
	for turnout in turnouts:
		if turnout.branch_rail == rail and absf(turnout.branch_distance() - end) < WELD_TOLERANCE:
			return true
		if turnout.main_rail == rail and absf(turnout.points_distance() - end) < WELD_TOLERANCE:
			return true
	return false


func _make_lines() -> void:
	for rail in rails:
		var offset := rail.track_gauge * 0.5 + HEAD_WIDTH * 0.5
		lines.append(Line.new(rail, -1, -offset))
		lines.append(Line.new(rail, 1, offset))


## Main rails rank above branches, longer above shorter: whoever ranks higher
## lays the long timbers where two tracks share them.
func _rank_rails() -> void:
	for rail in rails:
		var is_main := false
		for turnout in turnouts:
			if turnout.main_rail == rail:
				is_main = true
		_rank[rail] = (1e6 if is_main else 0.0) + rail.rail_length() + rail.get_instance_id() * 1e-12
#endregion


#region Points
## Each turnout has two blades. With the branch leaving to the right of a facing
## train, the right-hand stock rail is the main rail's right line up to the
## points and the branch's right line after them; the straight blade is the main
## rail's right line from the points to its heel. On the left the main rail's
## line is the stock rail throughout, and the curved blade is the branch's left
## line. A left-hand turnout is the mirror image.
func _cut_blades() -> void:
	for turnout in turnouts:
		var main := turnout.main_rail
		var branch := turnout.branch_rail
		var side := turnout.branch_side()
		var main_dir := turnout.diverge_sign()
		var branch_dir := turnout.branch_exit_sign()
		var points := turnout.points_distance()
		var branch_at := turnout.branch_distance()
		var heel := _heel_length(turnout)

		var straight := Blade.new()
		straight.turnout = turnout
		straight.line = line_for(main, side * main_dir)
		straight.start = points
		straight.direction = main_dir
		straight.stock = line_for(branch, side * branch_dir)
		straight.stock_start = branch_at
		straight.stock_direction = branch_dir
		straight.heel = heel
		straight.closed_when = Turnout.Position.NORMAL

		var curved := Blade.new()
		curved.turnout = turnout
		curved.line = line_for(branch, -side * branch_dir)
		curved.start = branch_at
		curved.direction = branch_dir
		curved.stock = line_for(main, -side * main_dir)
		curved.stock_start = points
		curved.stock_direction = main_dir
		curved.heel = heel
		curved.closed_when = Turnout.Position.REVERSE

		for blade: Blade in [straight, curved]:
			var a := blade.start
			var b := blade.start + float(blade.direction) * blade.heel
			blade.line.cuts.append(Vector2(minf(a, b), maxf(a, b)))
			blades.append(blade)


## How far from the points the two routes' centre lines have drawn
## [constant HEEL_SEPARATION] apart - where a blade can end.
static func _heel_length(turnout: Turnout) -> float:
	var main := turnout.main_rail
	var branch := turnout.branch_rail
	var limit := minf(MAX_HEEL, branch.rail_length())
	var along := 0.25
	while along < limit:
		var on_main := frame_at(main, turnout.points_distance()
				+ float(turnout.diverge_sign()) * along).origin
		var on_branch := branch.sample_position(branch.clamp_distance(turnout.branch_distance()
				+ float(turnout.branch_exit_sign()) * along))
		if on_main.distance_to(on_branch) >= HEEL_SEPARATION:
			return maxf(along, MIN_HEEL)
		along += 0.25
	return clampf(limit, MIN_HEEL, MAX_HEEL)


## Where [param blade] is at [param along] metres from the points, in
## [param position]: blended from hard against (or standing off) the stock rail
## at the tip into its own line at the heel, where it is fixed.
static func blade_point(blade: Blade, along: float, closed: bool) -> Vector3:
	var own_at := blade.start + float(blade.direction) * along
	var own_frame := frame_at(blade.line.rail, own_at)
	var own := own_frame.origin + own_frame.basis.x * blade.line.lateral
	var stock := line_point(blade.stock,
			blade.stock_start + float(blade.stock_direction) * along)
	var inward := (own_frame.origin - own)
	inward = inward.normalized() if inward.length_squared() > 1e-9 else Vector3.ZERO
	var stand_off := HEAD_WIDTH + (0.0 if closed else BLADE_THROW)
	var target := stock + inward * stand_off
	var t := clampf(along / blade.heel, 0.0, 1.0)
	return target.lerp(own, t * t * (3.0 - 2.0 * t))


## Head width at [param along] metres from the tip.
static func blade_head_width(along: float) -> float:
	return lerpf(HEAD_WIDTH * 0.3, HEAD_WIDTH, clampf(along / BLADE_TAPER, 0.0, 1.0))
#endregion


#region Crossings
## Intersects every running line with every other one and cuts both where they
## cross: the frog of every turnout, the four corners of every diamond, and
## whatever a double slip packs into its middle. A line the blades have cut out
## is not looked at there, which is what keeps a stock rail and its blade -
## which touch at the points - from counting as a crossing.
func _cut_crossings() -> void:
	var seg_a := PackedVector3Array()
	var seg_b := PackedVector3Array()
	var seg_line := PackedInt32Array()
	var seg_from := PackedFloat64Array()
	var seg_to := PackedFloat64Array()
	var grid: Dictionary[Vector2i, PackedInt32Array] = {}

	for index in lines.size():
		var line := lines[index]
		var all := stations[line.rail]
		for i in all.size() - 1:
			var from := all[i]
			var to := all[i + 1]
			if line.is_cut((from + to) * 0.5):
				continue
			var id := seg_a.size()
			var a := line_point(line, from)
			var b := line_point(line, to)
			seg_a.append(a)
			seg_b.append(b)
			seg_line.append(index)
			seg_from.append(from)
			seg_to.append(to)
			for cell in _cells_between(a, b):
				if not grid.has(cell):
					grid[cell] = PackedInt32Array()
				grid[cell].append(id)

	var seen := {}
	for cell in grid:
		var ids := grid[cell]
		for i in ids.size():
			for j in range(i + 1, ids.size()):
				var p := ids[i]
				var q := ids[j]
				var line_p := lines[seg_line[p]]
				var line_q := lines[seg_line[q]]
				if line_p.rail == line_q.rail and absf(seg_from[p] - seg_from[q]) < 20.0:
					continue
				var key := Vector2i(mini(p, q), maxi(p, q))
				if seen.has(key):
					continue
				seen[key] = true
				var hit := _intersect_xz(seg_a[p], seg_b[p], seg_a[q], seg_b[q])
				if hit == Vector2(-1.0, -1.0):
					continue
				var on_p := seg_a[p].lerp(seg_b[p], hit.x)
				var on_q := seg_a[q].lerp(seg_b[q], hit.y)
				if absf(on_p.y - on_q.y) > MAX_CROSSING_RISE:
					continue
				var dir_p := _flat(seg_b[p] - seg_a[p])
				var dir_q := _flat(seg_b[q] - seg_a[q])
				# angle_to is signed; which way round they cross does not matter.
				var angle := rad_to_deg(absf(dir_p.angle_to(dir_q)))
				angle = minf(angle, 180.0 - angle)
				if angle < MIN_CROSSING_DEGREES:
					continue
				var at_p := lerpf(seg_from[p], seg_to[p], hit.x)
				var at_q := lerpf(seg_from[q], seg_to[q], hit.y)
				var gap_p := _add_gap(line_p, at_p, line_q, at_q, angle)
				var gap_q := _add_gap(line_q, at_q, line_p, at_p, angle)
				gap_p.partner = gap_q
				gap_q.partner = gap_p


## A wheel on [param other] carries its flange beside the railhead, on the
## gauge side - towards the middle of its own track. So [param line] has to be
## absent wherever it comes within a railhead and a flangeway of [param other]
## on that side, which along a line crossing at a shallow angle is a long way.
## Worked out as if both were straight, with a tenth and a few centimetres to
## spare for the ones that curve away from each other less quickly than that: a
## slip road inside a double slip does. On the other side, the field side, no
## flange passes: the line runs on to the crossing and makes half of the nose.
func _add_gap(line: Line, at: float, other: Line, other_at: float, angle: float) -> Gap:
	var sine := sin(deg_to_rad(angle))
	var frame := frame_at(line.rail, at)
	var ahead := _flat(-frame.basis.z)
	var other_frame := frame_at(other.rail, other_at)
	var gauge_side := _flat(other_frame.basis.x * -signf(other.lateral))
	var gap := Gap.new()
	gap.line = line
	gap.at = at
	gap.cut_direction = 1 if ahead.dot(gauge_side) > 0.0 else -1
	gap.reach = minf((HEAD_WIDTH + FLANGEWAY) / sine * 1.1 + 0.05, MAX_GAP_HALF)
	gap.nose = minf(NOSE_TIP / sine, MAX_GAP_HALF)
	gap.angle_degrees = angle
	gap.other = other
	gap.other_at = other_at
	gaps.append(gap)
	line.cuts.append(gap.cut())
	return gap


## Where [param gap]'s two nose rails - its line's and the other line's arms on
## each other's field side - leave the crossing at an acute angle, that is a
## frog, and the arm cut out of the other line's flangeway carries on as a wing
## rail: bent at the knuckle to run beside the other line's nose rail, a
## railhead and a flangeway off it, until past the nose. Laid along the other
## line, as a check rail of the other rail. At an obtuse crossing - the middle of
## a diamond - the nose rails run almost straight on through each other as a
## knuckle and there is no wing.
func _add_wing(gap: Gap, running: Dictionary) -> void:
	var other := gap.other
	var partner := gap.partner
	var forward := _flat(-frame_at(gap.line.rail, gap.at).basis.z)
	var other_forward := _flat(-frame_at(other.rail, gap.other_at).basis.z)
	var nose_arm := forward * float(-gap.cut_direction)
	var other_nose_arm := other_forward * float(-partner.cut_direction)
	if nose_arm.dot(other_nose_arm) <= 0.0:
		return
	var sine := sin(deg_to_rad(gap.angle_degrees))
	var toward_nose := -partner.cut_direction
	# The knuckle: where this line comes to a check rail's offset off the other
	# line, and the wing carries on from it without a flare.
	var knuckle := minf(CHECK_OFFSET / sine, MAX_GAP_HALF)
	var start := gap.other_at - float(toward_nose) * knuckle
	var finish := gap.other_at + float(toward_nose) * (partner.reach + CHECK_RUN)
	var run := overrun[other.rail]
	var from := maxf(minf(start, finish), -run.x)
	var to := minf(maxf(start, finish), other.rail.rail_length() + run.y)
	# The other line's nose rail has to be there for the wing to stand beside.
	var nose_from := gap.other_at + float(toward_nose) * (partner.nose + 0.01)
	if other.cut_between(minf(nose_from, finish), maxf(nose_from, finish)):
		return
	var lateral := other.lateral - signf(other.lateral) * CHECK_OFFSET
	if _fouls_another_track(other.rail, lateral, from, to, running, gap.line.rail):
		return
	var piece := _add_piece(other.rail, lateral, from, to)
	if piece != null:
		piece.is_check = true
		piece.flare = CHECK_FLARE_OUT
		piece.wing_of = gap.line
		if toward_nose > 0:
			piece.flare_from = false
		else:
			piece.flare_to = false


## Segment intersection in plan: the parameters along each, or (-1, -1).
static func _intersect_xz(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> Vector2:
	var r := Vector2(b.x - a.x, b.z - a.z)
	var s := Vector2(d.x - c.x, d.z - c.z)
	var denominator := r.cross(s)
	if absf(denominator) < 1e-12:
		return Vector2(-1.0, -1.0)
	var offset := Vector2(c.x - a.x, c.z - a.z)
	var t := offset.cross(s) / denominator
	var u := offset.cross(r) / denominator
	if t < 0.0 or t > 1.0 or u < 0.0 or u > 1.0:
		return Vector2(-1.0, -1.0)
	return Vector2(t, u)


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


static func _cell(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / _CELL), floori(point.z / _CELL))


static func _cells_between(a: Vector3, b: Vector3) -> Array[Vector2i]:
	var lo := _cell(Vector3(minf(a.x, b.x), 0.0, minf(a.z, b.z)))
	var hi := _cell(Vector3(maxf(a.x, b.x), 0.0, maxf(a.z, b.z)))
	var found: Array[Vector2i] = []
	for x in range(lo.x, hi.x + 1):
		for z in range(lo.y, hi.y + 1):
			found.append(Vector2i(x, z))
	return found
#endregion


#region Pieces
## Everything left of each running line once the cuts are taken out, plus a
## wing rail at every frog and a check rail opposite every shallow crossing gap.
func _make_pieces() -> void:
	for line in lines:
		line.cuts = _merged(line.cuts)
		var run := overrun[line.rail]
		var at := -run.x
		var end := line.rail.rail_length() + run.y
		for cut in line.cuts:
			if cut.x > at:
				_add_piece(line.rail, line.lateral, at, minf(cut.x, end))
			at = maxf(at, cut.y)
		if end > at:
			_add_piece(line.rail, line.lateral, at, end)

	# Every running rail, sampled, so a check rail can tell whether it would stand
	# in another track's flangeway.
	var running := {}
	for piece in pieces:
		var at := piece.from
		while at <= piece.to:
			var point := line_point_at(piece.rail, piece.lateral, at)
			var cell := Vector2i(floori(point.x), floori(point.z))
			if not running.has(cell):
				running[cell] = []
			running[cell].append([point, piece.rail])
			at += 0.2

	for gap in gaps:
		_add_wing(gap, running)
	for gap in gaps:
		if gap.angle_degrees > MAX_CHECK_DEGREES:
			continue
		var opposite := line_for(gap.line.rail, -gap.line.side)
		var length := gap.line.rail.rail_length()
		var from := maxf(gap.cut().x - CHECK_RUN, 0.0)
		var to := minf(gap.cut().y + CHECK_RUN, length)
		# The opposite rail is broken here too - the middle of a diamond, or the
		# blades - so there is nothing for a check rail to stand beside.
		if opposite.cut_between(from, to):
			continue
		var lateral := opposite.lateral - signf(opposite.lateral) * CHECK_OFFSET
		# Inside a double slip the next set of points can be right there, with
		# another track's rail where the check rail would go.
		if _fouls_another_track(gap.line.rail, lateral, from, to, running):
			continue
		var piece := _add_piece(gap.line.rail, lateral, from, to)
		if piece != null:
			piece.is_check = true
			piece.flare = CHECK_FLARE_OUT


## Whether a check rail [param lateral] metres off [param rail]'s centre line,
## from [param from] to [param to] with its ends flared, would come within a
## flangeway of another track's running rail. [param running] is sampled every
## 20 cm, so the margin is widened by as much as a sample can miss by. A wing
## rail joins [param also_ignore]'s line at its knuckle, so that is not counted.
static func _fouls_another_track(rail: Rail, lateral: float, from: float, to: float,
		running: Dictionary, also_ignore: Rail = null) -> bool:
	var clear := CHECK_OFFSET + 0.1
	var at := from
	while at <= to:
		var into := minf(at - from, to - at)
		var flare := CHECK_FLARE_OUT * clampf(1.0 - into / CHECK_FLARE, 0.0, 1.0)
		var point := line_point_at(rail, lateral - signf(lateral) * flare, at)
		var home := Vector2i(floori(point.x), floori(point.z))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for entry: Array in running.get(home + Vector2i(dx, dz), []):
					if entry[1] != rail and entry[1] != also_ignore \
							and point.distance_to(entry[0]) < clear:
						return true
		at += 0.1
	return false


static func line_point_at(rail: Rail, lateral: float, distance: float) -> Vector3:
	var frame := frame_at(rail, distance)
	return frame.origin + frame.basis.x * lateral


func _add_piece(rail: Rail, lateral: float, from: float, to: float) -> Piece:
	if to - from < 0.05:
		return null
	var piece := Piece.new()
	piece.rail = rail
	piece.lateral = lateral
	piece.from = from
	piece.to = to
	pieces.append(piece)
	return piece


static func _merged(intervals: Array[Vector2]) -> Array[Vector2]:
	var sorted := intervals.duplicate()
	sorted.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var merged: Array[Vector2] = []
	for interval: Vector2 in sorted:
		if not merged.is_empty() and interval.x <= merged[-1].y:
			merged[-1].y = maxf(merged[-1].y, interval.y)
		else:
			merged.append(interval)
	return merged
#endregion


#region Sleepers
## One sleeper every [constant SLEEPER_SPACING] along every rail, except where a
## higher-ranked track runs close by: that one lays a long timber under both.
func _lay_sleepers() -> void:
	# Centre lines, for asking where another track crosses a sleeper's line.
	var seg_a := PackedVector3Array()
	var seg_b := PackedVector3Array()
	var seg_rail: Array[Rail] = []
	var seg_from := PackedFloat64Array()
	var grid: Dictionary[Vector2i, PackedInt32Array] = {}
	for rail in rails:
		var all := stations[rail]
		for i in all.size() - 1:
			var id := seg_a.size()
			var a := frame_at(rail, all[i]).origin
			var b := frame_at(rail, all[i + 1]).origin
			seg_a.append(a)
			seg_b.append(b)
			seg_rail.append(rail)
			seg_from.append(all[i])
			for cell in _cells_between(a, b):
				if not grid.has(cell):
					grid[cell] = PackedInt32Array()
				grid[cell].append(id)

	var half := SLEEPER_LENGTH * 0.5
	var reach := SHARED_TIE_ZONE * 2.0
	# Highest rank first, so that where two tracks' timbers would cross - the
	# last long timbers of a turnout against the branch's first own sleepers,
	# laid at an angle to them - the lower-ranked track is the one that gives
	# way. Footprints in plan: centre, across axis, half length, by cell.
	var by_rank := rails.duplicate()
	by_rank.sort_custom(func(a: Rail, b: Rail) -> bool: return _rank[a] > _rank[b])
	var placed: Dictionary[Vector2i, Array] = {}
	for rail: Rail in by_rank:
		var run := overrun[rail]
		var at := -run.x + SLEEPER_SPACING * 0.5
		var end := rail.rail_length() + run.y
		while at < end:
			var frame := frame_at(rail, at)
			var across := Vector3(frame.basis.x.x, 0.0, frame.basis.x.z).normalized()
			# Nearest crossing of this sleeper's line by each other track.
			var nearest: Dictionary[Rail, float] = {}
			var self_ahead := false
			var probe_a := frame.origin - across * reach
			var probe_b := frame.origin + across * reach
			var checked := {}
			for cell in _cells_between(probe_a, probe_b):
				if not grid.has(cell):
					continue
				for id in grid[cell]:
					if checked.has(id):
						continue
					checked[id] = true
					var other := seg_rail[id]
					if other == rail and absf(seg_from[id] - at) < 20.0:
						continue
					var hit := _intersect_xz(probe_a, probe_b, seg_a[id], seg_b[id])
					if hit == Vector2(-1.0, -1.0):
						continue
					var point := seg_a[id].lerp(seg_b[id], hit.y)
					if absf(point.y - frame.origin.y) > 1.0:
						continue
					var u := (hit.x * 2.0 - 1.0) * reach
					if other == rail:
						# The same rail come back round: one of the two passes keeps
						# its sleepers, the later one along the rail gives way.
						if absf(u) < SHARED_TIE_ZONE and seg_from[id] < at:
							self_ahead = true
						continue
					if not nearest.has(other) or absf(u) < absf(nearest[other]):
						nearest[other] = u
			var lo := -half
			var hi := half
			var skip := self_ahead
			for other in nearest:
				var u := nearest[other]
				if absf(u) < SHARED_TIE_ZONE:
					if _rank[other] > _rank[rail]:
						skip = true
						break
					lo = minf(lo, u - half)
					hi = maxf(hi, u + half)
			if not skip:
				# Never reach more than halfway to a track this one does not
				# cover: that one lays its own timbers from the other side.
				for other in nearest:
					var u := nearest[other]
					if absf(u) >= SHARED_TIE_ZONE:
						if u > 0.0:
							hi = minf(hi, maxf(u * 0.5, half))
						else:
							lo = maxf(lo, minf(u * 0.5, -half))
				var centre := frame.origin + across * ((lo + hi) * 0.5)
				var footprint := [Vector2(centre.x, centre.z), Vector2(across.x, across.z),
						(hi - lo) * 0.5, rail]
				if not _overlaps_placed(footprint, placed):
					var sleeper := Sleeper.new()
					sleeper.rail = rail
					sleeper.distance = at
					sleeper.lo = lo
					sleeper.hi = hi
					sleeper.frame = Transform3D(frame.basis,
							frame.origin + frame.basis.y * -RAIL_HEIGHT)
					sleepers.append(sleeper)
					var cell := _cell(centre)
					if not placed.has(cell):
						placed[cell] = []
					placed[cell].append(footprint)
			at += SLEEPER_SPACING


## Whether a sleeper's footprint, as (centre, across, half length, rail), would
## cross one another track has already laid. Rectangles in plan, by separating
## axes.
static func _overlaps_placed(footprint: Array, placed: Dictionary[Vector2i, Array]) -> bool:
	var centre: Vector2 = footprint[0]
	var home := Vector2i(floori(centre.x / _CELL), floori(centre.y / _CELL))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var cell := home + Vector2i(dx, dz)
			if not placed.has(cell):
				continue
			for other: Array in placed[cell]:
				if other[3] != footprint[3] and _footprints_cross(footprint, other):
					return true
	return false


static func _footprints_cross(a: Array, b: Array) -> bool:
	# A hair narrower than drawn, so sleepers merely touching do not count.
	var half_width := SLEEPER_WIDTH * 0.5 - 0.02
	var a_across: Vector2 = a[1]
	var b_across: Vector2 = b[1]
	var offset: Vector2 = b[0] - a[0]
	for axis: Vector2 in [a_across, a_across.orthogonal(), b_across, b_across.orthogonal()]:
		var reach_a := absf(a_across.dot(axis)) * (float(a[2]) - 0.02) \
				+ absf(a_across.orthogonal().dot(axis)) * half_width
		var reach_b := absf(b_across.dot(axis)) * (float(b[2]) - 0.02) \
				+ absf(b_across.orthogonal().dot(axis)) * half_width
		if absf(offset.dot(axis)) > reach_a + reach_b:
			return false
	return true
#endregion
