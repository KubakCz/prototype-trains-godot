class_name DebugPanel
extends PanelContainer
## A collapsible section of the debug HUD: a header you can click and a body of
## text the subclass writes.
##
## The three debug panels had grown to the point where three expanded readouts
## covered a good part of the screen, so every one of them folds down to its
## header. They start folded: a scene opens showing the track, and you open the
## section you are working on.
##
## A subclass supplies a title, the lines of its readout and any cycle rows it
## wants; everything else - the chrome, the fold, the numbering, the refresh -
## lives here. The chrome is built in code rather than authored per scene, which
## is what keeps a panel a single node in the .tscn.

## Folded state. Exported so a level can open a section it is about, but the
## default is folded for every panel in every scene.
@export var expanded: bool = false:
	set(value):
		expanded = value
		_apply_expanded()

## Font size of both the header and the readout, matching the other panels.
const FONT_SIZE: int = 13

var _header: Button
var _controls: VBoxContainer
var _control_buttons: Array[Button] = []
var _readout: Label


func _ready() -> void:
	_build_chrome()
	_apply_expanded()
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


# --- what a subclass fills in -------------------------------------------------


## The name of the section, shown in the header in both states.
func _panel_title() -> String:
	return str(name)


## The body of the readout, one string per line. Only called while expanded.
func _panel_lines() -> Array[String]:
	return []


## A key press that is not this panel's fold key. Return true if it was used,
## which marks the event handled and refreshes the readout.
func _panel_key(_keycode: Key) -> bool:
	return false


## Clickable rows between the header and the readout, one label each, shown only
## while the section is open. A press calls [method _panel_control_pressed] with
## the row's index. Labels rather than callables: the subclass already has a
## method per row, and a plain array keeps the whole thing typed.
func _panel_controls() -> Array[String]:
	return []


## What a press on the row at [param index] of [method _panel_controls] does.
func _panel_control_pressed(_index: int) -> void:
	pass


# --- chrome -------------------------------------------------------------------


func _build_chrome() -> void:
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 6)
	margin.add_child(rows)

	_header = Button.new()
	_header.flat = true
	_header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	# Without this the header joins the GUI focus chain, and Tab - the train
	# panel's select key - would move focus between headers instead.
	_header.focus_mode = Control.FOCUS_NONE
	_header.add_theme_font_size_override("font_size", FONT_SIZE)
	_header.pressed.connect(_on_header_pressed)
	rows.add_child(_header)

	_controls = VBoxContainer.new()
	_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_controls.add_theme_constant_override("separation", 2)
	rows.add_child(_controls)

	_readout = Label.new()
	_readout.add_theme_font_size_override("font_size", FONT_SIZE)
	rows.add_child(_readout)


func _on_header_pressed() -> void:
	expanded = not expanded
	_refresh()


func _apply_expanded() -> void:
	if _readout != null:
		_readout.visible = expanded
	if _controls != null:
		_controls.visible = expanded
	_update_header()


# --- cycle rows ---------------------------------------------------------------


## The buttons as they currently stand, for tests that want to click one.
func control_buttons() -> Array[Button]:
	return _control_buttons


func _refresh_controls() -> void:
	if _controls == null:
		return
	var labels := _panel_controls()
	if labels.size() != _control_buttons.size():
		_rebuild_controls(labels.size())
	for i in labels.size():
		_control_buttons[i].text = labels[i]


func _rebuild_controls(count: int) -> void:
	for button in _control_buttons:
		# Removed as well as freed: `queue_free` alone leaves the old rows in the
		# container until the end of the frame, next to the new ones.
		_controls.remove_child(button)
		button.queue_free()
	_control_buttons.clear()
	for i in count:
		var button := Button.new()
		button.flat = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", FONT_SIZE)
		# A `Button` consumes its click, which is what keeps a press on a cycle
		# row from also reaching the 3D picking behind the panel.
		button.pressed.connect(_on_control_pressed.bind(i))
		_controls.add_child(button)
		_control_buttons.append(button)


func _on_control_pressed(index: int) -> void:
	_panel_control_pressed(index)
	_refresh()


func _update_header() -> void:
	if _header == null:
		return
	var key := fold_key()
	var hint: String = "" if key == KEY_NONE else "   [ %s ]" % OS.get_keycode_string(key)
	_header.text = "%s %s%s" % ["▼" if expanded else "▶", _panel_title(), hint]


## The number key that folds this panel: [kbd]1[/kbd] for the first debug panel
## among its siblings, [kbd]2[/kbd] for the next, and so on. Derived from the
## scene tree rather than authored, so the numbers always read down the column
## and reordering the panels renumbers them.
func fold_key() -> Key:
	var index := _panel_index()
	return KEY_NONE if index < 0 or index > 8 else (KEY_1 + index) as Key


func _panel_index() -> int:
	var parent := get_parent()
	if parent == null:
		return -1
	var index := 0
	for sibling in parent.get_children():
		if sibling == self:
			return index
		if sibling is DebugPanel:
			index += 1
	return -1


# --- input and refresh --------------------------------------------------------


## [method Node._input] rather than [method Node._unhandled_key_input]: the GUI
## layer swallows Tab for focus navigation before an unhandled-key handler sees it.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var keycode := (event as InputEventKey).physical_keycode as Key
	if keycode == fold_key():
		expanded = not expanded
	elif not _panel_key(keycode):
		return
	get_viewport().set_input_as_handled()
	_refresh()


## The body as the panel is currently showing it - empty while folded, which is
## the whole of what folding does to the readout.
func readout_text() -> String:
	return _readout.text if _readout != null and _readout.visible else ""


func _refresh() -> void:
	if _readout == null:
		return
	_update_header()
	if not expanded:
		return
	_refresh_controls()
	_readout.text = "\n".join(_panel_lines())
