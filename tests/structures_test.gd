extends TestCase
## Bridges and tunnels, on [code]scenes/demos/structures.tscn[/code]: three straight
## lines side by side - StoneLine, SteelLine and TimberLine, each built in one
## bridge style - crossing a short, a middling and a long gully, then a ridge they
## all tunnel through, with a train shuttling up and down each. The playground and
## the desert level dress their own bridge and tunnels the same way.

const DEMO_SCENE := "res://scenes/demos/structures.tscn"
const LINES := {
	"StoneLine": Bridge.Style.STONE_ARCH,
	"SteelLine": Bridge.Style.STEEL_TRUSS,
	"TimberLine": Bridge.Style.WOODEN_TRESTLE,
}

var demo: Node


func before_each() -> void:
	demo = await load_scene(DEMO_SCENE)


func _structures_on(line: String) -> Array[TrackStructure]:
	var found: Array[TrackStructure] = []
	for node in demo.get_node("Structures").get_children():
		var structure := node as TrackStructure
		if structure != null and structure.rail.name == line:
			found.append(structure)
	found.sort_custom(func(a: TrackStructure, b: TrackStructure) -> bool:
		return a.start_distance() < b.start_distance())
	return found


func test_each_line_crosses_three_gullies_in_its_own_style_and_tunnels_the_ridge() -> void:
	for line: String in LINES:
		var structures := _structures_on(line)
		var bridges: Array[Bridge] = []
		var tunnels := 0
		for structure in structures:
			if structure is Bridge:
				bridges.append(structure as Bridge)
			elif structure is Tunnel:
				tunnels += 1
		var spans: Array[String] = []
		for bridge in bridges:
			spans.append("%.0f m" % bridge.span_length())
			assert_eq(bridge.style, LINES[line], "%s is built in its line's style" % bridge.name)
			assert_not_null(bridge.mesh_instance().mesh, "%s has been built" % bridge.name)
		note("%-10s bridges of %s, %d tunnel" % [line, ", ".join(spans), tunnels])
		assert_eq(bridges.size(), 3, "%s crosses three gullies" % line)
		assert_eq(tunnels, 1, "and tunnels through the ridge")
		if bridges.size() == 3:
			assert_less(bridges[0].span_length(), 25.0, "the first gully is a short span")
			assert_greater(bridges[2].span_length(), 80.0, "the last a long one")


## How each style deals with length: stone in arches of about 16 m, steel in
## trusses of at most 40 m with piers between, timber in bents every few metres.
func test_long_spans_are_split_the_way_each_style_splits_them() -> void:
	for line: String in LINES:
		for structure in _structures_on(line):
			var bridge := structure as Bridge
			if bridge == null:
				continue
			match bridge.style:
				Bridge.Style.STONE_ARCH:
					var arches := bridge.arch_spans()
					note("%s: %.0f m in %d arches" % [bridge.name, bridge.span_length(), arches.size()])
					for arch in arches:
						assert_between(arch.y - arch.x, 8.0, 22.0, "%s's arches are 8-22 m" % bridge.name)
				Bridge.Style.STEEL_TRUSS:
					var joints := bridge.truss_joints()
					note("%s: %.0f m in %d trusses" % [bridge.name, bridge.span_length(), joints.size() - 1])
					for i in joints.size() - 1:
						assert_less(joints[i + 1] - joints[i], 40.01, "%s's trusses are at most 40 m"
								% bridge.name)
	var long_truss := _structures_on("SteelLine")[2] as Bridge
	assert_greater(float(long_truss.truss_joints().size() - 1), 2.0,
			"the long gully needs piers under the truss")
	var short_truss := _structures_on("SteelLine")[0] as Bridge
	assert_eq(short_truss.truss_joints().size() - 1, 1, "the short one is a single span")


## A truss is straight, so on a curve the track bows away from its centre line;
## the bridge takes more, shorter spans until that bow stays small. Checked on a
## 60 m radius semicircle, which no demo has.
func test_a_curved_truss_is_split_until_the_track_stays_inside_it() -> void:
	var rail := Rail.new()
	rail.snap_on_ready = false
	rail.curve = Curve3D.new()
	var radius := 60.0
	for i in 9:
		var angle := PI * float(i) / 8.0
		var tangent := Vector3(-sin(angle), 0.0, cos(angle)) * radius * 0.1316
		rail.curve.add_point(Vector3(cos(angle), 0.0, sin(angle)) * radius, -tangent, tangent)
	own(rail)
	demo.add_child(rail)
	var bridge := Bridge.new()
	bridge.style = Bridge.Style.STEEL_TRUSS
	bridge.rail = rail
	bridge.from_distance = 10.0
	bridge.to_distance = rail.rail_length() - 10.0
	demo.add_child(bridge)
	own(bridge)
	var joints := bridge.truss_joints()
	var worst := 0.0
	for i in joints.size() - 1:
		var a := rail.sample_position(joints[i])
		var b := rail.sample_position(joints[i + 1])
		var at := joints[i]
		while at < joints[i + 1]:
			var p := rail.sample_position(at)
			var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
			worst = maxf(worst, p.distance_to(a.lerp(b, t)))
			at += 0.5
	note("%.0f m round a %.0f m radius: %d trusses, the track at most %.2f m off their centre line"
			% [bridge.span_length(), radius, joints.size() - 1, worst])
	assert_less(worst, Bridge._MAX_TRUSS_BOW + 0.01, "the track stays near the truss's centre line")
	# Half the widest train plus that bow, inside the trusses' inner faces.
	assert_less(1.55 + worst, Bridge._TRUSS_HALF_WIDTH - 0.25, "so the widest train clears the trusses")


## The tallest thing on the rails - a locomotive's roof marker - fits under the
## truss's top bracing and through a tunnel's arch, and the widest at its sides.
func test_the_tallest_and_widest_trains_fit_through() -> void:
	var tallest := 0.0
	var widest := 0.0
	for path in DirAccess.get_files_at("res://rolling_stock"):
		var type := load("res://rolling_stock/" + path) as CarType
		if type == null:
			continue
		tallest = maxf(tallest, type.height * 1.25)
		widest = maxf(widest, type.width)
	var bracing := -(TrackLayout.RAIL_HEIGHT + TrackLayout.SLEEPER_HEIGHT) - 0.5 \
			+ Bridge._TRUSS_MIN_HEIGHT - 0.125
	note("tallest %.2f m, widest %.2f m; truss bracing at %.2f m, tunnel crown %.2f m, "
			% [tallest, widest, bracing, Tunnel.CROWN]
			+ "arch %.2f m high at the widest train's side" % Tunnel.opening_top(widest * 0.5))
	assert_greater(bracing, tallest + 0.3, "the truss's top bracing clears the tallest train")
	assert_greater(Tunnel.CROWN, tallest + 0.3, "and so does the tunnel's crown")
	assert_greater(Tunnel.opening_top(widest * 0.5), 3.9 + 0.3,
			"and the arch over the widest train's sides clears its roof")


## Behind each mouth the terrain is cut away exactly where the bore's shell is,
## so the bore is open to the light rather than full of hillside - and nowhere
## else, so the hillside has no hole in it. Heights are still answered in the
## cut, so nothing standing beside the track loses its footing.
func test_a_tunnel_opens_the_ground_inside_its_shell_and_nowhere_else() -> void:
	var ground: Ground = demo.get_node("Ground")
	var faces := ground.mesh.get_faces()
	var to_global := ground.global_transform
	for line: String in LINES:
		var tunnel: Tunnel = null
		for structure in _structures_on(line):
			if structure is Tunnel:
				tunnel = structure as Tunnel
		if not assert_not_null(tunnel, "%s has a tunnel" % line):
			continue
		assert_eq(tunnel.mouths().size(), 2, "%s's tunnel has a mouth at each end" % line)
		for mouth in tunnel.mouths():
			var frame := tunnel.mouth_frame(mouth)
			var inside := 0
			var outside_holes := 0
			var near := PackedVector3Array()
			for i in range(0, faces.size(), 3):
				var a := to_global * faces[i]
				var b := to_global * faces[i + 1]
				var c := to_global * faces[i + 2]
				var middle := (a + b + c) / 3.0
				if Vector2(middle.x - frame.origin.x, middle.z - frame.origin.z).length() > 16.0:
					continue
				near.append_array(PackedVector3Array([a, b, c]))
				var local := frame.affine_inverse() * middle
				if absf(local.x) < Tunnel.SHELL_HALF - 0.05 and local.z < -0.05 and local.z > -10.0 \
						and local.y < Tunnel.SHELL_TOP - 0.05 and (b - a).cross(c - a).length() > 1e-3:
					inside += 1
			# Probe the ground's own triangles on a grid round the mouth: a
			# column that finds no triangle is a hole in the mesh.
			for x in range(-14, 15):
				for z in range(-12, 13):
					var probe := frame * Vector3(float(x) * 0.5 + 0.13, 0.0, float(z) * 0.5 + 0.07)
					var local := frame.affine_inverse() * probe
					var height = ground.surface_height_at(probe.x, probe.z)
					var in_shell := absf(local.x) < Tunnel.SHELL_HALF + 0.05 and local.z < 0.05 \
							and float(height) - frame.origin.y < Tunnel.SHELL_TOP + 0.05
					if in_shell:
						continue
					var hit := false
					for i in range(0, near.size(), 3):
						if Geometry3D.ray_intersects_triangle(Vector3(probe.x, 1000.0, probe.z),
								Vector3.DOWN, near[i], near[i + 1], near[i + 2]) != null:
							hit = true
							break
					if not hit:
						outside_holes += 1
			assert_eq(inside, 0, "%s: no ground left inside the shell behind a mouth" % line)
			assert_eq(outside_holes, 0, "%s: and no hole in the ground anywhere else round it" % line)
			var centre := frame * Vector3(0.0, 0.0, -3.0)
			assert_not_null(ground.surface_height_at(centre.x, centre.z),
					"%s: the ground still answers heights in the cut" % line)


## The point of the scene: every train runs over all three of its bridges and
## through its tunnel, both ways, and none comes to grief.
func test_every_train_runs_over_its_bridges_and_through_its_tunnel() -> void:
	var trains: Array[Train] = []
	var furthest: Dictionary[Train, float] = {}
	for node in demo.get_node("Trains").get_children():
		trains.append(node as Train)
		furthest[node as Train] = 0.0
	for _step in 120:
		await physics_frames(30)
		for train in trains:
			# Every train sets out facing east, so its nose is half its length on.
			furthest[train] = maxf(furthest[train], train.distance + train.half_length())
	for train in trains:
		var tunnel_end := 0.0
		for structure in _structures_on(train.rail.name):
			if structure is Tunnel:
				tunnel_end = structure.end_distance()
		note("%-12s got its nose as far as %.0f m (the tunnel ends at %.0f m), %s" % [train.name,
				furthest[train], tunnel_end, train.state_name()])
		assert_greater(furthest[train], tunnel_end, "%s ran out through the tunnel" % train.name)
		assert_false(train.derailed, "%s is still on the rails" % train.name)


## The other two levels dress what their terrain already had.
func test_the_playground_and_the_desert_dress_their_bridges_and_tunnels() -> void:
	for entry: Array in [["res://scenes/main.tscn", 1, 1], ["res://scenes/levels/desert.tscn", 1, 5]]:
		var level := await load_scene(entry[0])
		var bridges := 0
		var tunnels := 0
		for node in level.get_node("Structures").get_children():
			var structure := node as TrackStructure
			assert_not_null(structure.mesh_instance().mesh, "%s has been built" % structure.name)
			assert_true(structure._get_configuration_warnings().is_empty(),
					"%s is configured cleanly" % structure.name)
			if structure is Bridge:
				bridges += 1
			else:
				tunnels += 1
		note("%s: %d bridge, %d tunnels" % [String(entry[0]).get_file(), bridges, tunnels])
		assert_eq(bridges, entry[1], "%s has its bridge" % String(entry[0]).get_file())
		assert_eq(tunnels, entry[2], "and its tunnels")
