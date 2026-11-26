@tool
class_name InterestPoint
extends Node3D
## Somewhere trains are going: a [Station] or an [OutsideConnection]. It spans one
## or more tracks - its [InterestTrack] children - and is marked by a badge floating
## over the middle of them, with a pole down to each: a pill for a station, a box for
## a connection, in the point's own colour, with its name inside. The poles are drawn
## here, in 3D; the badge is an [InterestPointWidget] on the floating marker layer, so
## that it is sized like the rest of the interface and scales with it.
##
## The colour is picked for the whole level at once: every point that does not set
## its own gets a hue spread as far from the others as the number of points allows
## ([method assign_colors]). A point that does set one - to make a level's entry, its
## station and its exit three tints of green, say - is left out of that.
##
## Routes ([TrainRoute]) are lists of these, and a train's route is a list of them
## too. The nodes themselves only say where they are and what they look like; what
## happens to a train there is [Train]'s and [TrainSpawner]'s business.

## Every point joins this group, in the editor too.
const GROUP := &"interest_points"

## How high the badge floats over the tracks: where the poles meet.
const MARKER_HEIGHT := 14.0

const _SATURATION := 0.78
const _VALUE := 0.95

## The names inside the badges; without them a badge is a bare circle or square.
## A debug option, switched from the interest point panel.
static var show_names := true
static var _colors_pending := false
static var _line_material: StandardMaterial3D

## What the readouts and the label call it. The node's name when empty.
@export var display_name := ""
## Set the colour by hand instead of having one picked.
@export var use_custom_color := false:
	set(value):
		use_custom_color = value
		_refresh_colors()
		# Takes this point out of the spread, or puts it back in.
		_request_colors()
@export var custom_color := Color(0.2, 0.75, 0.3):
	set(value):
		custom_color = value
		_refresh_colors()

var _auto_color := Color.WHITE
var _marker: Node3D
var _lines: MeshInstance3D
var _anchor := Vector3.INF


func _enter_tree() -> void:
	add_to_group(GROUP)
	_request_colors()


func _exit_tree() -> void:
	remove_from_group(GROUP)
	_request_colors()


func _ready() -> void:
	child_order_changed.connect(refresh)
	refresh()


func _process(_delta: float) -> void:
	# A rail dragged in the editor takes the marker with it. At runtime nothing
	# under it moves.
	if Engine.is_editor_hint():
		refresh()


## A circle or a square? The one thing a station's badge and a connection's draw
## differently.
func is_square() -> bool:
	return false


func label() -> String:
	return display_name if not display_name.is_empty() else str(name)


## The tracks this point spans, in scene order.
func tracks() -> Array[InterestTrack]:
	var found: Array[InterestTrack] = []
	for child in get_children():
		var track := child as InterestTrack
		if track != null and track.rail != null:
			found.append(track)
	return found


## The colour the marker shows: the one set by hand, or the one picked.
func color() -> Color:
	return custom_color if use_custom_color else _auto_color


## The middle of the tracks' marks, in the world. The origin with no usable track.
func anchor() -> Vector3:
	var total := Vector3.ZERO
	var count := 0
	for track in tracks():
		if track.is_usable():
			total += track.position()
			count += 1
	return total / float(count) if count > 0 else Vector3.ZERO


#region Colours
## Hands every point that has not set its own colour a hue of its own, spread
## around the wheel as far apart as their number allows, and ordered so that points
## listed next to each other in the scene - the ones most likely to be near each
## other - get hues far apart. Run once for the whole level a frame after anything
## enters or leaves; a level's points never have to be told about each other.
static func assign_colors(tree: SceneTree) -> void:
	_colors_pending = false
	if tree == null:
		return
	var picking: Array[InterestPoint] = []
	for node in tree.get_nodes_in_group(GROUP):
		var point := node as InterestPoint
		if point != null and not point.use_custom_color:
			picking.append(point)
	var hues := auto_hues(picking.size())
	for i in picking.size():
		picking[i]._set_auto_color(Color.from_hsv(hues[i], _SATURATION, _VALUE))


## [param count] hues, evenly spread round the wheel, in an order that puts each one as
## far from the one before as the unused ones allow, so that points listed next to each
## other - the ones most likely to be near each other - are easy to tell apart.
static func auto_hues(count: int) -> PackedFloat64Array:
	var hues := PackedFloat64Array()
	if count <= 0:
		return hues
	var unused: Array[int] = []
	for slot in range(1, count):
		unused.append(slot)
	var slot := 0
	hues.append(0.0)
	while not unused.is_empty():
		var best := unused[0]
		var best_gap := -1
		for candidate in unused:
			var apart := absi(candidate - slot)
			apart = mini(apart, count - apart)
			if apart > best_gap:
				best = candidate
				best_gap = apart
		unused.erase(best)
		slot = best
		hues.append(float(slot) / float(count))
	return hues


func _request_colors() -> void:
	if _colors_pending or not is_inside_tree():
		return
	_colors_pending = true
	assign_colors.call_deferred(get_tree())


func _set_auto_color(value: Color) -> void:
	_auto_color = value
	_refresh_colors()


## The colour changed. The badge reads it every frame; a subclass with something of
## its own in the point's colour repaints it here.
func _refresh_colors() -> void:
	pass
#endregion


#region Marker
## Builds or moves the marker to match the tracks. Cheap when nothing moved.
func refresh() -> void:
	if not is_inside_tree():
		return
	var middle := anchor()
	var marks: Array[Vector3] = []
	for track in tracks():
		marks.append(track.position())
	var signature := middle + Vector3(float(marks.size()), 0.0, 0.0)
	if _marker != null and signature.is_equal_approx(_anchor):
		return
	_anchor = signature
	_ensure_marker()
	_marker.global_position = middle + Vector3.UP * MARKER_HEIGHT
	_rebuild_lines(middle, marks)
	place_scenery()
	update_configuration_warnings()


## The tracks under the point moved or changed, or the point entered the tree. A
## subclass with something standing by its tracks places it again here.
func place_scenery() -> void:
	pass


func _ensure_marker() -> void:
	if _marker != null:
		return
	_marker = Node3D.new()
	_marker.name = "Marker"
	_marker.top_level = true
	add_child(_marker, false, Node.INTERNAL_MODE_BACK)
	_lines = MeshInstance3D.new()
	_lines.name = "Poles"
	_lines.top_level = true
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lines.material_override = _get_line_material()
	_marker.add_child(_lines)


func _rebuild_lines(middle: Vector3, marks: Array[Vector3]) -> void:
	var mesh := ImmediateMesh.new()
	_lines.global_transform = Transform3D.IDENTITY
	_lines.mesh = mesh
	if marks.is_empty():
		return
	var top := middle + Vector3.UP * MARKER_HEIGHT
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for mark in marks:
		mesh.surface_add_vertex(top)
		mesh.surface_add_vertex(mark)
	mesh.surface_end()


static func _get_line_material() -> StandardMaterial3D:
	if _line_material == null:
		_line_material = StandardMaterial3D.new()
		_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_line_material.albedo_color = Color(1.0, 1.0, 1.0, 0.7)
		_line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return _line_material
#endregion


func marker_position() -> Vector3:
	return _marker.global_position if _marker != null else Vector3.ZERO


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if tracks().is_empty():
		warnings.append("No tracks: add an InterestTrack child for each track this point spans.")
	return warnings
