class_name MarkerOverlay
extends Control
## The floating layer: one [TrackMarkerWidget] for every [RailSignal] and every
## [Turnout] in the level, kept from covering each other and collapsed when there
## are too many of them to read.
##
## Signals and turnouts share one overlay rather than having one each, because
## de-cluttering only works if it knows about every widget on screen - two
## separate overlays would each lay its own markers out neatly and then draw them
## on top of the other's.
##
## Two things are still unsettled and so are switchable at runtime rather than
## decided here:
##
## - [member mode] - the four candidate ways of presenting a turnout, inherited
##   from step 2.
## - [member signal_style] and [member collapse_rule] - how a signal's widget is
##   drawn, and what makes a widget collapse to a point. All three collapse rules
##   are implemented; which one a dispatcher actually wants is a question for a
##   camera and a human.

## The four candidate ways of presenting a turnout. Step 2's, unchanged.
enum Mode {
	## The 3D legs alone, and no floating widget.
	LEGS_3D,
	## 3D legs plus a small name/position button.
	LEGS_AND_BADGE,
	## 3D legs plus a miniature of the real layout.
	LEGS_AND_SCHEMATIC,
	## The miniature carrying the whole job, with nothing drawn on the track.
	SCHEMATIC_ONLY,
}

## What makes a widget collapse to a point. Hovering a collapsed widget always
## opens it again, whichever rule is in force.
enum Collapse {
	## Full size up to [member collapse_distance] metres, a dot past it.
	WHEN_FAR,
	## The widget shrinks as the camera pulls back, and collapses once it would
	## be smaller than [member min_scale].
	WITH_DISTANCE,
	## Everything stays expanded whatever the distance; only widgets that cannot
	## be given a clear place on screen collapse.
	WHEN_CROWDED,
}

## How many times a widget may be pushed clear of its neighbours before the
## layout gives up on it. A cluster deeper than this is a crowd, not a layout
## problem.
const _MAX_PUSHES := 24

## How many rounds [constant Collapse.WHEN_CROWDED] gets to work out how much of
## the crowd it can afford to expand. Bounded because a hovered widget refuses to
## collapse, so a round can legitimately make no progress.
const _MAX_COLLAPSE_ROUNDS := 6

@export var camera: Camera3D
## Turnouts in this group get a widget.
@export var turnout_group: StringName = &"turnouts"
## Signals in this group get a widget.
@export var signal_group: StringName = &"signals"
@export var mode := Mode.LEGS_AND_SCHEMATIC: set = _set_mode
@export var signal_style := SignalWidget.Style.ARROW: set = _set_signal_style

@export_group("Collapsing")
@export var collapse_rule := Collapse.WHEN_FAR
## Metres past which [constant Collapse.WHEN_FAR] collapses a widget.
@export var collapse_distance := 120.0
## The camera distance at which [constant Collapse.WITH_DISTANCE] draws a widget
## at full size. Past it the widget shrinks in proportion.
@export var reference_distance := 55.0
## How small [constant Collapse.WITH_DISTANCE] lets a widget get before it
## collapses instead.
@export var min_scale := 0.6

@export_group("Layout")
## Pixels left between two widgets that had to be separated.
@export var widget_gap := 6.0

## Widget per subject - a [Turnout] or a [RailSignal]. Subjects are re-read every
## frame, since a level may add or remove them, but their widgets are kept.
var _widgets: Dictionary[Node, TrackMarkerWidget] = {}


func _ready() -> void:
	# The overlay itself spans the screen but must not swallow clicks; only the
	# widgets are interactive.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	_sync_widgets()
	_apply_styles()
	_layout()


#region Presentation switches
## Steps to the next turnout presentation. Bound to a key by the debug panel.
func cycle_mode() -> void:
	mode = ((mode + 1) % Mode.size()) as Mode


func cycle_signal_style() -> void:
	signal_style = ((signal_style + 1) % SignalWidget.Style.size()) as SignalWidget.Style


func cycle_collapse_rule() -> void:
	collapse_rule = ((collapse_rule + 1) % Collapse.size()) as Collapse


func mode_label() -> String:
	return Mode.keys()[mode]


func signal_style_label() -> String:
	return SignalWidget.Style.keys()[signal_style]


func collapse_label() -> String:
	match collapse_rule:
		Collapse.WHEN_FAR:
			return "WHEN_FAR (past %.0f m)" % collapse_distance
		Collapse.WITH_DISTANCE:
			return "WITH_DISTANCE (full size at %.0f m)" % reference_distance
		_:
			return "WHEN_CROWDED"
#endregion


#region Widgets
## The widget for one [Turnout] or [RailSignal], or null before the overlay has
## caught up with a subject that was just added to the level.
func widget_for(subject: Node) -> TrackMarkerWidget:
	return _widgets.get(subject)


## The [Turnout] or [RailSignal] whose floating widget the pointer is over, or
## null. Only the widget layer is asked - the 3D marker under it answers for
## itself, because a mode that hides the widget still has a clickable model.
func hovered_subject() -> Node:
	for subject in _widgets:
		var widget := _widgets[subject]
		if widget.visible and widget.is_pointer_over():
			return subject
	return null


## Every widget the overlay currently owns, laid out or not.
func widgets() -> Array[TrackMarkerWidget]:
	var found: Array[TrackMarkerWidget] = []
	found.assign(_widgets.values())
	return found


func _sync_widgets() -> void:
	var subjects := _collect_subjects()
	for subject in subjects:
		if not _widgets.has(subject):
			_widgets[subject] = _make_widget(subject)
	for subject in _widgets.keys():
		if subject not in subjects:
			_widgets[subject].queue_free()
			_widgets.erase(subject)


func _collect_subjects() -> Array[Node]:
	var found: Array[Node] = []
	found.assign(get_tree().get_nodes_in_group(turnout_group))
	found.append_array(get_tree().get_nodes_in_group(signal_group))
	return found


func _make_widget(subject: Node) -> TrackMarkerWidget:
	var turnout := subject as Turnout
	var widget: TrackMarkerWidget
	if turnout != null:
		var turnout_widget := TurnoutWidget.new()
		turnout_widget.turnout = turnout
		widget = turnout_widget
	else:
		var signal_widget := SignalWidget.new()
		signal_widget.rail_signal = subject as RailSignal
		widget = signal_widget
	widget.name = "Widget_%s" % subject.name
	widget.camera = camera
	add_child(widget)
	return widget


## Pushes the current presentation onto every widget, and onto the turnouts
## themselves - the 3D legs are the turnout's own draw, not the overlay's.
func _apply_styles() -> void:
	var wants_legs := mode != Mode.SCHEMATIC_ONLY
	var wants_turnout_widget := mode != Mode.LEGS_3D
	for subject in _widgets:
		var turnout := subject as Turnout
		if turnout == null:
			(_widgets[subject] as SignalWidget).style = signal_style
			continue
		turnout.debug_draw = wants_legs
		var widget := _widgets[subject] as TurnoutWidget
		widget.style = (TurnoutWidget.Style.BADGE if mode == Mode.LEGS_AND_BADGE
				else TurnoutWidget.Style.SCHEMATIC)
		widget.suppressed = not wants_turnout_widget
#endregion


#region Layout
func _layout() -> void:
	var viewport := get_viewport_rect().size
	var shown: Array[TrackMarkerWidget] = []
	for subject in _widgets:
		var widget := _widgets[subject]
		if widget.suppressed or not widget.track_camera():
			widget.visible = false
			continue
		widget.visible = true
		shown.append(widget)

	for widget in shown:
		_apply_collapse(widget)
	_arrange(shown, viewport)
	_restack(shown)
	queue_redraw()


func _arrange(shown: Array[TrackMarkerWidget], viewport: Vector2) -> void:
	for _round in _MAX_COLLAPSE_ROUNDS:
		var stuck := _separate(shown, viewport)
		if stuck.is_empty() or collapse_rule != Collapse.WHEN_CROWDED:
			return
		# The rule's whole definition: expand everything that fits, and collapse
		# what could not be given a clear place even after being shifted. One
		# round is not enough - collapsing frees room, and how much it frees
		# decides how many of the rest can stay open.
		for widget in stuck:
			if not widget.is_pointer_over():
				widget.collapsed = true


## Draw order, which for a [Control] is child order: dots, then open badges, then
## whatever the pointer is on.
##
## Collapsed widgets take no part in [method _separate], so a dot may well land
## on top of a badge - and it was doing, hiding the very thing the layout had
## worked to keep readable. The reverse costs nothing: a badge over a dot hides
## only a point the badge is already standing next to. The hovered widget goes
## last because it is the one the player is asking about.
func _restack(shown: Array[TrackMarkerWidget]) -> void:
	var order: Array[TrackMarkerWidget] = []
	for tier in 3:
		for widget in shown:
			if _stack_tier(widget) == tier:
				order.append(widget)
	# Back to front, so each widget lands in a slot the ones after it have already
	# taken. Hidden widgets are left with the low indices; they draw nothing.
	var slot := get_child_count() - 1
	for i in range(order.size() - 1, -1, -1):
		if order[i].get_index() != slot:
			move_child(order[i], slot)
		slot -= 1


func _stack_tier(widget: TrackMarkerWidget) -> int:
	if widget.is_pointer_over():
		return 2
	return 0 if widget.collapsed else 1


func _apply_collapse(widget: TrackMarkerWidget) -> void:
	match collapse_rule:
		Collapse.WHEN_FAR:
			widget.set_widget_scale(1.0)
			widget.collapsed = widget.camera_distance > collapse_distance
		Collapse.WITH_DISTANCE:
			var wanted := clampf(reference_distance / maxf(widget.camera_distance, 1.0),
					0.0, 1.0)
			widget.set_widget_scale(maxf(wanted, min_scale))
			widget.collapsed = wanted < min_scale
		_:
			widget.set_widget_scale(1.0)
			widget.collapsed = false
	# Whatever the rule says, what the mouse is on is readable.
	if widget.is_pointer_over():
		widget.collapsed = false
		widget.set_widget_scale(1.0)


## Stacks overlapping widgets upwards, and reports the ones that ran out of
## screen doing it.
##
## Lowest anchor first, because on a dispatcher's camera the lowest marker on
## screen is usually the nearest one: it keeps the place it asked for and the
## ones behind it climb above it. The leader lines are what stop that reading as
## a scramble - a widget shifted 60 px up the screen still visibly belongs to its
## own signal.
##
## Collapsed widgets take no part in this. A dot is already the answer to "there
## is no room to show this properly", and moving it off its own marker to make
## space for a badge would be losing the one thing it still says: where the
## signal is. So the layout's promise is about the widgets that are readable -
## no two open badges cover each other.
func _separate(widgets: Array[TrackMarkerWidget], viewport: Vector2) -> Array[TrackMarkerWidget]:
	var order: Array[TrackMarkerWidget] = widgets.duplicate()
	order.sort_custom(func(a: TrackMarkerWidget, b: TrackMarkerWidget) -> bool:
			return a.anchor_screen.y > b.anchor_screen.y)
	var placed: Array[Rect2] = []
	var stuck: Array[TrackMarkerWidget] = []
	for widget in order:
		var rect := widget.desired_rect(viewport)
		if widget.collapsed:
			widget.place_at(rect.position)
			continue
		for _push in _MAX_PUSHES:
			var hit := _first_overlap(placed, rect)
			if hit < 0:
				break
			rect.position.y = placed[hit].position.y - rect.size.y - widget_gap
		if rect.position.y < 0.0:
			rect.position.y = 0.0
			stuck.append(widget)
		placed.append(rect)
		widget.place_at(rect.position)
	return stuck


## Index of the first already-placed rect [param rect] would sit too close to,
## or -1. Grown by the gap on both sides, so widgets end up separated rather than
## merely not intersecting.
func _first_overlap(placed: Array[Rect2], rect: Rect2) -> int:
	for i in placed.size():
		if placed[i].grow(widget_gap).intersects(rect):
			return i
	return -1


## Every leader line, drawn by the overlay rather than by the widgets themselves.
## A parent draws before its children, so a line drawn here is behind every badge
## on screen instead of only behind the one it belongs to.
func _draw() -> void:
	for subject in _widgets:
		var widget := _widgets[subject]
		if not widget.visible or not widget.is_alive():
			continue
		draw_line(widget.leader_start(), widget.leader_end(), widget.leader_color(), 1.0)
#endregion


func _set_mode(value: Mode) -> void:
	mode = value
	if is_inside_tree():
		# Legs are the turnout's own draw, so a mode that hides them has to say
		# so immediately rather than waiting for the next frame.
		for subject in _widgets:
			var turnout := subject as Turnout
			if turnout != null:
				turnout.debug_draw = mode != Mode.SCHEMATIC_ONLY


func _set_signal_style(value: SignalWidget.Style) -> void:
	signal_style = value
	if not is_inside_tree():
		return
	for subject in _widgets:
		var widget := _widgets[subject] as SignalWidget
		if widget != null:
			widget.style = value
