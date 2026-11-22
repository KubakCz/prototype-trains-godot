class_name InterestDebugPanel
extends DebugPanel
## Every [InterestPoint] in the level and the [TrainSpawner]'s counts, with the switch
## for the names floating beside the markers.


func _panel_title() -> String:
	return "Stations and connections"


func _panel_controls() -> Array[String]:
	return ["names: %s" % ("on" if InterestPoint.show_names else "off")]


func _panel_control_pressed(index: int) -> void:
	if index == 0:
		InterestPoint.show_names = not InterestPoint.show_names


func _panel_lines() -> Array[String]:
	var lines: Array[String] = []
	for node in get_tree().get_nodes_in_group(TrainSpawner.GROUP):
		var spawner := node as TrainSpawner
		lines.append("trains %d / %d   next spawn in %.0f s   spawned %d  left %d (%d completed)" % [
				spawner.train_count(), spawner.max_trains, spawner.time_to_next_spawn(),
				spawner.spawned_count, spawner.left_count, spawner.completed_count])
	if not lines.is_empty():
		lines.append("")
	for node in get_tree().get_nodes_in_group(InterestPoint.GROUP):
		lines.append(_describe(node as InterestPoint))
	return lines


func _describe(point: InterestPoint) -> String:
	var station := point as Station
	if station != null:
		var cargo: String = Station.Cargo.keys()[station.cargo].to_lower()
		return "O %-16s station, %d track%s, stops %.0f s, cargo %s   %s" % [point.label(),
				point.tracks().size(), "" if point.tracks().size() == 1 else "s",
				station.dwell_time, cargo, point.color().to_html(false)]
	return "[] %-16s connection, %d track%s   %s" % [point.label(), point.tracks().size(),
			"" if point.tracks().size() == 1 else "s", point.color().to_html(false)]
