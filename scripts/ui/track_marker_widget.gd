class_name TrackMarkerWidget
extends Control
## One floating, clickable marker for one thing on the track.
##
## The widget knows how to find itself on screen and how to draw itself. Where it
## actually ends up is [MarkerOverlay]'s decision, because keeping clear of the
## other widgets and collapsing when there are too many to read are questions
## about the set of markers, not about any one of them.
##
## A subclass supplies five things: what it is pointing at, how big it is when
## expanded, what colour it is, what a click does, and how to draw its contents.

## The collapsed dot's drawn size, and the hit area around it. The hit area is
## bigger on purpose: a 12 px dot that has to be hovered to open is a 12 px dot
## nobody can hover.
const COLLAPSED_DIAMETER := 12.0
const COLLAPSED_SIZE := Vector2(20.0, 20.0)
## Gap between the widget's bottom edge and the point it describes. The widget
## floats above its marker rather than over it, so it never hides it.
const STANDOFF := 16.0

const _COLOR_BACKGROUND := Color(0.06, 0.07, 0.09, 0.72)
const _COLOR_TEXT := Color(0.93, 0.94, 0.96)

var camera: Camera3D
## A dot with a leader line instead of the full widget. Set by the overlay, which
## owns the rule; hovering always overrides it.
var collapsed := false: set = _set_collapsed
## Hidden without being laid out - the overlay's turnout modes use this.
var suppressed := false
## Where the thing being described is on screen, refreshed by
## [method track_camera]. What the overlay sorts and stacks by.
var anchor_screen := Vector2.ZERO
## Metres from the camera to the anchor, which is what the collapse rules read.
var camera_distance := 0.0

var _hovered := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# Scaling about the top left keeps `position` the rect's corner, which is
	# what the overlay's layout arithmetic assumes.
	pivot_offset = Vector2.ZERO


func _ready() -> void:
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))
	refresh_size()


#region To be overridden
## The point in the world this widget describes, which is where its leader line
## lands and what it is sorted by.
func marker_anchor() -> Vector3:
	return Vector3.ZERO


## The widget's size when it is not collapsed, in unscaled pixels.
func expanded_size() -> Vector2:
	return Vector2(60.0, 24.0)


## The colour that says what state the thing is in. Used for the border, the
## leader line and the collapsed dot.
func accent_color() -> Color:
	return _COLOR_TEXT


## What a click on the widget does.
func activate() -> void:
	pass


## False once the thing being described has gone, so the overlay can drop the
## widget without the draw code having to check for nulls.
func is_alive() -> bool:
	return false


## The widget's contents, drawn inside the frame in unscaled coordinates.
func _draw_expanded(_accent: Color) -> void:
	pass


## The widget's outline. A subclass overrides this when its shape carries meaning
## rather than just holding the contents.
func _draw_frame(accent: Color) -> void:
	var background := _COLOR_BACKGROUND
	if _hovered:
		background = background.lightened(0.3)
	draw_rect(Rect2(Vector2.ZERO, size), background)
	draw_rect(Rect2(Vector2.ZERO, size), accent, false, 1.0)


## What a collapsed widget is. A dot by default.
func _draw_collapsed(accent: Color) -> void:
	var centre := size * 0.5
	draw_circle(centre, COLLAPSED_DIAMETER * 0.5, accent)
	draw_circle(centre, COLLAPSED_DIAMETER * 0.5, _COLOR_BACKGROUND.lightened(0.2), false, 1.5)
#endregion


#region Layout, driven by the overlay
## Refreshes [member anchor_screen] and [member camera_distance]. Returns false
## when the marker is behind the camera or off screen, in which case the overlay
## hides the widget rather than laying it out.
func track_camera() -> bool:
	if camera == null or not camera.is_inside_tree() or not is_alive():
		_hovered = false
		return false
	var anchor := marker_anchor()
	if camera.is_position_behind(anchor):
		_hovered = false
		return false
	anchor_screen = camera.unproject_position(anchor)
	camera_distance = camera.global_position.distance_to(anchor)
	if not Rect2(Vector2.ZERO, get_viewport_rect().size).has_point(anchor_screen):
		_hovered = false
		return false
	return true


## Where the widget would sit if nothing else were on screen: centred above its
## marker, kept inside the viewport.
func desired_rect(viewport: Vector2) -> Rect2:
	var extent := size * scale
	var top_left := anchor_screen - Vector2(extent.x * 0.5, extent.y + STANDOFF)
	return Rect2(top_left.clamp(Vector2.ZERO, Vector2(
			maxf(viewport.x - extent.x, 0.0), maxf(viewport.y - extent.y, 0.0))), extent)


func place_at(top_left: Vector2) -> void:
	position = top_left
	queue_redraw()


## Where the leader line leaves the widget, in the overlay's coordinates: the
## bottom edge when the widget is open, the dot's own centre when it is not.
##
## The line is drawn by [MarkerOverlay] and not here, because a line drawn by the
## widget is drawn *with* the widget - it would cross over any badge that happens
## to sit between this widget and its marker. The overlay draws before its
## children, so a line drawn there is behind every badge on screen.
func leader_start() -> Vector2:
	var local: Vector2 = size * 0.5 if collapsed else Vector2(size.x * 0.5, size.y)
	return position + local * scale


## Where the leader line lands: the marker it describes.
func leader_end() -> Vector2:
	return anchor_screen


func leader_color() -> Color:
	return accent_color() * Color(1.0, 1.0, 1.0, 0.7)


func set_widget_scale(value: float) -> void:
	var wanted := Vector2(value, value)
	if scale != wanted:
		scale = wanted


func is_pointer_over() -> bool:
	return _hovered


func refresh_size() -> void:
	if not is_inside_tree():
		return
	size = COLLAPSED_SIZE if collapsed else expanded_size()
#endregion


func _gui_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"interact"):
		return
	# Consumed here, so the click does not also reach the 3D collider underneath
	# and undo what the widget just did.
	accept_event()
	if is_alive():
		activate()
		queue_redraw()


func _draw() -> void:
	if not is_alive():
		return
	var accent := accent_color()
	if collapsed:
		_draw_collapsed(accent)
		return
	_draw_frame(accent)
	_draw_expanded(accent)


func _set_collapsed(value: bool) -> void:
	if collapsed == value:
		return
	collapsed = value
	refresh_size()
	queue_redraw()


func _on_hover(entered: bool) -> void:
	_hovered = entered
	queue_redraw()
