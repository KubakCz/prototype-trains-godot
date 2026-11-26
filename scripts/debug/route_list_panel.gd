class_name RouteListPanel
extends DebugPanel
## The second way a train's route is shown, and the switch between the two: a list of
## trains with their stops, in the order the trains came on to the level. The first way
## is the row of shapes floating over each train ([RouteIcons]); the panel's first row
## picks which one is showing, and the second says whether the list names its stops or
## leaves them as coloured shapes.

var _view: RouteListView


func _panel_title() -> String:
	return "Routes"


func _build_chrome() -> void:
	super._build_chrome()
	_view = RouteListView.new()
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_readout.get_parent().add_child(_view)


func _apply_expanded() -> void:
	super._apply_expanded()
	if _view != null:
		_view.visible = _list_showing()


func _panel_controls() -> Array[String]:
	return [
		"routes shown: %s" % ("over the trains" if RouteIcons.mode == RouteIcons.Mode.ICONS
				else "in the list"),
		"list: %s" % ("icons and names" if _view != null and _view.show_names else "icons only"),
	]


func _panel_control_pressed(index: int) -> void:
	match index:
		0:
			RouteIcons.mode = (RouteIcons.Mode.LIST if RouteIcons.mode == RouteIcons.Mode.ICONS
					else RouteIcons.Mode.ICONS)
		1:
			_view.show_names = not _view.show_names


func _panel_lines() -> Array[String]:
	if RouteIcons.mode == RouteIcons.Mode.ICONS:
		return ["a circle is a station, a square a way off the level;", "the next stop is the front one"]
	return []


func _refresh() -> void:
	super._refresh()
	if _view == null:
		return
	_view.visible = _list_showing()
	if _view.visible:
		var trains: Array[Train] = []
		for node in get_tree().get_nodes_in_group(Train.GROUP):
			var train := node as Train
			if train != null and not train.is_queued_for_deletion():
				trains.append(train)
		_view.show_trains(trains)


func _list_showing() -> bool:
	return expanded and RouteIcons.mode == RouteIcons.Mode.LIST


## The list as it is drawing, for tests.
func view() -> RouteListView:
	return _view
