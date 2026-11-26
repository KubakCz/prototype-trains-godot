extends RefCounted
## What the scene generators under tools/ share: the turtle that draws a rail, its
## [Curve3D], the carving rules, and the [code].tscn[/code] text every generated level
## writes the same way.
##
## No class_name, so it never enters the global class cache: load it with
## [code]const Kit := preload("res://tools/scene_kit.gd")[/code].


#region Carving
## Carving, as on the desert level: a flat bed either side of the centre line, cuttings at
## 1:1 and banks at 1:1.6 beyond it. Ground this far over the railhead is a tunnel and is
## kept a roof's height above it; ground this far under the bed is a bridge and is left be.
const BED_HALF_WIDTH := 3.0
const CUT_SLOPE := 1.0
const BANK_SLOPE := 1.6
const TUNNEL_COVER := 7.0
const TUNNEL_ROOF := 6.5
const BRIDGE_DROP := 1.5

enum Kind { TRACK, TUNNEL, BRIDGE }


## What the track needs of the ground where it stands on [param natural] ground.
static func kind(natural: float, railhead: float, bed_depth: float) -> Kind:
	if natural > railhead + TUNNEL_COVER:
		return Kind.TUNNEL
	if natural < railhead - bed_depth - BRIDGE_DROP:
		return Kind.BRIDGE
	return Kind.TRACK


## The highest the ground may stand [param gap] metres from track of [param kind] whose
## railhead is at [param railhead]: the cutting. [constant INF] where nothing limits it.
static func cut_limit(kind: Kind, gap: float, railhead: float, bed_depth: float) -> float:
	if kind == Kind.TUNNEL:
		return INF
	return railhead - bed_depth + maxf(gap - BED_HALF_WIDTH, 0.0) * CUT_SLOPE


## The lowest it may lie: the bank under ordinary track, the roof over a tunnel.
## [code]-INF[/code] where nothing limits it - on a bridge, the gully is left be.
static func fill_limit(kind: Kind, gap: float, railhead: float, bed_depth: float) -> float:
	match kind:
		Kind.TRACK:
			return railhead - bed_depth - maxf(gap - BED_HALF_WIDTH, 0.0) / BANK_SLOPE
		Kind.TUNNEL:
			if gap < BED_HALF_WIDTH + 1.0:
				return railhead + TUNNEL_ROOF
	return -INF
#endregion


#region Rails
## A rail drawn as a turtle walk in plan: a list of poses, each a point and the heading
## the track has there in degrees clockwise from +X seen from above - 0 is east, 90 is
## south. Consecutive poses become one cubic segment of the curve.
class Track:
	var points: Array[Vector2] = []
	var headings: Array[float] = []

	func _init(start: Vector2, toward: float) -> void:
		points.append(start)
		headings.append(toward)


	func position() -> Vector2:
		return points[-1]


	func heading() -> float:
		return headings[-1]


	func line(length: float) -> Track:
		return to(position() + direction(heading()) * length, heading())


	## Straight on until x reaches [param x].
	func line_to_x(x: float) -> Track:
		return line((x - position().x) / direction(heading()).x)


	## Straight on until z reaches [param z].
	func line_to_z(z: float) -> Track:
		return line((z - position().y) / direction(heading()).y)


	## Right for positive [param degrees], left for negative. Split into steps of at most
	## 45 degrees, which a cubic follows to within a few millimetres.
	func arc(radius: float, degrees: float) -> Track:
		var steps := maxi(1, ceili(absf(degrees) / 45.0 - 1e-6))
		var step := degrees / float(steps)
		for _i in steps:
			var centre := position() + direction(heading() + 90.0 * signf(degrees)) * radius
			var arm := (position() - centre).rotated(deg_to_rad(step))
			to(centre + arm, heading() + step)
		return self


	## Any pose at all, joined to the last by a cubic leaving and arriving along the two
	## headings - an S-bend when they are parallel.
	func to(point: Vector2, toward: float) -> Track:
		points.append(point)
		headings.append(toward)
		return self


	## The same walk moved [param by] metres to the right of itself everywhere:
	## concentric arcs, parallel straights.
	func offset(by: float) -> Track:
		var moved := Track.new(points[0] + direction(headings[0] + 90.0) * by, headings[0])
		for i in range(1, points.size()):
			moved.to(points[i] + direction(headings[i] + 90.0) * by, headings[i])
		return moved


	static func direction(degrees: float) -> Vector2:
		return Vector2.from_angle(deg_to_rad(degrees))


## A point in plan at [param railhead], moved by [param shift].
static func world(point: Vector2, railhead: float, shift := Vector2.ZERO) -> Vector3:
	return Vector3(point.x + shift.x, railhead, point.y + shift.y)


## The track as a [Curve3D]: one point per pose, with handles along the headings. A
## segment between two poses on an arc gets the handles that make it follow the arc;
## a straight or an S-bend gets a third of its chord.
static func curve(track: Track, railhead: float, shift := Vector2.ZERO) -> Curve3D:
	var result := Curve3D.new()
	for point in track.points:
		result.add_point(world(point, railhead, shift))
	for i in track.points.size() - 1:
		var chord := track.points[i].distance_to(track.points[i + 1])
		var turn := deg_to_rad(absf(wrapf(track.headings[i + 1] - track.headings[i],
				-180.0, 180.0)))
		var handle := chord / 3.0
		if turn > 1e-4:
			handle = chord * 2.0 / 3.0 * tan(turn / 4.0) / sin(turn / 2.0)
		var out := Track.direction(track.headings[i]) * handle
		var back := Track.direction(track.headings[i + 1]) * -handle
		result.set_point_out(i, Vector3(out.x, 0.0, out.y))
		result.set_point_in(i + 1, Vector3(back.x, 0.0, back.y))
	return result


## Every turnout, compound members included, loose ones first.
static func all_turnouts(turnouts: Array[Dictionary],
		compounds: Array[Dictionary]) -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	all.append_array(turnouts)
	for compound in compounds:
		for member: Dictionary in compound["members"]:
			all.append(member)
	return all
#endregion


#region Writing
## Saves the baked heightmap; false, with the error pushed, if it could not.
static func save_heights(heights: Image, path: String) -> bool:
	var error := ResourceSaver.save(heights, path)
	if error != OK:
		push_error("Could not save %s: %s" % [path, error_string(error)])
		return false
	return true


## Writes the scene text; false, with the error pushed, if it could not.
static func write_scene(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write %s" % path)
		return false
	file.store_string(text)
	file.close()
	return true
#endregion


#region Scene text
## Four decimals, no trailing zeros, and no negative zero.
static func num(value: float) -> String:
	if absf(value) < 5e-5:
		return "0"
	return String.num(value, 4)


## [method num] for a float; an int is written as it is, without the [code].0[/code]
## [method num] would give it.
static func _value(value: Variant) -> String:
	if value is int:
		return str(value)
	return num(value)


## An empty [Node3D] under the root, to hold one kind of thing.
static func group(name: String) -> PackedStringArray:
	return PackedStringArray(['[node name="%s" type="Node3D" parent="."]' % name, ""])


## The sky every level is lit by.
static func environment_text() -> PackedStringArray:
	return PackedStringArray([
		'[sub_resource type="ProceduralSkyMaterial" id="ProceduralSkyMaterial_1"]',
		"sky_horizon_color = Color(0.66, 0.7, 0.74, 1)",
		"ground_bottom_color = Color(0.22, 0.24, 0.24, 1)",
		"ground_horizon_color = Color(0.66, 0.7, 0.74, 1)",
		"",
		'[sub_resource type="Sky" id="Sky_1"]',
		'sky_material = SubResource("ProceduralSkyMaterial_1")',
		"",
		'[sub_resource type="Environment" id="Environment_1"]',
		"background_mode = 2",
		'sky = SubResource("Sky_1")',
		"tonemap_mode = 2",
		"ssao_enabled = true",
		"",
	])


## The WorldEnvironment using [method environment_text], and the sun; only how far
## out it casts shadows changes with the size of the level.
static func world_environment_and_sun_text(shadow_distance: float) -> PackedStringArray:
	return PackedStringArray([
		'[node name="WorldEnvironment" type="WorldEnvironment" parent="."]',
		'environment = SubResource("Environment_1")',
		"",
		'[node name="Sun" type="DirectionalLight3D" parent="."]',
		"transform = Transform3D(0.6452, -0.628, 0.4352, 0, 0.5696, 0.822, -0.764, "
				+ "-0.5303, 0.3675, 0, 60, 0)",
		"light_energy = 1.3",
		"shadow_enabled = true",
		"directional_shadow_max_distance = %.1f" % shadow_distance,
		"",
	])


## A [Ground] shaped by a baked heightmap.
static func heightmap_ground_text(ground_script: String, size: Vector2,
		heights: String) -> PackedStringArray:
	return PackedStringArray([
		'[node name="Ground" type="MeshInstance3D" parent="." groups=["snap_surface"]]',
		'script = ExtResource("%s")' % ground_script,
		"size = Vector2(%s, %s)" % [num(size.x), num(size.y)],
		'heightmap = ExtResource("%s")' % heights,
		"low_color = Color(0.27, 0.4, 0.21, 1)",
		"high_color = Color(0.4, 0.52, 0.28, 1)",
		"steep_color = Color(0.46, 0.4, 0.3, 1)",
		"steep_amount = 0.8",
		"",
	])


## [code]in[/code], [code]out[/code], [code]position[/code] per point, handles relative
## to their point - see .claude/rules/tscn.md.
static func curve_text(rail: String, rail_curve: Curve3D) -> PackedStringArray:
	var numbers := PackedStringArray()
	var tilts := PackedStringArray()
	for i in rail_curve.point_count:
		for v: Vector3 in [rail_curve.get_point_in(i), rail_curve.get_point_out(i),
				rail_curve.get_point_position(i)]:
			numbers.append_array([num(v.x), num(v.y), num(v.z)])
		tilts.append("0")
	return PackedStringArray([
		'[sub_resource type="Curve3D" id="Curve3D_%s"]' % rail,
		"_data = {",
		'"points": PackedVector3Array(%s),' % ", ".join(numbers),
		'"tilts": PackedFloat32Array(%s)' % ", ".join(tilts),
		"}",
		"point_count = %d" % rail_curve.point_count,
		"",
	])


## The Rails group, one rail per name, each on the curve [method curve_text] wrote for
## it. [param surface_offset] is left out of the scene where it is NAN.
static func rails_text(rails: Array[String], rail_script: String,
		surface_offset := NAN) -> PackedStringArray:
	var lines := group("Rails")
	for rail in rails:
		lines.append('[node name="%s" type="Path3D" parent="Rails" ' % rail
				+ 'node_paths=PackedStringArray("surface_root")]')
		lines.append('curve = SubResource("Curve3D_%s")' % rail)
		lines.append('script = ExtResource("%s")' % rail_script)
		lines.append('surface_root = NodePath("../../Ground")')
		if not is_nan(surface_offset):
			lines.append("surface_offset = %s" % num(surface_offset))
		lines.append("snap_on_ready = false")
		lines.append("")
	return lines


## One turnout: name, parent, main, distance, diverge, branch, end.
static func turnout_text(turnout: Dictionary, turnout_script: String) -> PackedStringArray:
	var parent: String = turnout["parent"]
	var up := "../".repeat(parent.count("/") + 2)
	return PackedStringArray([
		'[node name="%s" type="Node3D" parent="%s" groups=["turnouts"] ' % [turnout["name"],
				parent] + 'node_paths=PackedStringArray("main_rail", "branch_rail")]',
		'script = ExtResource("%s")' % turnout_script,
		'main_rail = NodePath("%sRails/%s")' % [up, turnout["main"]],
		"main_distance = %s" % num(turnout["distance"]),
		"diverge_towards = %d" % turnout["diverge"],
		'branch_rail = NodePath("%sRails/%s")' % [up, turnout["branch"]],
		"branch_end = %d" % turnout["end"],
		"",
	])


## The Turnouts group, then the Compounds group: each assembly (name, kind, members)
## followed by its member turnouts.
static func turnouts_text(turnouts: Array[Dictionary], compounds: Array[Dictionary],
		turnout_script: String, compound_script: String) -> PackedStringArray:
	var lines := group("Turnouts")
	for turnout in turnouts:
		lines.append_array(turnout_text(turnout, turnout_script))
	lines.append_array(group("Compounds"))
	for compound in compounds:
		var paths := PackedStringArray()
		for member: Dictionary in compound["members"]:
			paths.append('NodePath("%s")' % member["name"])
		lines.append('[node name="%s" type="Node3D" parent="Compounds" ' % compound["name"]
				+ 'groups=["compound_turnouts"] node_paths=PackedStringArray("members")]')
		lines.append('script = ExtResource("%s")' % compound_script)
		lines.append("kind = %d" % compound["kind"])
		lines.append("members = [%s]" % ", ".join(paths))
		lines.append("")
		for member: Dictionary in compound["members"]:
			lines.append_array(turnout_text(member, turnout_script))
	return lines


## The Crossings group: name, a, distance_a, b, distance_b each.
static func crossings_text(crossings: Array[Dictionary],
		crossing_script: String) -> PackedStringArray:
	var lines := group("Crossings")
	for crossing in crossings:
		lines.append('[node name="%s" type="Node3D" parent="Crossings" groups=["crossings"] '
				% crossing["name"] + 'node_paths=PackedStringArray("rail_a", "rail_b")]')
		lines.append('script = ExtResource("%s")' % crossing_script)
		lines.append('rail_a = NodePath("../../Rails/%s")' % crossing["a"])
		lines.append("distance_a = %s" % num(crossing["distance_a"]))
		lines.append('rail_b = NodePath("../../Rails/%s")' % crossing["b"])
		lines.append("distance_b = %s" % num(crossing["distance_b"]))
		lines.append("")
	return lines


## The Signals group: name, rail, distance, governs each.
static func signals_text(signals: Array[Dictionary], signal_script: String) -> PackedStringArray:
	var lines := group("Signals")
	for rail_signal in signals:
		lines.append('[node name="%s" type="Node3D" parent="Signals" groups=["signals"] '
				% rail_signal["name"] + 'node_paths=PackedStringArray("rail")]')
		lines.append('script = ExtResource("%s")' % signal_script)
		lines.append('rail = NodePath("../../Rails/%s")' % rail_signal["rail"])
		lines.append("distance = %s" % num(rail_signal["distance"]))
		lines.append("governs = %d" % rail_signal["governs"])
		lines.append("")
	return lines


## The Trains group: name, rail, distance, facing, speed, end, locomotive, wagons and
## load each (distance and speed through [method _value]), the rolling stock named by
## its key in [param stock] - [code]key: [path, id][/code]. The wagons are typed by
## [param wagon_type_script]: see .claude/rules/tscn.md.
static func trains_text(trains: Array[Dictionary], train_script: String,
		wagon_type_script: String, stock: Dictionary) -> PackedStringArray:
	var lines := group("Trains")
	for train in trains:
		lines.append('[node name="%s" type="Node3D" parent="Trains" groups=["trains"] '
				% train["name"] + 'node_paths=PackedStringArray("rail")]')
		lines.append('script = ExtResource("%s")' % train_script)
		lines.append('rail = NodePath("../../Rails/%s")' % train["rail"])
		lines.append("distance = %s" % _value(train["distance"]))
		lines.append("facing = %d" % train["facing"])
		lines.append("max_speed = %s" % _value(train["speed"]))
		lines.append("end_behavior = %d" % train["end"])
		lines.append('locomotive = ExtResource("%s")' % stock[train["locomotive"]][1])
		var wagons: Array[String] = []
		for wagon: String in train["wagons"]:
			wagons.append('ExtResource("%s")' % stock[wagon][1])
		if not wagons.is_empty():
			lines.append('wagons = Array[ExtResource("%s")]([%s])'
					% [wagon_type_script, ", ".join(wagons)])
		if train["load"] > 0.0:
			lines.append("load_factor = %s" % num(train["load"]))
		lines.append("")
	return lines


## The camera rig, and the debug UI: [param panels] stacked top left, each
## [code][name, script, uses_overlay][/code], then the marker overlay if
## [param overlay_script] names one. [param rig] holds script, origin (whole metres), yaw,
## pitch, zoom and max_zoom.
static func camera_and_ui_text(rig: Dictionary, panels: Array,
		overlay_script := "") -> PackedStringArray:
	var origin: Vector3i = rig["origin"]
	var lines := PackedStringArray([
		'[node name="CameraRig" type="Node3D" parent="." node_paths=PackedStringArray("camera")]',
		"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %d, %d, %d)"
				% [origin.x, origin.y, origin.z],
		'script = ExtResource("%s")' % rig["script"],
		'camera = NodePath("Camera3D")',
		"yaw_degrees = %.1f" % rig["yaw"],
		"pitch_degrees = %.1f" % rig["pitch"],
		"zoom = %.1f" % rig["zoom"],
		"max_zoom = %.1f" % rig["max_zoom"],
		"",
		'[node name="Camera3D" type="Camera3D" parent="CameraRig"]',
		"far = 3000.0",
		"",
		'[node name="DebugUi" type="CanvasLayer" parent="."]',
		"",
		'[node name="Panels" type="VBoxContainer" parent="DebugUi"]',
		"offset_left = 12.0",
		"offset_top = 12.0",
		"mouse_filter = 2",
		"theme_override_constants/separation = 8",
		"",
	])
	for panel: Array in panels:
		var with_overlay: bool = panel[2]
		lines.append('[node name="%s" type="PanelContainer" parent="DebugUi/Panels"%s]' % [
				panel[0], ' node_paths=PackedStringArray("overlay")' if with_overlay else ""])
		lines.append("layout_mode = 2")
		lines.append("size_flags_horizontal = 0")
		lines.append("mouse_filter = 2")
		lines.append('script = ExtResource("%s")' % panel[1])
		if with_overlay:
			lines.append('overlay = NodePath("../../MarkerOverlay")')
		lines.append("")
	if overlay_script != "":
		lines.append_array([
			'[node name="MarkerOverlay" type="Control" parent="DebugUi" '
					+ 'node_paths=PackedStringArray("camera")]',
			"anchor_right = 1.0",
			"anchor_bottom = 1.0",
			"mouse_filter = 2",
			'script = ExtResource("%s")' % overlay_script,
			'camera = NodePath("../../CameraRig/Camera3D")',
			"",
		])
	return lines
#endregion
