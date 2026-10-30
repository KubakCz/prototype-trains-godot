extends DebugPanel
## Debug keys and a live readout for every [Train] in the level.
##
## The keys act on the selected train - the one last clicked, see
## [method Train.select]. Selecting is gameplay (a left click on a car); driving a
## train by hand is not, so the keys stay here, as physical keycodes, and the
## project's action list stays clean.

## Trains found in this group are listed. Re-read every refresh rather than cached:
## trains come and go as they enter and leave a level.
@export var train_group: StringName = &"trains"

## What [kbd]+[/kbd] couples on to a train that has no wagons to copy.
const _SPARE_WAGON := "res://rolling_stock/coach.tres"

var _trains: Array[Train] = []


func _ready() -> void:
	super._ready()
	_collect_trains()
	if _trains.is_empty():
		push_warning("No trains in group '%s'." % train_group)


func _panel_title() -> String:
	return "Trains"


func _collect_trains() -> void:
	_trains.assign(get_tree().get_nodes_in_group(train_group))


func _panel_key(keycode: Key) -> bool:
	if keycode == KEY_BACKSPACE:
		# Derailing is final, so a wreck would otherwise end the session.
		get_tree().reload_current_scene()
		return true
	var train := Train.selected_train()
	if train == null or train.derailed:
		return false
	match keycode:
		KEY_SPACE:
			# The player's "let go" for a tripped train is the same key as go.
			if train.tripped:
				train.release()
			else:
				train.throttle = 0 if train.throttle != 0 else 1
		KEY_R:
			train.throttle = -1 if train.throttle == 0 else -train.throttle
		KEY_F:
			# Turning a moving train round would flip it under itself.
			if train.current_speed == 0.0:
				train.facing = -train.facing
		KEY_E:
			train.end_behavior = ((train.end_behavior + 1) % Train.EndBehavior.size()) as Train.EndBehavior
		KEY_EQUAL, KEY_KP_ADD:
			var spare: WagonType = (train.wagons[-1] if not train.wagons.is_empty()
					else load(_SPARE_WAGON))
			train.add_wagon(spare)
		KEY_MINUS, KEY_KP_SUBTRACT:
			train.remove_wagon()
		KEY_L:
			train.load_factor = 0.0 if train.load_factor > 0.0 else 1.0
		_:
			return false
	return true


func _panel_controls() -> Array[String]:
	return [
		"stopping strip: %s" % ("on" if Train.show_stopping_strip else "off"),
		"collision boxes: %s" % ("on" if Train.show_collision_boxes else "off"),
	]


func _panel_control_pressed(index: int) -> void:
	match index:
		0:
			Train.show_stopping_strip = not Train.show_stopping_strip
		1:
			Train.show_collision_boxes = not Train.show_collision_boxes


func _panel_lines() -> Array[String]:
	_collect_trains()
	var lines: Array[String] = [
		"click a train to select it" if Train.selected_train() == null
				else "selected: %s" % Train.selected_train().name,
		"[ Space ] stop / go / let go   [ R ] reverse   [ F ] turn round (standing)",
		"[ + ] [ - ] wagon   [ L ] load   [ E ] end behaviour   [ Backspace ] restart",
		"",
	]
	for train in _trains:
		lines.append_array(_describe(train))
	return lines


func _describe(train: Train) -> Array[String]:
	var rail_name: String = str(train.rail.name) if train.rail != null else "<no rail>"
	var rail_length: float = train.rail.rail_length() if train.rail != null else 0.0
	var lines: Array[String] = []
	lines.append("%s %-13s %-9s %s   on %s %.1f / %.1f m  nose %s" % [
		">" if train.is_selected() else " ",
		train.name,
		train.state_name(),
		_describe_motion(train),
		rail_name,
		train.distance,
		rail_length,
		"along rail" if train.facing == Train.ALONG_RAIL else "against rail",
	])
	lines.append("    %s, %.0f m, %.0f t%s   accel %.2f  brake %.2f / %.2f m/s²  stops in %.1f m  end:%s"
			% [_describe_consist(train), train.train_length(), train.total_mass(),
			" (%.0f t carried)" % train.carried_mass() if train.carried_mass() > 0.0 else "",
			train.acceleration_rate(), train.service_brake_rate(), train.full_brake_rate(),
			Train.stopping_distance(train.current_speed, train.service_brake_rate()),
			Train.EndBehavior.keys()[train.end_behavior]])
	# A held train still has its throttle open: it is waiting, not stopped, and
	# goes by itself once the way is clear.
	var blocked := train.blocked_description()
	var ahead := train.ahead_description()
	if not blocked.is_empty():
		lines.append("    <- %s" % blocked)
	elif not ahead.is_empty() and train.braking > 0.0:
		lines.append("    <- braking at %.2f m/s² for %s" % [train.braking, ahead])
	return lines


## The point of the readout: "forward" is about the train's nose, not the rail's
## direction, so a train can be driving forward while its rail distance falls.
func _describe_motion(train: Train) -> String:
	var heading := "forward" if train.moving_direction() > 0 else "backing"
	var rail_direction := "+" if train.moving_direction() * train.facing > 0 else "-"
	return "%5.1f / %.0f m/s %s (rail %s) throttle %+d" % [train.current_speed,
			train.max_speed, heading, rail_direction, train.throttle]


## "passenger locomotive + 2× coach", runs of one type counted.
func _describe_consist(train: Train) -> String:
	var parts: Array[String] = []
	var types: Array[CarType] = []
	for car in train.cars():
		types.append(car.car_type)
	var i := 0
	while i < types.size():
		var run := 1
		while i + run < types.size() and types[i + run] == types[i]:
			run += 1
		parts.append(types[i].label() if run == 1 else "%d× %s" % [run, types[i].label()])
		i += run
	return " + ".join(parts)
