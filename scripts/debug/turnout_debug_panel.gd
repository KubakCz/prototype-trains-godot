extends PanelContainer
## Keyboard control and live readout for every [Turnout] in the level.
##
## Companion to the train panel: the mouse is the real way to throw a turnout, but
## a keyboard path is what makes the refusal cases reproducible without a hand on
## the mouse, and what lets a headless run drive the whole thing.

## Turnouts found in this group become controllable, in scene-tree order.
@export var turnout_group: StringName = &"turnouts"
@export var readout: Label
## Cycled by [kbd]O[/kbd]. Optional; without it the overlay line is dropped.
@export var overlay: TurnoutOverlay
## Reported alongside each turnout, so it is obvious which train is being held.
@export var train_group: StringName = &"trains"

var _turnouts: Array[Turnout] = []
## Tracked by reference rather than index, so it survives the list changing.
var _selected: Turnout


func _ready() -> void:
	_collect()
	if _turnouts.is_empty():
		push_warning("No turnouts in group '%s'." % turnout_group)
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


## [method Node._input] rather than [method Node._unhandled_key_input] for the
## same reason as the train panel: the GUI layer swallows some keys first.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	_collect()
	match (event as InputEventKey).physical_keycode:
		KEY_T:
			if not _turnouts.is_empty():
				_selected = _turnouts[(_turnouts.find(_selected) + 1) % _turnouts.size()]
		KEY_G:
			if _selected != null:
				_selected.throw_points()
		KEY_O:
			if overlay != null:
				overlay.cycle_mode()
		_:
			return
	get_viewport().set_input_as_handled()
	_refresh()


func _collect() -> void:
	_turnouts.assign(get_tree().get_nodes_in_group(turnout_group))
	if _selected == null or not _turnouts.has(_selected):
		_selected = _turnouts[0] if not _turnouts.is_empty() else null


func _refresh() -> void:
	if readout == null:
		return
	_collect()
	var lines: Array[String] = [
		"[ T ] select turnout   [ G ] throw it   [ LMB ] throw the one under the cursor",
	]
	if overlay != null:
		lines.append("[ O ] overlay: %s" % overlay.mode_label())
	lines.append("")
	for turnout in _turnouts:
		lines.append(_describe(turnout, turnout == _selected))
	readout.text = "\n".join(lines)


## Everything needed to check a turnout is wired up the way the level intended:
## which rail it lives on and where, which way the toe faces, which side the
## branch leaves on, and who is currently waiting at it.
func _describe(turnout: Turnout, is_selected: bool) -> String:
	if not turnout.is_usable():
		return "%s %s  <not configured>" % [">" if is_selected else " ", turnout.name]
	var toe := "towards start" if turnout.diverge_sign() > 0 else "towards end"
	var line := "%s %s  %s  on %s @ %.1f m  toe %s  branch %s %s(%s)" % [
		">" if is_selected else " ",
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
