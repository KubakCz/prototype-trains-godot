class_name TurnoutOverlay
extends Control
## Keeps a floating [TurnoutWidget] over every [Turnout] in the level, and owns
## which of the four ways of presenting a turnout is currently in use.
##
## There is no obvious right answer to how a turnout should be shown, so all four
## candidates are here and the debug panel cycles them:
##
## - [constant Mode.LEGS_3D] - the 3D legs alone. The turnout is only clickable
##   on its own model, which is honest but fiddly from a zoomed-out camera.
## - [constant Mode.LEGS_AND_BADGE] - 3D legs plus a small name/position button,
##   which is the cheapest way to guarantee a click target.
## - [constant Mode.LEGS_AND_SCHEMATIC] - 3D legs plus a miniature of the real
##   layout.
## - [constant Mode.SCHEMATIC_ONLY] - the miniature carrying the whole job, with
##   no overlay on the track at all.
##
## Debug scaffolding: step 3 has to solve the same problem properly for signals,
## which need collapsing, de-overlapping and a visible direction.

enum Mode {
	LEGS_3D,
	LEGS_AND_BADGE,
	LEGS_AND_SCHEMATIC,
	SCHEMATIC_ONLY,
}

@export var camera: Camera3D
## Turnouts in this group get a widget.
@export var turnout_group: StringName = &"turnouts"
@export var mode := Mode.LEGS_AND_SCHEMATIC: set = _set_mode

## Widget per turnout. Turnouts are re-read every frame, since a level may add or
## remove them, but their widgets are kept.
var _widgets: Dictionary[Turnout, TurnoutWidget] = {}


func _ready() -> void:
	# The overlay itself spans the screen but must not swallow clicks; only the
	# widgets are interactive.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	var turnouts := _collect_turnouts()
	for turnout in turnouts:
		if not _widgets.has(turnout):
			_widgets[turnout] = _make_widget(turnout)
	for turnout in _widgets.keys():
		if turnout not in turnouts:
			_widgets[turnout].queue_free()
			_widgets.erase(turnout)

	var wants_legs := mode != Mode.SCHEMATIC_ONLY
	var wants_widget := mode != Mode.LEGS_3D
	for turnout in turnouts:
		turnout.debug_draw = wants_legs
		var widget := _widgets[turnout]
		widget.style = (TurnoutWidget.Style.BADGE if mode == Mode.LEGS_AND_BADGE
				else TurnoutWidget.Style.SCHEMATIC)
		widget.visible = wants_widget and widget.follow_camera()


## Steps to the next presentation. Bound to a key by the debug panel.
func cycle_mode() -> void:
	mode = ((mode + 1) % Mode.size()) as Mode


func mode_label() -> String:
	return Mode.keys()[mode]


func _collect_turnouts() -> Array[Turnout]:
	var found: Array[Turnout] = []
	found.assign(get_tree().get_nodes_in_group(turnout_group))
	return found


func _make_widget(turnout: Turnout) -> TurnoutWidget:
	var widget := TurnoutWidget.new()
	widget.name = "Widget_%s" % turnout.name
	widget.turnout = turnout
	widget.camera = camera
	add_child(widget)
	return widget


func _set_mode(value: Mode) -> void:
	mode = value
	if is_inside_tree():
		# Legs are the turnout's own draw, so a mode that hides them has to say
		# so immediately rather than waiting for the next frame.
		for turnout in _widgets:
			turnout.debug_draw = mode != Mode.SCHEMATIC_ONLY
