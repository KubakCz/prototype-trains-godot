@tool
class_name CompoundTurnout
extends Node3D
## Several [Turnout]s that the player works as one: a three-way, a crossover, a
## double crossover or a double slip.
##
## The members stay ordinary turnouts, and stay the only thing a train ever deals
## with - [TrackWalker] does not know the assembly exists. What the assembly adds
## is a single control: a list of [i]positions[/i], each one a setting for every
## member, and a click that steps to the next. It throws its members through
## [method Turnout.throw_points], the one entry point for throwing, and takes
## [member Turnout.player_operable] off them so that the only way to move a
## member's points from the game is to cycle the whole assembly.
##
## A click on any member's 3D marker cycles the assembly - the markers stay,
## because the points really are there - and the floating widget over the
## assembly is the one control element the overlay shows for it.
##
## Positions per kind:
##
## - [constant THREE_WAY] - [code]STRAIGHT[/code], [code]LEFT[/code],
##   [code]RIGHT[/code], cycled in that order. Two members on the same main rail,
##   facing the same way, branching to opposite sides: straight is both normal,
##   and a branch is its member reverse with the other left normal.
## - [constant CROSSOVER] - [code]PARALLEL[/code] / [code]CROSS[/code]. Two
##   members on two parallel rails, sharing one connecting rail as their branch.
##   Parallel is both normal; cross is both reverse.
## - [constant DOUBLE_CROSSOVER] - the same two positions, over four members and
##   two connecting rails that cross each other in the middle. That middle is a
##   [Crossing], authored beside the assembly, not part of it.
## - [constant DOUBLE_SLIP] - two tracks crossing at an angle, with a slip road on
##   each side of the diamond joining one track to the other. Four members, two on
##   each track, each slip road the branch of one member on each. Worked in pairs,
##   like the crossovers: [code]STRAIGHT[/code] opens both straight routes (every
##   member normal), [code]SLIP[/code] both slip roads (every member reverse).

enum Kind {
	## One track splitting into three.
	THREE_WAY,
	## Two parallel tracks joined by one connecting track.
	CROSSOVER,
	## Two parallel tracks joined by two connecting tracks that cross in an X - a
	## scissors crossover.
	DOUBLE_CROSSOVER,
	## Two tracks crossing at an angle, with a slip road on each side of the
	## diamond.
	DOUBLE_SLIP,
}

## What [member compound_position] reads while the members are in a combination
## none of the positions describes - someone threw one of them directly.
const MIXED := -1

const _COLOR_SET := Color(0.25, 1.0, 0.35)
const _COLOR_UNSET := Color(0.85, 0.2, 0.18)
const _COLOR_POINTS := Color(1.0, 1.0, 1.0)

## Emitted whenever the assembly's position changes, however it was changed -
## including a member being thrown on its own.
signal position_changed

@export var kind := Kind.CROSSOVER: set = _set_kind
## The turnouts the assembly drives. Order does not matter to the positions -
## which member is the left branch of a three-way is read off the curves - but
## keeping the members as children of the assembly keeps the scene tree legible,
## and makes the assembly ready after them.
@export var members: Array[Turnout] = []: set = _set_members
## Which of the kind's positions the members are set to. Setting it throws them.
@export var compound_position := 0: set = _set_compound_position
## Whether clicking the assembly in the running game cycles it. Step 8's
## interlocking takes this away while a train is on the assembly.
@export var player_operable := true

@export_group("Debug Draw")
## The routes through the whole assembly, drawn on the track: set routes green,
## the rest red. Replaces the members' own legs, which drawn one at a time
## would paint over each other. Driven by [MarkerOverlay] at runtime.
@export var debug_draw := true: set = _set_debug_draw
## How far along the assembly's outer legs the overlay is drawn. The track
## between two members is always drawn in full.
@export var leg_length := 12.0: set = _set_leg_length
## Height above the railhead the overlay floats at.
@export var overlay_lift := 0.55

var _bound: Array[Turnout] = []
## Set while the assembly is throwing its own members, so that the
## [signal Turnout.position_changed] each throw raises is not mistaken for
## someone else moving them.
var _applying := false
var _debug_mesh: MeshInstance3D
static var _debug_material: StandardMaterial3D


func _ready() -> void:
	_bind_members()
	if not Engine.is_editor_hint():
		# The assembly is authoritative about where it starts; members authored in
		# some other combination are brought into line.
		_apply_position()
	_refresh_debug_mesh()


func _enter_tree() -> void:
	# Re-entering the tree after being moved; the first entry is _ready's job,
	# because the member references are not resolved yet at that point.
	if is_node_ready():
		_bind_members()


func _exit_tree() -> void:
	_unbind_members()


#region Positions
## How many positions this kind of assembly cycles through.
func position_count() -> int:
	match kind:
		Kind.THREE_WAY:
			return 3
		_:
			return 2


## A position's name, for readouts and the inspector.
func position_label(index: int) -> String:
	if index == MIXED:
		return "MIXED"
	match kind:
		Kind.THREE_WAY:
			return ["STRAIGHT", "LEFT", "RIGHT"][index]
		Kind.DOUBLE_SLIP:
			return ["STRAIGHT", "SLIP"][index]
		_:
			return ["PARALLEL", "CROSS"][index]


## What every member is set to in [param index], in [member members] order.
func member_positions(index: int) -> Array[Turnout.Position]:
	var wanted: Array[Turnout.Position] = []
	for _i in members.size():
		wanted.append(Turnout.Position.NORMAL)
	if index <= 0:
		return wanted
	if kind == Kind.THREE_WAY:
		var branch := three_way_member(-1 if index == 1 else 1)
		var at := members.find(branch)
		if at >= 0:
			wanted[at] = Turnout.Position.REVERSE
		return wanted
	for i in wanted.size():
		wanted[i] = Turnout.Position.REVERSE
	return wanted


## The three-way member whose branch leaves to [param side] (-1 left, +1 right,
## seen by a train making the facing move). If both branch to the same side the
## level is odd but still drivable, so the members are then told apart by order.
func three_way_member(side: int) -> Turnout:
	if members.size() < 2 or members[0] == null or members[1] == null:
		return null
	var first := members[0]
	var second := members[1]
	if first.branch_side() == second.branch_side():
		return first if side < 0 else second
	return first if first.branch_side() == side else second


## The single entry point for the player: steps to the next position. A mixed
## assembly starts again from the first.
func cycle() -> void:
	compound_position = (maxi(compound_position, MIXED) + 1) % position_count()


## True when the members are in the combination [member compound_position] names.
func is_consistent() -> bool:
	return compound_position != MIXED
#endregion


#region Topology
## True when the assembly has the members its kind needs and all of them work.
func is_usable() -> bool:
	if members.size() != _member_count():
		return false
	for member in members:
		if member == null or not member.is_usable():
			return false
	return true


func _member_count() -> int:
	match kind:
		Kind.THREE_WAY, Kind.CROSSOVER:
			return 2
		_:
			return 4


## Where the assembly is, in global space: the middle of its members' points.
func centre() -> Vector3:
	var sum := Vector3.ZERO
	var count := 0
	for member in members:
		if member != null and member.is_usable():
			sum += member.points_position()
			count += 1
	return sum / float(count) if count > 0 else global_position


## Where the floating widget's leader line lands, in global space.
func overlay_anchor() -> Vector3:
	return centre() + Vector3.UP * 2.4


## Which way the assembly runs, flattened: the first member's through leg. The
## frame the schematic is drawn in.
func heading() -> Vector3:
	if members.is_empty() or members[0] == null or not members[0].is_usable():
		return Vector3.FORWARD
	var through := members[0].through_direction()
	var flat := Vector3(through.x, 0.0, through.z)
	return flat.normalized() if flat.length_squared() > 1e-9 else Vector3.FORWARD


## True while the mouse is over any member's 3D marker.
func is_pointer_over() -> bool:
	for member in members:
		if member != null and member.is_pointer_over():
			return true
	return false


## The next member's points along [param exit]'s rail in its direction, as the
## distance along that rail - or NAN when the leg leaves the assembly.
func _next_member_on(exit: Turnout.Exit, from: Turnout) -> float:
	var best := NAN
	for member in members:
		if member == null or member == from:
			continue
		for at in member.distances_on(exit.rail):
			var ahead := (at - exit.distance) * float(exit.direction)
			if ahead > TrackWalker.EPSILON and (is_nan(best)
					or ahead < (best - exit.distance) * float(exit.direction)):
				best = at
	return best
#endregion


#region Routes
## The assembly's own track, for drawing it: every leg that leaves the assembly
## out to [member leg_length], and every stretch between two members in full,
## once. Each span starts at a member's points.
func track_pieces() -> Array[TrackWalker.Span]:
	var pieces: Array[TrackWalker.Span] = []
	if not is_usable():
		return pieces
	for member in members:
		for leg: Turnout.Leg in [Turnout.Leg.TOE, Turnout.Leg.THROUGH, Turnout.Leg.DIVERGING]:
			var exit := member.leg_exit(leg)
			var inner := _next_member_on(exit, member)
			if is_nan(inner):
				pieces.append(TrackWalker.Span.new(exit.rail, exit.distance,
						exit.rail.clamp_distance(exit.distance + float(exit.direction) * leg_length)))
				continue
			# Found from both ends; kept from the end whose member comes first.
			var other := _member_at(exit.rail, inner)
			if members.find(member) < members.find(other):
				pieces.append(TrackWalker.Span.new(exit.rail, exit.distance, inner))
	return pieces


## The legs that leave the assembly, as the member and the leg.
func outer_legs() -> Array[Dictionary]:
	var legs: Array[Dictionary] = []
	if not is_usable():
		return legs
	for member in members:
		for leg: Turnout.Leg in [Turnout.Leg.TOE, Turnout.Leg.THROUGH, Turnout.Leg.DIVERGING]:
			if is_nan(_next_member_on(member.leg_exit(leg), member)):
				legs.append({"member": member, "leg": leg})
	return legs


## Every route the assembly is currently set for, as the stretches of rail it
## runs over, clipped to what [method track_pieces] draws.
##
## Found by walking rather than by reading the members one at a time: a train
## is let in from each outer leg in turn and walked through, and only a walk
## that comes out of the far side is a route. Member by member, a three-way set
## to one branch still shows its second set of points' toe as connected - it
## always is, from that member's point of view - when no train from outside can
## reach it.
func route_spans() -> Array[TrackWalker.Span]:
	var routes: Array[TrackWalker.Span] = []
	var outer := outer_legs()
	var inner_length := 0.0
	for piece in track_pieces():
		inner_length += absf(piece.to - piece.from)
	for entry in outer:
		var exit := (entry["member"] as Turnout).leg_exit(entry["leg"] as Turnout.Leg)
		var start := exit.rail.clamp_distance(exit.distance + float(exit.direction) * leg_length)
		var reach := absf(start - exit.distance)
		var walk := TrackWalker.walk(exit.rail, start, -exit.direction,
				reach + inner_length + leg_length)
		if walk.blocking_turnout != null:
			continue
		routes.append_array(_clip_route(walk.spans, outer))
	return routes


## Cuts a walk off once it is [member leg_length] down an outer leg - the walk
## through the assembly carries on past it, and the drawing does not.
func _clip_route(spans: Array[TrackWalker.Span],
		outer: Array[Dictionary]) -> Array[TrackWalker.Span]:
	var kept: Array[TrackWalker.Span] = []
	for i in spans.size():
		var span := spans[i]
		kept.append(span)
		if i == 0:
			continue
		for entry in outer:
			var exit := (entry["member"] as Turnout).leg_exit(entry["leg"] as Turnout.Leg)
			var direction := signf(span.to - span.from)
			if (exit.rail == span.rail and absf(exit.distance - span.from) <= Turnout.AT_POINTS
					and (direction == 0.0 or direction == float(exit.direction))):
				var run := minf(absf(span.to - span.from), leg_length)
				span.to = span.from + float(exit.direction) * run
				return kept
	return kept


func _member_at(rail: Rail, at: float) -> Turnout:
	for member in members:
		if member == null:
			continue
		for distance in member.distances_on(rail):
			if absf(distance - at) <= TrackWalker.EPSILON:
				return member
	return null
#endregion


#region Player operation
func _on_member_clicked() -> void:
	if player_operable:
		cycle()


func _on_member_moved() -> void:
	if _applying:
		return
	var found := MIXED
	for index in position_count():
		if _members_match(index):
			found = index
			break
	if found != compound_position:
		compound_position = found
	else:
		_refresh_debug_mesh()


func _members_match(index: int) -> bool:
	var wanted := member_positions(index)
	for i in members.size():
		if members[i] != null and members[i].turnout_position != wanted[i]:
			return false
	return true


## Throws every member that is not where [member compound_position] wants it.
func _apply_position() -> void:
	if compound_position == MIXED or members.is_empty():
		return
	var wanted := member_positions(compound_position)
	_applying = true
	for i in members.size():
		var member := members[i]
		if member != null and member.turnout_position != wanted[i]:
			member.throw_points()
	_applying = false
#endregion


#region Member binding
func _bind_members() -> void:
	_unbind_members()
	for member in members:
		if member == null or member in _bound:
			continue
		member.assembly = self
		if not Engine.is_editor_hint():
			member.player_operable = false
		member.clicked.connect(_on_member_clicked)
		member.position_changed.connect(_on_member_moved)
		_bound.append(member)


func _unbind_members() -> void:
	for member in _bound:
		if not is_instance_valid(member):
			continue
		if member.assembly == self:
			member.assembly = null
		if member.clicked.is_connected(_on_member_clicked):
			member.clicked.disconnect(_on_member_clicked)
		if member.position_changed.is_connected(_on_member_moved):
			member.position_changed.disconnect(_on_member_moved)
	_bound.clear()
#endregion


#region Editor authoring
func _validate_property(property: Dictionary) -> void:
	# The positions depend on the kind, so the inspector's dropdown is built from
	# whatever kind is set rather than being one fixed enum.
	if property.name == "compound_position":
		var labels: Array[String] = []
		for index in position_count():
			labels.append("%s:%d" % [position_label(index).capitalize(), index])
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(labels)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var wanted := _member_count()
	if members.size() != wanted:
		warnings.append("A %s needs exactly %d member turnouts; %d are set."
				% [Kind.keys()[kind].capitalize(), wanted, members.size()])
	for member in members:
		if member == null:
			warnings.append("A member slot is empty.")
		elif not member.is_usable():
			warnings.append("Member '%s' is not configured." % member.name)
	if not is_usable():
		return warnings
	match kind:
		Kind.THREE_WAY:
			_warn_three_way(warnings)
		Kind.CROSSOVER:
			_warn_connecting_rails(warnings, 1)
		Kind.DOUBLE_CROSSOVER:
			_warn_connecting_rails(warnings, 2)
		Kind.DOUBLE_SLIP:
			_warn_connecting_rails(warnings, 2)
			_warn_two_per_track(warnings)
	return warnings


## A double slip's four members stand two on each of the two crossing tracks.
func _warn_two_per_track(warnings: PackedStringArray) -> void:
	var by_track: Dictionary[Rail, int] = {}
	for member in members:
		by_track[member.main_rail] = by_track.get(member.main_rail, 0) + 1
	if by_track.size() != 2 or by_track.values().has(1) or by_track.values().has(3):
		warnings.append("A double slip needs its four members two on each of the two crossing "
				+ "tracks.")


func _warn_three_way(warnings: PackedStringArray) -> void:
	var first := members[0]
	var second := members[1]
	if first.main_rail != second.main_rail:
		warnings.append("Both members of a three-way must sit on the same main rail.")
		return
	if first.diverge_towards != second.diverge_towards:
		warnings.append("Both members of a three-way must face the same way (diverge_towards).")
	if absf(first.points_distance() - second.points_distance()) <= TrackWalker.EPSILON * 10.0:
		warnings.append("The two sets of points sit at the same distance. TrackWalker needs "
				+ "them apart - stagger them by a few metres.")
	if first.branch_side() == second.branch_side():
		warnings.append("Both branches leave to the %s, so LEFT and RIGHT are named by member "
				% ("right" if first.branch_side() > 0 else "left")
				+ "order rather than by side.")


## Crossovers: [param connections] connecting rails, each the branch of exactly
## two members, one welded at each of its ends.
func _warn_connecting_rails(warnings: PackedStringArray, connections: int) -> void:
	var by_branch: Dictionary[Rail, Array] = {}
	for member in members:
		if not by_branch.has(member.branch_rail):
			by_branch[member.branch_rail] = []
		by_branch[member.branch_rail].append(member)
	if by_branch.size() != connections:
		warnings.append("Expected %d connecting rail(s) shared as branches, found %d."
				% [connections, by_branch.size()])
		return
	for branch: Rail in by_branch:
		var pair: Array = by_branch[branch]
		if pair.size() != 2:
			warnings.append("Connecting rail '%s' is the branch of %d members, not 2."
					% [branch.name, pair.size()])
			continue
		var a := pair[0] as Turnout
		var b := pair[1] as Turnout
		if a.branch_end == b.branch_end:
			warnings.append("Both ends of '%s' are claimed as the same end (%s)."
					% [branch.name, Turnout.RailEnd.keys()[a.branch_end]])
		if a.main_rail == b.main_rail:
			warnings.append("'%s' connects '%s' to itself; a crossover joins two parallel rails."
					% [branch.name, a.main_rail.name])
#endregion


#region Debug draw
## Every piece of the assembly's track in red, then the set routes over it in
## green, then a cross on the end of each outer leg no route leaves by.
func _refresh_debug_mesh() -> void:
	if not is_inside_tree():
		return
	if _debug_mesh == null:
		_debug_mesh = MeshInstance3D.new()
		_debug_mesh.name = "CompoundDebugDraw"
		_debug_mesh.top_level = true
		add_child(_debug_mesh, false, Node.INTERNAL_MODE_BACK)
	var mesh := ImmediateMesh.new()
	_debug_mesh.mesh = mesh
	if not debug_draw or not is_usable():
		return

	var routes := route_spans()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _get_debug_material())
	for piece in track_pieces():
		_draw_span(mesh, piece, _COLOR_UNSET)
	for route in routes:
		_draw_span(mesh, route, _COLOR_SET)
	for entry in outer_legs():
		var exit := (entry["member"] as Turnout).leg_exit(entry["leg"] as Turnout.Leg)
		if not _is_routed(exit, routes):
			_draw_dead_end(mesh, exit)
	for member in members:
		var base := member.points_position()
		_line(mesh, base, base + Vector3.UP * (overlay_lift + 1.4), _COLOR_POINTS)
	mesh.surface_end()


func _is_routed(exit: Turnout.Exit, routes: Array[TrackWalker.Span]) -> bool:
	var probe := exit.rail.clamp_distance(exit.distance + float(exit.direction) * 1.0)
	for route in routes:
		if route.covers(exit.rail, probe):
			return true
	return false


## One span as a band of three lines, the same way [Turnout] draws its legs.
func _draw_span(mesh: ImmediateMesh, span: TrackWalker.Span, color: Color) -> void:
	const STEP := 0.75
	const HALF_WIDTH := 0.45
	var length := absf(span.to - span.from)
	if length <= TrackWalker.EPSILON:
		return
	var steps := maxi(1, ceili(length / STEP))
	var previous := Vector3.ZERO
	var previous_side := Vector3.ZERO
	for i in steps + 1:
		var at := span.rail.clamp_distance(lerpf(span.from, span.to, float(i) / float(steps)))
		var point := span.rail.sample_position(at) + Vector3.UP * overlay_lift
		var side := span.rail.sample_transform(at).basis.x * HALF_WIDTH
		if i > 0:
			for offset: float in [-1.0, 0.0, 1.0]:
				_line(mesh, previous + previous_side * offset, point + side * offset, color)
		previous = point
		previous_side = side


func _draw_dead_end(mesh: ImmediateMesh, exit: Turnout.Exit) -> void:
	const HALF_WIDTH := 0.45
	var at := exit.rail.clamp_distance(exit.distance + float(exit.direction) * leg_length)
	var point := exit.rail.sample_position(at) + Vector3.UP * overlay_lift
	var side := exit.rail.sample_transform(at).basis.x * HALF_WIDTH
	var up := Vector3.UP * HALF_WIDTH * 1.6
	_line(mesh, point - side - up, point + side + up, _COLOR_UNSET)
	_line(mesh, point - side + up, point + side - up, _COLOR_UNSET)


func _line(mesh: ImmediateMesh, from: Vector3, to: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(from)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(to)


static func _get_debug_material() -> StandardMaterial3D:
	if _debug_material == null:
		_debug_material = StandardMaterial3D.new()
		_debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_debug_material.vertex_color_use_as_albedo = true
		_debug_material.vertex_color_is_srgb = true
		_debug_material.disable_receive_shadows = true
		_debug_material.no_depth_test = true
	return _debug_material
#endregion


func _set_kind(value: Kind) -> void:
	kind = value
	compound_position = clampi(compound_position, MIXED, position_count() - 1)
	notify_property_list_changed()
	_refresh_debug_mesh()
	update_configuration_warnings()


func _set_members(value: Array[Turnout]) -> void:
	members = value
	if is_inside_tree():
		_bind_members()
	_refresh_debug_mesh()
	update_configuration_warnings()


func _set_compound_position(value: int) -> void:
	var changed := compound_position != value
	compound_position = value
	if is_inside_tree() and not _applying:
		_apply_position()
	_refresh_debug_mesh()
	if changed:
		position_changed.emit()


func _set_debug_draw(value: bool) -> void:
	# The overlay pushes its mode onto every turnout every frame, so an unchanged
	# value must not rebuild the mesh.
	if debug_draw == value:
		return
	debug_draw = value
	_refresh_debug_mesh()


func _set_leg_length(value: float) -> void:
	leg_length = value
	_refresh_debug_mesh()
