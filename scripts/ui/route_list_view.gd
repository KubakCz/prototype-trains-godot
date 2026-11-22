class_name RouteListView
extends Control
## The route list's body: one line per train, in the order the trains came on to the
## level - a swatch in the train's livery, its name, and a circle or square in the colour
## of each stop still to come, the next one first. Drawn rather than written out, because
## a coloured shape is the point and the debug font has none.
##
## [RouteListPanel] owns it and hands it the trains every frame.

const ROW_HEIGHT := 22.0
const SWATCH_SIZE := Vector2(30.0, 14.0)
const ICON_SIZE := 14.0
const GAP := 8.0
const NAME_WIDTH := 108.0
const FONT_SIZE := 13
const _OUTLINE := Color(1.0, 1.0, 1.0, 0.55)
const _TEXT := Color(0.92, 0.92, 0.92)

## Write each stop's name beside its shape, for telling similar colours apart.
var show_names := false

var _rows: Array[Train] = []


## Lists [param trains], sorted by arrival.
func show_trains(trains: Array[Train]) -> void:
	_rows = trains.duplicate()
	_rows.sort_custom(func(a: Train, b: Train) -> bool: return a.arrival_index < b.arrival_index)
	custom_minimum_size = Vector2(_width(), maxf(float(_rows.size()), 1.0) * ROW_HEIGHT)
	queue_redraw()


func row_count() -> int:
	return _rows.size()


## The trains as listed, top to bottom.
func rows() -> Array[Train]:
	return _rows


func _width() -> float:
	var widest := 0.0
	for train in _rows:
		var width := SWATCH_SIZE.x + GAP + NAME_WIDTH
		for point in train.remaining_stops():
			width += GAP + ICON_SIZE
			if show_names:
				width += _text_width(point.label()) + 2.0
		widest = maxf(widest, width)
	return widest


func _text_width(text: String) -> float:
	return ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			FONT_SIZE).x


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for i in _rows.size():
		var train := _rows[i]
		if not is_instance_valid(train):
			continue
		var middle := (float(i) + 0.5) * ROW_HEIGHT
		var x := 0.0
		_draw_swatch(train, Vector2(x, middle - SWATCH_SIZE.y * 0.5))
		x += SWATCH_SIZE.x + GAP
		var label := "%s%s" % [">" if train.is_selected() else "", train.name]
		draw_string(font, Vector2(x, middle + FONT_SIZE * 0.35), label,
				HORIZONTAL_ALIGNMENT_LEFT, NAME_WIDTH, FONT_SIZE, _TEXT)
		x += NAME_WIDTH
		for point in train.remaining_stops():
			x += GAP
			_draw_stop(point, Vector2(x, middle - ICON_SIZE * 0.5))
			x += ICON_SIZE
			if show_names:
				draw_string(font, Vector2(x + 3.0, middle + FONT_SIZE * 0.35), point.label(),
						HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE, _TEXT)
				x += _text_width(point.label()) + 2.0


## The engine's colour, with its stripe across the middle if it has one.
func _draw_swatch(train: Train, at: Vector2) -> void:
	var rect := Rect2(at, SWATCH_SIZE)
	var livery := train.livery
	draw_rect(rect, livery.body if livery != null else train.body_color())
	if livery != null and livery.striped:
		var band := SWATCH_SIZE.y * 0.34
		draw_rect(Rect2(at + Vector2(0.0, (SWATCH_SIZE.y - band) * 0.5),
				Vector2(SWATCH_SIZE.x, band)), livery.stripe)
	draw_rect(rect, _OUTLINE, false, 1.0)


func _draw_stop(point: InterestPoint, at: Vector2) -> void:
	if point.is_square():
		var rect := Rect2(at, Vector2.ONE * ICON_SIZE)
		draw_rect(rect, point.color())
		draw_rect(rect, _OUTLINE, false, 1.0)
	else:
		var centre := at + Vector2.ONE * ICON_SIZE * 0.5
		draw_circle(centre, ICON_SIZE * 0.5, point.color())
		draw_arc(centre, ICON_SIZE * 0.5, 0.0, TAU, 20, _OUTLINE, 1.0)
