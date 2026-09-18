extends DebugPanel
## Live readout for every [RailSignal] in the level, plus the switches for the
## two presentation questions step 3 left open.
##
## No keys of its own, for the same reason as the turnout panel: clicking a
## signal is the player's actual interface, and the readout marks whichever line
## the mouse is on rather than one a select key walked to.

## Signals found in this group are listed, in scene-tree order.
@export var signal_group: StringName = &"signals"
## Cycled by this panel's two rows. Optional; without it they are dropped.
@export var overlay: MarkerOverlay
## Reported alongside each signal, so it is obvious which train is being held.
@export var train_group: StringName = &"trains"

var _signals: Array[RailSignal] = []


func _ready() -> void:
	super._ready()
	_collect()
	if _signals.is_empty():
		push_warning("No signals in group '%s'." % signal_group)


func _panel_title() -> String:
	return "Signals"


func _panel_controls() -> Array[String]:
	if overlay == null:
		return []
	return [
		"signal widget: %s   ▸" % overlay.signal_style_label(),
		"collapse: %s   ▸" % overlay.collapse_label(),
	]


func _panel_control_pressed(index: int) -> void:
	if overlay == null:
		return
	match index:
		0:
			overlay.cycle_signal_style()
		1:
			overlay.cycle_collapse_rule()


func _collect() -> void:
	_signals.assign(get_tree().get_nodes_in_group(signal_group))


## The signal the mouse is on, from either of the two things that can be clicked:
## the floating widget, or the mast under it.
func _hovered() -> RailSignal:
	if overlay != null:
		var subject := overlay.hovered_subject() as RailSignal
		if subject != null:
			return subject
	for rail_signal in _signals:
		if rail_signal.is_pointer_over():
			return rail_signal
	return null


func _panel_lines() -> Array[String]:
	_collect()
	var lines: Array[String] = []
	var hovered := _hovered()
	for rail_signal in _signals:
		lines.append(_describe(rail_signal, rail_signal == hovered))
	return lines


## Everything needed to check a signal is wired up the way the level intended:
## what it is showing, which rail it stands on and where, which direction of
## travel it governs, and who is waiting at it.
func _describe(rail_signal: RailSignal, is_hovered: bool) -> String:
	if not rail_signal.is_usable():
		return "%s %s  <not configured>" % [">" if is_hovered else " ", rail_signal.name]
	var line := "%s %s  %s  on %s @ %.1f m  governs %s" % [
		">" if is_hovered else " ",
		rail_signal.name,
		"CLEAR " if rail_signal.is_clear() else "DANGER",
		rail_signal.rail.name,
		rail_signal.signal_distance(),
		"towards end" if rail_signal.governed_direction() > 0 else "towards start",
	]
	var held := _held_train(rail_signal)
	return line if held.is_empty() else "%s  <- holding %s" % [line, held]


func _held_train(rail_signal: RailSignal) -> String:
	for node in get_tree().get_nodes_in_group(train_group):
		var train := node as Train
		if train != null and train.blocking_signal == rail_signal:
			return str(train.name)
	return ""
