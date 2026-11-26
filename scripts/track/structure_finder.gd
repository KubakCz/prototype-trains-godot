class_name StructureFinder
extends RefCounted
## [b]Find Bridges & Tunnels[/b], for [TrackMesher]: proposes a [Bridge] wherever
## the track runs high over the ground and a [Tunnel] wherever it runs under it,
## skipping stretches already covered. A first draft: check the spans and pick
## each bridge's style afterwards.

## How high over the ground the railhead has to be to call it a bridge, and how
## far under it for a tunnel.
const BRIDGE_CLEARANCE := 3.0
const TUNNEL_COVER := 4.0


## Adds what it finds along [param rails] to [param root]'s [code]Structures[/code]
## node, made if missing, leaving out what [param existing] already covers.
static func propose(root: Node, rails: Array[Rail], existing: Array[TrackStructure]) -> void:
	var surfaces := rails[0].ground_surfaces()
	var parent := root.get_node_or_null(^"Structures")
	if parent == null:
		parent = Node3D.new()
		parent.name = "Structures"
		root.add_child(parent)
		parent.owner = root
	for rail in rails:
		for found: Vector3 in _classify(rail, surfaces):
			var from := found.x
			var to := found.y
			var already := false
			for structure in existing:
				if structure.rail == rail and structure.start_distance() < to \
						and structure.end_distance() > from:
					already = true
			if already:
				continue
			var structure: TrackStructure
			if found.z > 0.0:
				var bridge := Bridge.new()
				bridge.style = Bridge.Style.STONE_ARCH if to - from < 40.0 \
						else Bridge.Style.STEEL_TRUSS
				structure = bridge
			else:
				structure = Tunnel.new()
			structure.name = "%s%s" % ["Bridge" if found.z > 0.0 else "Tunnel", rail.name]
			parent.add_child(structure, true)
			structure.owner = root
			structure.rail = rail
			structure.from_distance = snappedf(from, 0.1)
			structure.to_distance = snappedf(to, 0.1)


## Stretches of [param rail] that look like a bridge or a tunnel, as
## (from, to, +1 for a bridge / -1 for a tunnel).
static func _classify(rail: Rail, surfaces: Array[SurfaceSnapper.Surface]) -> Array[Vector3]:
	var found: Array[Vector3] = []
	var length := rail.rail_length()
	var kind := 0
	var run_start := 0.0
	var at := 0.0
	while true:
		var point := rail.sample_position(minf(at, length))
		# The terrain as authored: the mesh has the track's own cutting in it.
		var height = SurfaceSnapper.height_at(surfaces, point.x, point.z, true)
		var now := 0
		if height != null:
			var ground := float(height)
			if point.y - ground > BRIDGE_CLEARANCE:
				now = 1
			elif ground - point.y > TUNNEL_COVER:
				now = -1
		if now != kind or at >= length:
			if kind != 0 and at - run_start >= 4.0:
				found.append(Vector3(_widen(rail, surfaces, run_start, -1, kind),
						_widen(rail, surfaces, minf(at, length), 1, kind), float(kind)))
			kind = now
			run_start = at
		if at >= length:
			break
		at += 1.0
	return found


## Carries an end of a found stretch on outward until it meets the ground: a
## bridge until the bank is close under the track, so the abutments sit on it; a
## tunnel back to where the hillside starts to rise, so the portal stands
## against it.
static func _widen(rail: Rail, surfaces: Array[SurfaceSnapper.Surface], at: float,
		outward: int, kind: int) -> float:
	var length := rail.rail_length()
	while at > 0.0 and at < length:
		var next := clampf(at + 0.5 * float(outward), 0.0, length)
		var point := rail.sample_position(next)
		var height = SurfaceSnapper.height_at(surfaces, point.x, point.z, true)
		if height == null:
			break
		var rise := float(height) - point.y
		if (kind > 0 and rise > -1.0) or (kind < 0 and rise < 0.5):
			break
		at = next
	return at