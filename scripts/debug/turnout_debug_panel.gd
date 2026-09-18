extends DebugPanel
## Live readout for every [Turnout] in the level, and the switch for the
## presentation question step 2 left open.
##
## No keys of its own: clicking a turnout - the 3D marker or its floating widget -
## is the player's actual interface, so a second, keyboard-shaped way in was only
## something extra to keep working. The readout follows the mouse instead, and
## marks the line for whatever the pointer is on.

## Turnouts found in this group are listed, in scene-tree order.
@export var turnout_group: StringName = &"turnouts"
## Cycled by this panel's overlay row. Optional; without it the row is dropped.
@export var overlay: MarkerOverlay
## Reported alongside each turnout, so it is obvious which train is being held.
@export var train_group: StringName = &"trains"

var _turnouts: Array[Turnout] = []


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
	return ["overlay: %s   ▸" % overlay.mode_label()]


func _panel_control_pressed(index: int) -> void:
	if index == 0 and overlay != null:
		overlay.cycle_mode()


func _collect() -> void:
	_turnouts.assign(get_tree().get_nodes_in_group(turnout_group))


## The turnout the mouse is on, from either of the two things that can be
## clicked: the floating widget, or the 3D marker under it.
func _hovered() -> Turnout:
	if overlay != null:
		var subject := overlay.hovered_subject() as Turnout
		if subject != null:
			return subject
	for turnout in _turnouts:
		if turnout.is_pointer_over():
			return turnout
	return null


func _panel_lines() -> Array[String]:
	_collect()
	var lines: Array[String] = []
	var hovered := _hovered()
	for turnout in _turnouts:
		lines.append(_describe(turnout, turnout == hovered))
	return lines


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
