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

const Kit := preload("res://tools/scene_kit.gd")

const SCENE_PATH := "res://scenes/demos/structures.tscn"
const HEIGHTS_PATH := "res://scenes/demos/structures_heights.res"

const RAILHEAD := 0.25
const BED_DEPTH := 0.25
const LINE_FROM := -250.0
const LINE_TO := 250.0
## The three lines, north to south, with the bridge style each is built in and the
## train that runs on it.
const LINES := [
	{"name": "StoneLine", "z": -20.0, "style": Bridge.Style.STONE_ARCH, "train": "StoneTrain",
			"locomotive": "passenger", "wagons": ["coach", "coach"], "load": 0.0},
	{"name": "SteelLine", "z": 0.0, "style": Bridge.Style.STEEL_TRUSS, "train": "SteelTrain",
			"locomotive": "freight", "wagons": ["freight_wagon", "freight_wagon", "freight_wagon"],
			"load": 1.0},
	{"name": "TimberLine", "z": 20.0, "style": Bridge.Style.WOODEN_TRESTLE,
			"train": "TimberTrain", "locomotive": "shunting", "wagons": ["coach"], "load": 0.0},
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
## Carving reaches this far either side of a line - half the playground's, the lines
## being only 20 m apart; the rest of the rules are [code]Kit[/code]'s.
const CARVE_REACH := 12.0

const _STOCK := {
	"passenger": ["res://rolling_stock/passenger_locomotive.tres", "loco_passenger"],
	"freight": ["res://rolling_stock/freight_locomotive.tres", "loco_freight"],
	"shunting": ["res://rolling_stock/shunting_locomotive.tres", "loco_shunting"],
	"coach": ["res://rolling_stock/coach.tres", "wagon_coach"],
	"freight_wagon": ["res://rolling_stock/freight_wagon.tres", "wagon_freight"],
}

func _initialize() -> void:
	if not Kit.save_heights(_bake_terrain(), HEIGHTS_PATH) \
			or not Kit.write_scene(SCENE_PATH, _scene_text()):
		quit(1)
		return
	print("Wrote %s and %s" % [SCENE_PATH, HEIGHTS_PATH])
	quit(0)


#region Terrain
## The ground before carving: flat, less the gullies, plus the ridge. The same at
## every z, so the three lines see the same profile.
func _natural(x: float) -> float:
	var height := 0.0
	for gully: Vector4 in GULLIES:
		height -= gully.w * _profile(absf(x - gully.x), gully.y, gully.z)
	height += RIDGE.w * _profile(absf(x - RIDGE.x), RIDGE.y, RIDGE.z)
	return height


## 1 out to [param inner], easing to 0 at [param outer].
func _profile(offset: float, inner: float, outer: float) -> float:
	return 1.0 - smoothstep(inner, outer, offset)


func _kind_at(x: float) -> Kit.Kind:
	return Kit.kind(_natural(x), RAILHEAD, BED_DEPTH)


func _bake_terrain() -> Image:
	var columns := roundi(GROUND_SIZE.x / GRID) + 1
	var rows := roundi(GROUND_SIZE.y / GRID) + 1
	var half := GROUND_SIZE * 0.5
	var image := Image.create_empty(columns, rows, false, Image.FORMAT_RF)
	for row in rows:
		for column in columns:
			var x := -half.x + float(column) * GRID
			var z := -half.y + float(row) * GRID
			var height := _natural(x)
			var ceiling := INF
			var floor_height := -INF
			if x >= LINE_FROM - CARVE_REACH and x <= LINE_TO + CARVE_REACH:
				for line: Dictionary in LINES:
					var gap := absf(z - float(line["z"]))
					if gap > CARVE_REACH:
						continue
					var kind := _kind_at(clampf(x, LINE_FROM, LINE_TO))
					ceiling = minf(ceiling, Kit.cut_limit(kind, gap, RAILHEAD, BED_DEPTH))
					floor_height = maxf(floor_height,
							Kit.fill_limit(kind, gap, RAILHEAD, BED_DEPTH))
			height = maxf(minf(height, ceiling), floor_height)
			image.set_pixel(column, row, Color(height, 0.0, 0.0))
	return image


## Every stretch of tunnel or bridge along a line, as (from, to, kind) in rail
## distance from the line's west end.
func _structures() -> Array[Vector3]:
	var found: Array[Vector3] = []
	var run := Kit.Kind.TRACK
	var start := 0.0
	var x := LINE_FROM
	while x <= LINE_TO + 0.25:
		var now := _kind_at(minf(x, LINE_TO))
		if now != run or x > LINE_TO:
			if run != Kit.Kind.TRACK:
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
	lines.append_array(Kit.environment_text())
	for line: Dictionary in LINES:
		var straight := Curve3D.new()
		straight.add_point(Vector3(LINE_FROM, RAILHEAD, float(line["z"])))
		straight.add_point(Vector3(LINE_TO, RAILHEAD, float(line["z"])))
		lines.append_array(Kit.curve_text(line["name"], straight))

	lines.append('[node name="StructuresDemo" type="Node3D"]')
	lines.append("")
	lines.append_array(Kit.world_environment_and_sun_text(500.0))
	lines.append_array(Kit.heightmap_ground_text("1_ground", GROUND_SIZE, "6_heights"))

	var rails: Array[String] = []
	for line: Dictionary in LINES:
		rails.append(line["name"])
	lines.append_array(Kit.rails_text(rails, "2_rail"))

	lines.append_array(Kit.group("Structures"))
	var spans := _structures()
	for line: Dictionary in LINES:
		var bridges := 0
		for span in spans:
			var is_bridge := int(span.z) == Kit.Kind.BRIDGE
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
			lines.append("from_distance = %s" % Kit.num(span.x))
			lines.append("to_distance = %s" % Kit.num(span.y))
			if is_bridge:
				lines.append("style = %d" % int(line["style"]))
			lines.append("")

	var trains: Array[Dictionary] = []
	for line: Dictionary in LINES:
		# Back and forth for ever, over every bridge and through the tunnel.
		trains.append({"name": line["train"], "rail": line["name"], "distance": 40,
				"facing": 1, "speed": 14, "end": Train.EndBehavior.REVERSE,
				"locomotive": line["locomotive"], "wagons": line["wagons"], "load": line["load"]})
	lines.append_array(Kit.trains_text(trains, "3_train", "10_wagon_type", _STOCK))

	lines.append('[node name="Track" type="Node3D" parent="."]')
	lines.append('script = ExtResource("7_mesher")')
	lines.append("")
	lines.append_array(Kit.camera_and_ui_text({"script": "4_camera",
			"origin": Vector3i(-40, 2, 0), "yaw": -20.0, "pitch": -32.0, "zoom": 260.0,
			"max_zoom": 700.0}, [["TrainDebugPanel", "5_panel", false]]))
	return "\n".join(lines)
#endregion
