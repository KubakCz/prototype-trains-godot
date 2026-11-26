class_name SchematicMarkerWidget
extends TrackMarkerWidget
## A marker drawn as a miniature of the track, with a caption under it: what
## [TurnoutWidget] and [CompoundTurnoutWidget] have in common.
##
## The caption is the subject's name in the text colour and its position in the
## accent colour, so the word says what the border and the leader say. A subclass
## draws the miniature into [method _schematic_box] and says what its subject is
## called and what position it is in.

## What is written under the miniature. Still an open question, so the overlay
## cycles it, for single turnouts and assemblies alike.
enum Caption {
	## The miniature alone.
	NO_TEXT,
	TURNOUT_NAME,
	## The position - [code]NORMAL[/code], [code]REVERSE[/code], an assembly's own
	## names - in the accent colour.
	TURNOUT_POSITION,
	## The name, then the position.
	ALL,
}

const _LABEL_HEIGHT := 15.0
const _PADDING := Vector2(9.0, 4.0)

const _COLOR_NORMAL := Color(0.92, 0.93, 0.95)
const _COLOR_REVERSE := Color(1.0, 0.65, 0.08)

var caption := Caption.ALL: set = _set_caption


#region To be overridden
## The subject's name, as the caption writes it.
func _subject_name() -> String:
	return ""


## The subject's position as it stands, as the caption writes it.
func _position_word() -> String:
	return ""


## The miniature, drawn inside [method _schematic_box].
func _draw_schematic() -> void:
	pass
#endregion


func _draw_expanded(accent: Color) -> void:
	_draw_schematic()
	if caption != Caption.NO_TEXT:
		_draw_caption(accent, _position_word())


## The part of the widget the miniature has: all of it, less the caption's line.
func _schematic_box() -> Vector2:
	return Vector2(size.x, size.y if caption == Caption.NO_TEXT else size.y - _LABEL_HEIGHT)


## The expanded size for a miniature [param box] big, with room under it for the
## caption with [param position_word] in it.
func _size_with_caption(box: Vector2, position_word: String) -> Vector2:
	if caption == Caption.NO_TEXT:
		return box
	return Vector2(maxf(_text_width(_caption_for(position_word)) + _PADDING.x * 2.0, box.x),
			box.y + _LABEL_HEIGHT)


## The caption along the bottom edge.
func _draw_caption(accent: Color, position_word: String) -> void:
	var position_text := position_word if _shows_position() else ""
	var whole := _text_width(_caption_for(position_word))
	var at := Vector2((size.x - whole) * 0.5, size.y - _PADDING.y)
	if _shows_name():
		_draw_text(at, _subject_name(), _COLOR_TEXT)
	if not position_text.is_empty():
		at.x += whole - _text_width(position_text)
		_draw_text(at, position_text, accent)


## The whole caption, as [member caption] has it, with [param position_word] as the position.
func _caption_for(position_word: String) -> String:
	return join_caption(_subject_name() if _shows_name() else "",
			position_word if _shows_position() else "")


func _shows_name() -> bool:
	return caption == Caption.TURNOUT_NAME or caption == Caption.ALL


func _shows_position() -> bool:
	return caption == Caption.TURNOUT_POSITION or caption == Caption.ALL


## A caption's two parts on one line, either of them possibly absent.
static func join_caption(name_text: String, position_text: String) -> String:
	if name_text.is_empty() or position_text.is_empty():
		return name_text + position_text
	return "%s  %s" % [name_text, position_text]


func _set_caption(value: Caption) -> void:
	if caption == value:
		return
	caption = value
	_restyle()
