extends PanelContainer
## Keyboard driving controls and live readout for every [Train] in the level.
##
## Throwaway scaffolding for step 1: it exists so the rail-following behaviour can
## be poked at without an editor round-trip. Real dispatching happens through
## signals and turnouts, not by driving trains directly.

## Trains found in this group become controllable. Selection order follows the
## scene tree.
@export var train_group: StringName = &"trains"
@export var readout: Label

## Held only for the duration of a refresh or a keypress. Trains come and go as
## they enter and leave a level, so the group is re-read rather than cached; the
## selection is tracked by reference so it survives the list changing under it.
var _trains: Array[Train] = []
var _selected: Train


func _ready() -> void:
	_collect_trains()
	if _trains.is_empty():
		push_warning("No trains in group '%s'." % train_group)
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _collect_trains() -> void:
	_trains.assign(get_tree().get_nodes_in_group(train_group))
	if _selected == null or not _trains.has(_selected):
		_selected = _trains[0] if not _trains.is_empty() else null


## Handled in [method Node._input] rather than [method Node._unhandled_key_input]
## because the GUI layer would otherwise swallow Tab for focus navigation.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	_collect_trains()
	var train := _selected
	if train == null:
		return
	match (event as InputEventKey).physical_keycode:
		KEY_TAB:
			_selected = _trains[(_trains.find(train) + 1) % _trains.size()]
		KEY_SPACE:
			train.throttle = 0 if train.throttle != 0 else 1
		KEY_R:
			train.throttle = -1 if train.throttle == 0 else -train.throttle
		KEY_F:
			train.facing = -train.facing
		KEY_E:
			train.end_behavior = (train.end_behavior + 1) % Train.EndBehavior.size()
		_:
			return
	get_viewport().set_input_as_handled()
	_refresh()


func _refresh() -> void:
	if readout == null:
		return
	_collect_trains()
	var lines: Array[String] = [
		"[ Tab ] select   [ Space ] stop/go   [ R ] reverse",
		"[ F ] turn around   [ E ] end behaviour",
		"RMB orbit   MMB/WASD pan   wheel zoom",
		"",
	]
	for train in _trains:
		lines.append(_describe(train, train == _selected))
	readout.text = "\n".join(lines)


func _describe(train: Train, is_selected: bool) -> String:
	var rail_name: String = str(train.rail.name) if train.rail != null else "<no rail>"
	var rail_length: float = train.rail.rail_length() if train.rail != null else 0.0
	return "%s %s  on %s  %.1f / %.1f m  nose %s  %s  end:%s" % [
		">" if is_selected else " ",
		train.name,
		rail_name,
		train.distance,
		rail_length,
		"along rail" if train.facing == Train.ALONG_RAIL else "against rail",
		_describe_motion(train),
		Train.EndBehavior.keys()[train.end_behavior],
	]


## The point of the readout: "forward" is about the train's nose, not the rail's
## direction, so a train can be driving forward while its rail distance falls.
func _describe_motion(train: Train) -> String:
	if train.throttle == 0:
		return "stopped"
	var rail_direction := "+" if train.throttle * train.facing > 0 else "-"
	var mode := "forward" if train.throttle > 0 else "reversing"
	return "%s %.0f m/s (rail %s)" % [mode, train.speed, rail_direction]
