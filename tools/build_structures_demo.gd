extends SceneTree
## Builds the structures demo, [code]scenes/demos/structures.tscn[/code], and bakes its
## terrain.
##
## [codeblock]
## godot --headless --path . --script res://tools/build_structures_demo.gd
## [/codeblock]
##
## Three straight lines side by side, one per bridge style - stone arches, steel
## trusses, a timber trestle - crossing three gullies of very different widths, so
## each style shows how it copes with a short, a middling and a long span; then a
## ridge they all tunnel through, and a buffer stop at each end. A train shuttles
## up and down each line. Like the playground, the script is the source: a re-run
## overwrites both the scene and [code]scenes/demos/structures_heights.res[/code].

const SCENE_PATH := "res://scenes/demos/structures.tscn"
const HEIGHTS_PATH := "res://scenes/demos/structures_heights.res"

const RAILHEAD := 0.25
const BED_DEPTH := 0.25
const LINE_FROM := -250.0
const LINE_TO := 250.0
## The three lines, north to south, with the bridge style each is built in and the
## train that runs on it.
const LINES := [
	{"name": "StoneLine", "z": -20.0, "style": 0, "train": "StoneTrain",
			"locomotive": "passenger", "wagons": ["coach", "coach"], "load": 0.0},
	{"name": "SteelLine", "z": 0.0, "style": 1, "train": "SteelTrain",
			"locomotive": "freight", "wagons": ["freight_wagon", "freight_wagon", "freight_wagon"],
			"load": 1.0},
	{"name": "TimberLine", "z": 20.0, "style": 2, "train": "TimberTrain",
			"locomotive": "shunting", "wagons": ["coach"], "load": 0.0},
]
## Gullies across all three lines: centre, half width of the floor, half width at
## the rim, depth. A short span, a middling one with a pier or two, and a long one.
const GULLIES := [
	Vector4(-160.0, 3.0, 10.0, 6.0),
	Vector4(-70.0, 10.0, 22.0, 10.0),
	Vector4(55.0, 28.0, 48.0, 15.0),
]
## The ridge the lines tunnel through: centre, half width of the crest, half width
## at the foot, height.
const RIDGE := Vector4(190.0, 18.0, 48.0, 20.0)

const GROUND_SIZE := Vector2(540.0, 160.0)
const GRID := 2.0
## Carving, as for the playground: a bed 3 m either side, cuttings at 1:1, banks at
## 1:1.6; a tunnel where the ground stands this far over the railhead, kept a roof
## over it; a bridge where it drops this far under the bed, left alone.
const BED_HALF_WIDTH := 3.0
const CUT_SLOPE := 1.0
const BANK_SLOPE := 1.6
const CARVE_REACH := 12.0
const TUNNEL_COVER := 7.0
const TUNNEL_ROOF := 6.5
const BRIDGE_DROP := 1.5

const _STOCK := {
	"passenger": ["res://rolling_stock/passenger_locomotive.tres", "loco_passenger"],
	"freight": ["res://rolling_stock/freight_locomotive.tres", "loco_freight"],
	"shunting": ["res://rolling_stock/shunting_locomotive.tres", "loco_shunting"],
	"coach": ["res://rolling_stock/coach.tres", "wagon_coach"],
	"freight_wagon": ["res://rolling_stock/freight_wagon.tres", "wagon_freight"],
}

enum Kind { TRACK, TUNNEL, BRIDGE }


func _initialize() -> void:
	var error := ResourceSaver.save(_bake_terrain(), HEIGHTS_PATH)
	if error != OK:
		push_error("Could not save %s: %s" % [HEIGHTS_PATH, error_string(error)])
		quit(1)
		return
	var file := FileAccess.open(SCENE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not write %s" % SCENE_PATH)
		quit(1)
		return
	file.store_string(_scene_text())
	file.close()
	print("Wrote %s and %s" % [SCENE_PATH, HEIGHTS_PATH])
	quit(0)


#region Terrain
## The ground before carving: flat, less the gullies, plus the ridge. The same at
## every z, so the three lines see the same profile.
static func natural(x: float) -> float:
	var height := 0.0
	for gully: Vector4 in GULLIES:
		height -= gully.w * _profile(absf(x - gully.x), gully.y, gully.z)
	height += RIDGE.w * _profile(absf(x - RIDGE.x), RIDGE.y, RIDGE.z)
	return height


## 1 out to [param inner], easing to 0 at [param outer].
static func _profile(offset: float, inner: float, outer: float) -> float:
	return 1.0 - smoothstep(inner, outer, offset)


static func kind_at(x: float) -> Kind:
	var ground := natural(x)
	if ground > RAILHEAD + TUNNEL_COVER:
		return Kind.TUNNEL
	if ground < RAILHEAD - BED_DEPTH - BRIDGE_DROP:
		return Kind.BRIDGE
	return Kind.TRACK


func _bake_terrain() -> Image:
	var columns := roundi(GROUND_SIZE.x / GRID) + 1
	var rows := roundi(GROUND_SIZE.y / GRID) + 1
	var half := GROUND_SIZE * 0.5
	var image := Image.create_empty(columns, rows, false, Image.FORMAT_RF)
	var bed := RAILHEAD - BED_DEPTH
	for row in rows:
		for column in columns:
			var x := -half.x + float(column) * GRID
			var z := -half.y + float(row) * GRID
			var height := natural(x)
			var ceiling := INF
			var floor_height := -INF
			if x >= LINE_FROM - CARVE_REACH and x <= LINE_TO + CARVE_REACH:
				for line: Dictionary in LINES:
					var gap := absf(z - float(line["z"]))
					if gap > CARVE_REACH:
						continue
					var beyond := maxf(gap - BED_HALF_WIDTH, 0.0)
					match kind_at(clampf(x, LINE_FROM, LINE_TO)):
						Kind.TRACK:
							ceiling = minf(ceiling, bed + beyond * CUT_SLOPE)
							floor_height = maxf(floor_height, bed - beyond / BANK_SLOPE)
						Kind.BRIDGE:
							ceiling = minf(ceiling, bed + beyond * CUT_SLOPE)
						Kind.TUNNEL:
							if gap < BED_HALF_WIDTH + 1.0:
								floor_height = maxf(floor_height, RAILHEAD + TUNNEL_ROOF)
			height = maxf(minf(height, ceiling), floor_height)
			image.set_pixel(column, row, Color(height, 0.0, 0.0))
	return image


## Every stretch of tunnel or bridge along a line, as (from, to, kind) in rail
## distance from the line's west end.
static func structures() -> Array[Vector3]:
	var found: Array[Vector3] = []
	var run := Kind.TRACK
	var start := 0.0
	var x := LINE_FROM
	while x <= LINE_TO + 0.25:
		var now := kind_at(minf(x, LINE_TO))
		if now != run or x > LINE_TO:
			if run != Kind.TRACK:
				found.append(Vector3(start - LINE_FROM, minf(x, LINE_TO) - LINE_FROM, float(run)))
			run = now
			start = x
		x += 0.5
	return found
#endregion


#region Scene text
func _scene_text() -> String:
	var lines := PackedStringArray()
	lines.append("[gd_scene format=3]")
	lines.append("")
	for entry: Array in [
		["Script", "res://scripts/world/ground.gd", "1_ground"],
		["Script", "res://scripts/rails/rail.gd", "2_rail"],
		["Script", "res://scripts/trains/train.gd", "3_train"],
		["Script", "res://scripts/debug/camera_rig.gd", "4_camera"],
		["Script", "res://scripts/debug/train_debug_panel.gd", "5_panel"],
		["Image", HEIGHTS_PATH, "6_heights"],
		["Script", "res://scripts/track/track_mesher.gd", "7_mesher"],
		["Script", "res://scripts/track/bridge.gd", "8_bridge"],
		["Script", "res://scripts/track/tunnel.gd", "9_tunnel"],
		["Script", "res://scripts/trains/wagon_type.gd", "10_wagon_type"],
	]:
		lines.append('[ext_resource type="%s" path="%s" id="%s"]' % entry)
	for stock: String in _STOCK:
		lines.append('[ext_resource type="Resource" path="%s" id="%s"]' % _STOCK[stock])
	lines.append("")
	lines.append_array([
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
	for line: Dictionary in LINES:
		var z := _num(float(line["z"]))
		lines.append('[sub_resource type="Curve3D" id="Curve3D_%s"]' % line["name"])
		lines.append("_data = {")
		lines.append('"points": PackedVector3Array(0, 0, 0, 0, 0, 0, %s, %s, %s, 0, 0, 0, 0, 0, 0, %s, %s, %s),'
				% [_num(LINE_FROM), _num(RAILHEAD), z, _num(LINE_TO), _num(RAILHEAD), z])
		lines.append('"tilts": PackedFloat32Array(0, 0)')
		lines.append("}")
		lines.append("point_count = 2")
		lines.append("")

	lines.append('[node name="StructuresDemo" type="Node3D"]')
	lines.append("")
	lines.append('[node name="WorldEnvironment" type="WorldEnvironment" parent="."]')
	lines.append('environment = SubResource("Environment_1")')
	lines.append("")
	lines.append('[node name="Sun" type="DirectionalLight3D" parent="."]')
	lines.append("transform = Transform3D(0.6452, -0.628, 0.4352, 0, 0.5696, 0.822, -0.764, "
			+ "-0.5303, 0.3675, 0, 60, 0)")
	lines.append("light_energy = 1.3")
	lines.append("shadow_enabled = true")
	lines.append("directional_shadow_max_distance = 500.0")
	lines.append("")
	lines.append('[node name="Ground" type="MeshInstance3D" parent="." groups=["snap_surface"]]')
	lines.append('script = ExtResource("1_ground")')
	lines.append("size = Vector2(%s, %s)" % [_num(GROUND_SIZE.x), _num(GROUND_SIZE.y)])
	lines.append('heightmap = ExtResource("6_heights")')
	lines.append("low_color = Color(0.27, 0.4, 0.21, 1)")
	lines.append("high_color = Color(0.4, 0.52, 0.28, 1)")
	lines.append("steep_color = Color(0.46, 0.4, 0.3, 1)")
	lines.append("steep_amount = 0.8")
	lines.append("")

	lines.append('[node name="Rails" type="Node3D" parent="."]')
	lines.append("")
	for line: Dictionary in LINES:
		lines.append('[node name="%s" type="Path3D" parent="Rails" ' % line["name"]
				+ 'node_paths=PackedStringArray("surface_root")]')
		lines.append('curve = SubResource("Curve3D_%s")' % line["name"])
		lines.append('script = ExtResource("2_rail")')
		lines.append('surface_root = NodePath("../../Ground")')
		lines.append("snap_on_ready = false")
		lines.append("")

	lines.append('[node name="Structures" type="Node3D" parent="."]')
	lines.append("")
	var spans := structures()
	for line: Dictionary in LINES:
		var bridges := 0
		for span in spans:
			var is_bridge := int(span.z) == Kind.BRIDGE
			var label: String
			if is_bridge:
				bridges += 1
				label = "%sBridge%d" % [line["name"], bridges]
			else:
				label = "%sTunnel" % line["name"]
			lines.append('[node name="%s" type="Node3D" parent="Structures" ' % label
					+ 'node_paths=PackedStringArray("rail")]')
			lines.append('script = ExtResource("%s")' % ("8_bridge" if is_bridge else "9_tunnel"))
			lines.append('rail = NodePath("../../Rails/%s")' % line["name"])
			lines.append("from_distance = %s" % _num(span.x))
			lines.append("to_distance = %s" % _num(span.y))
			if is_bridge:
				lines.append("style = %d" % int(line["style"]))
			lines.append("")

	lines.append('[node name="Trains" type="Node3D" parent="."]')
	lines.append("")
	for line: Dictionary in LINES:
		lines.append('[node name="%s" type="Node3D" parent="Trains" groups=["trains"] '
				% line["train"] + 'node_paths=PackedStringArray("rail")]')
		lines.append('script = ExtResource("3_train")')
		lines.append('rail = NodePath("../../Rails/%s")' % line["name"])
		lines.append("distance = 40")
		lines.append("facing = 1")
		lines.append("max_speed = 14")
		# Back and forth for ever, over every bridge and through the tunnel.
		lines.append("end_behavior = 1")
		lines.append('locomotive = ExtResource("%s")' % _STOCK[line["locomotive"]][1])
		var wagons: Array[String] = []
		for wagon: String in line["wagons"]:
			wagons.append('ExtResource("%s")' % _STOCK[wagon][1])
		lines.append('wagons = Array[ExtResource("10_wagon_type")]([%s])' % ", ".join(wagons))
		if float(line["load"]) > 0.0:
			lines.append("load_factor = %s" % _num(float(line["load"])))
		lines.append("")

	lines.append('[node name="Track" type="Node3D" parent="."]')
	lines.append('script = ExtResource("7_mesher")')
	lines.append("")
	lines.append_array([
		'[node name="CameraRig" type="Node3D" parent="." node_paths=PackedStringArray("camera")]',
		"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -40, 2, 0)",
		'script = ExtResource("4_camera")',
		'camera = NodePath("Camera3D")',
		"yaw_degrees = -20.0",
		"pitch_degrees = -32.0",
		"zoom = 260.0",
		"max_zoom = 700.0",
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
		'[node name="TrainDebugPanel" type="PanelContainer" parent="DebugUi/Panels"]',
		"layout_mode = 2",
		"size_flags_horizontal = 0",
		"mouse_filter = 2",
		'script = ExtResource("5_panel")',
		"",
	])
	return "\n".join(lines)


## Four decimals, no trailing zeros, and no negative zero.
func _num(value: float) -> String:
	if absf(value) < 5e-5:
		return "0"
	return String.num(value, 4)
#endregion
