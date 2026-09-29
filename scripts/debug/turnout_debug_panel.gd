extends DebugPanel
## Live readout for every [Turnout], [CompoundTurnout] and [Crossing] in the
## level, and the switches for the presentation question step 2 left open.
##
## A compound assembly is one line with its members indented under it, since the
## assembly is what the player works; a crossing is one line saying which trains
## are standing over it, since that is all there is to know about one yet.
##
## No keys of its own: clicking a turnout - the 3D marker or its floating widget -
## is the player's actual interface, so a second, keyboard-shaped way in was only
## something extra to keep working. The readout follows the mouse instead, and
## marks the line for whatever the pointer is on.

## Turnouts found in this group are listed, in scene-tree order.
@export var turnout_group: StringName = &"turnouts"
@export var compound_group: StringName = &"compound_turnouts"
@export var crossing_group: StringName = &"crossings"
## Cycled by this panel's two rows. Optional; without it they are dropped.
@export var overlay: MarkerOverlay
## Reported alongside each turnout, so it is obvious which train is being held.
@export var train_group: StringName = &"trains"

var _turnouts: Array[Turnout] = []
var _compounds: Array[CompoundTurnout] = []
var _crossings: Array[Crossing] = []


func _ready() -> void:
	super._ready()
	_collect()
	if _turnouts.is_empty():
		push_warning("No turnouts in group '%s'." % turnout_group)


func _panel_title() -> String:
	return "Turnouts"


func _panel_controls() -> Array[String]:
	if overlay == null:
		return []
	return [
		"overlay: %s   ▸" % overlay.mode_label(),
		"schematic text: %s   ▸" % overlay.turnout_caption_label(),
	]


func _panel_control_pressed(index: int) -> void:
	if overlay == null:
		return
	match index:
		0:
			overlay.cycle_mode()
		1:
			overlay.cycle_turnout_caption()


func _collect() -> void:
	_turnouts.assign(get_tree().get_nodes_in_group(turnout_group))
	_compounds.assign(get_tree().get_nodes_in_group(compound_group))
	_crossings.assign(get_tree().get_nodes_in_group(crossing_group))


## The turnout or assembly the mouse is on, from either of the two things that
## can be clicked: the floating widget, or the 3D marker under it. A member's
## marker counts as its assembly, because that is what the click cycles.
func _hovered() -> Node:
	if overlay != null:
		var subject := overlay.hovered_subject()
		if subject is Turnout or subject is CompoundTurnout:
			return subject
	for turnout in _turnouts:
		if turnout.is_pointer_over():
			return turnout.assembly if turnout.assembly != null else turnout
	return null


func _panel_lines() -> Array[String]:
	_collect()
	var lines: Array[String] = []
	var hovered := _hovered()
	for turnout in _turnouts:
		if turnout.assembly == null:
			lines.append(_describe(turnout, turnout == hovered))
	for compound in _compounds:
		lines.append(_describe_compound(compound, compound == hovered))
		for member in compound.members:
			if member != null:
				lines.append("    " + _describe(member, false))
	for crossing in _crossings:
		lines.append(_describe_crossing(crossing))
	return lines


func _describe_compound(compound: CompoundTurnout, is_hovered: bool) -> String:
	if not compound.is_usable():
		return "%s %s  <not configured>" % [">" if is_hovered else " ", compound.name]
	return "%s %s  %s  %s (%d of %d)" % [
		">" if is_hovered else " ",
		compound.name,
		CompoundTurnout.Kind.keys()[compound.kind],
		compound.position_label(compound.compound_position),
		compound.compound_position + 1,
		compound.position_count(),
	]


func _describe_crossing(crossing: Crossing) -> String:
	if not crossing.is_usable():
		return "  %s  <not configured>" % crossing.name
	var names: Array[String] = []
	for train in crossing.occupants():
		names.append(str(train.name))
	return "  %s  CROSSING  %s @ %.1f m x %s @ %.1f m  %.0f deg  %s" % [
		crossing.name,
		crossing.rail_a.name, crossing.distance_a,
		crossing.rail_b.name, crossing.distance_b,
		crossing.crossing_angle_degrees(),
		"occupied by " + ", ".join(names) if not names.is_empty() else "clear",
	]


## Everything needed to check a turnout is wired up the way the level intended:
## which rail it lives on and where, which way the toe faces, which side the
## branch leaves on, and who is currently waiting at it.
func _describe(turnout: Turnout, is_hovered: bool) -> String:
	if not turnout.is_usable():
		return "%s %s  <not configured>" % [">" if is_hovered else " ", turnout.name]
	var toe := "towards start" if turnout.diverge_sign() > 0 else "towards end"
	var line := "%s %s  %s  on %s @ %.1f m  toe %s  branch %s %s(%s)" % [
		">" if is_hovered else " ",
		turnout.name,
		"REVERSE" if turnout.turnout_position == Turnout.Position.REVERSE else "NORMAL ",
		turnout.main_rail.name,
		turnout.points_distance(),
		toe,
		"right" if turnout.branch_side() > 0 else "left",
		turnout.branch_rail.name,
		Turnout.RailEnd.keys()[turnout.branch_end],
	]
	var held := _held_train(turnout)
	return line if held.is_empty() else "%s  <- holding %s" % [line, held]


func _held_train(turnout: Turnout) -> String:
	for node in get_tree().get_nodes_in_group(train_group):
		var train := node as Train
		if train != null and train.blocking_turnout == turnout:
			return str(train.name)
	return ""
