@tool
class_name Tunnel
extends TrackStructure
## Where [member TrackStructure.rail] runs under the ground, from
## [member TrackStructure.from_distance] to [member TrackStructure.to_distance].
##
## Each end that is not also the end of the rail gets a mouth: a stone portal
## wall across the track with an arched opening, and a short bore behind it that
## fades to black. A tunnel that runs off the end of its rail - the way off a
## level - has just the one mouth, and swallows the dead end, buffer stop and
## all.
##
## The terrain is a heightfield, so it has no tunnel in it: across the one grid
## cell a mouth spans, it rises from the track bed straight through the loading
## gauge to the roof. A tunnel therefore shapes the [Ground] (see
## [constant Ground.SHAPER_GROUP]): the ground inside the bore's stone shell is
## cut out exactly, and the shell - side walls and a roof, wherever the hill is
## too shallow to cover it - closes the cut, so the hillside never has a hole
## in it. In front of the face the ground is levelled with the bed for a couple
## of grid cells, between two short retaining walls. Trains run on through the
## hillside beyond, out of sight under the terrain.

## Half the opening's width, and the height of its springing and crown above the
## railhead. A semicircular arch, clear of the widest and tallest stock.
const OPEN_HALF := 2.4
const SPRINGING := 3.6
const CROWN := SPRINGING + OPEN_HALF
const _WALL_HALF := 5.5
const _WALL_TOP := 7.6
const _WALL_THICKNESS := 0.9
const _BORE_LENGTH := 14.0
## The outside of the bore's stone shell: half its width, and its roof above the
## railhead. The ground is cut out inside it.
const SHELL_HALF := OPEN_HALF + 0.5
const SHELL_TOP := CROWN + 0.5
## The retaining walls either side of the apron in front of the face.
const _RETAINING_THICKNESS := 0.5
## Highest a portal grows to meet a steep hillside.
const _WALL_TOP_LIMIT := 16.0

const _STONE := Color(0.6, 0.57, 0.52)
const _RING := Color(0.5, 0.47, 0.43)
const _COPING := Color(0.7, 0.67, 0.62)

func _enter_tree() -> void:
	add_to_group(Ground.SHAPER_GROUP)


func _exit_tree() -> void:
	remove_from_group(Ground.SHAPER_GROUP)


## Distances along the rail of each mouth, with +1/-1 for which way along the
## rail leads into the hill.
func mouths() -> Array[Vector2]:
	var found: Array[Vector2] = []
	if not is_usable():
		return found
	if start_distance() > END_TOLERANCE:
		found.append(Vector2(start_distance(), 1.0))
	if end_distance() < rail.rail_length() - END_TOLERANCE:
		found.append(Vector2(end_distance(), -1.0))
	return found


## The mouth's frame: on the railhead where the portal's face is, upright, -Z
## pointing into the tunnel.
func mouth_frame(mouth: Vector2) -> Transform3D:
	var frame := flat_frame(mouth.x)
	if mouth.y < 0.0:
		frame.basis = frame.basis.rotated(Vector3.UP, PI)
	return frame


## For [Ground]: behind each mouth, the bore's shell - its centre line at bed
## level from the face inward, its half width and its roof - for the ground to
## be cut out of.
func ground_holes(_ground: Ground) -> Array[Dictionary]:
	var holes: Array[Dictionary] = []
	for mouth in mouths():
		var line := PackedVector3Array()
		for at in _bore_distances(mouth):
			line.append(flat_frame(at).origin + Vector3.DOWN * rail.surface_offset)
		holes.append({"line": line, "half_width": SHELL_HALF,
				"roof": SHELL_TOP + rail.surface_offset})
	return holes


func _build_mesh(surfaces: Array[SurfaceSnapper.Surface]) -> ArrayMesh:
	# The ground first: the portal is sized to the hillside it is cut into.
	var grounds := refresh_grounds(surfaces)
	var ground: Ground = null if grounds.is_empty() else grounds[-1]
	var cell := ground.cell_diagonal() if ground != null else 3.0
	var apron := ground.apron_length() if ground != null else 2.0 * cell
	var stone := MeshSurface.new()
	var bore := MeshSurface.new()
	for mouth in mouths():
		_build_portal(stone, mouth, cell * 0.5, surfaces)
		_build_retaining_walls(stone, mouth, apron, surfaces)
		_build_shell(stone, mouth)
		_build_bore(bore, mouth)
	var mesh := ArrayMesh.new()
	stone.commit(mesh, TrackMaterials.stone())
	bore.commit(mesh, TrackMaterials.bore())
	return mesh


## Height of the opening's edge at [param x] across the track: the semicircle
## over the springing, or the bed beside it.
static func opening_top(x: float) -> float:
	if absf(x) >= OPEN_HALF:
		return SPRINGING
	return SPRINGING + sqrt(OPEN_HALF * OPEN_HALF - x * x)


#region Portal
## The portal wall, never lower than [constant _WALL_TOP] and as high as the
## hillside within [param depth] behind it. The ground in front of the face is
## levelled and the ground behind it is not, so the grid cell that straddles
## the face climbs from one to the other as steeply as the hill demands; the
## wall stands in front of that climb.
func _build_portal(surface: MeshSurface, mouth: Vector2, depth: float,
		surfaces: Array[SurfaceSnapper.Surface]) -> void:
	var frame := mouth_frame(mouth)
	var base := -rail.surface_offset - 1.0
	var wall_top := _WALL_TOP
	for i in 12:
		var x := lerpf(-_WALL_HALF, _WALL_HALF, float(i) / 11.0)
		for k in 4:
			var behind := frame * Vector3(x, 0.0, -0.05 - depth * float(k) / 3.0)
			var height = SurfaceSnapper.height_at(surfaces, behind.x, behind.z)
			if height != null:
				wall_top = maxf(wall_top, float(height) - frame.origin.y + 0.2)
	wall_top = minf(wall_top, _WALL_TOP_LIMIT)
	var outward := frame.basis.z
	var xs := PackedFloat64Array([-_WALL_HALF])
	for i in 17:
		xs.append(lerpf(-OPEN_HALF, OPEN_HALF, float(i) / 16.0))
	xs.append(_WALL_HALF)
	for i in xs.size() - 1:
		var x0 := xs[i]
		var x1 := xs[i + 1]
		var inside := x0 >= -OPEN_HALF - 1e-4 and x1 <= OPEN_HALF + 1e-4
		var b0 := opening_top(x0) if inside else base
		var b1 := opening_top(x1) if inside else base
		for z: float in [0.0, -_WALL_THICKNESS]:
			surface.add_quad_facing(frame * Vector3(x0, b0, z), frame * Vector3(x1, b1, z),
					frame * Vector3(x1, wall_top, z), frame * Vector3(x0, wall_top, z),
					outward if z == 0.0 else -outward, _STONE)
	# Ends of the wall, and a coping along its top.
	for x: float in [-_WALL_HALF, _WALL_HALF]:
		surface.add_quad_facing(frame * Vector3(x, base, 0.0), frame * Vector3(x, wall_top, 0.0),
				frame * Vector3(x, wall_top, -_WALL_THICKNESS), frame * Vector3(x, base, -_WALL_THICKNESS),
				frame.basis.x * signf(x), _STONE)
	surface.add_box(frame * Transform3D(Basis.IDENTITY,
			Vector3(0.0, wall_top + 0.15, -_WALL_THICKNESS * 0.5 + 0.1)),
			Vector3(_WALL_HALF * 2.0 + 0.4, 0.3, _WALL_THICKNESS + 0.4), _COPING)
	# A ring of voussoirs round the arch and down the jambs, standing proud.
	var ring := OPEN_HALF + 0.3
	var previous := Vector3(-ring, SPRINGING, 0.12)
	for i in range(1, 10):
		var angle := PI - PI * float(i) / 9.0
		var point := Vector3(cos(angle) * ring, SPRINGING + sin(angle) * ring, 0.12)
		surface.add_beam(frame * previous, frame * point, 0.6, 0.25, _RING, outward)
		previous = point
	for x: float in [-ring, ring]:
		surface.add_beam(frame * Vector3(x, SPRINGING, 0.12),
				frame * Vector3(x, -rail.surface_offset, 0.12), 0.6, 0.25, _RING, outward)


## Two short walls along the apron's sides, from the face out to its end: inside
## them the ground is levelled with the bed, outside it is the hillside, and the
## walls stand as high as the hillside so nothing shows between the two. Never
## rising on their way out from the portal, like wing walls.
func _build_retaining_walls(surface: MeshSurface, mouth: Vector2, length: float,
		surfaces: Array[SurfaceSnapper.Surface]) -> void:
	var frame := mouth_frame(mouth)
	var outward := frame.basis.z
	var bed := -rail.surface_offset
	var count := maxi(2, ceili(length / 0.75))
	for side: float in [-1.0, 1.0]:
		var inner := SHELL_HALF * side
		var outer := (SHELL_HALF + _RETAINING_THICKNESS) * side
		var tops := PackedFloat32Array()
		for i in count + 1:
			var z := length * float(i) / float(count)
			var top := bed + 0.15
			for x: float in [inner + 0.01 * side, outer]:
				var point := frame * Vector3(x, 0.0, z)
				var height = SurfaceSnapper.height_at(surfaces, point.x, point.z)
				if height != null:
					top = maxf(top, float(height) - frame.origin.y + 0.15)
			tops.append(top)
		for i in range(count - 1, -1, -1):
			tops[i] = maxf(tops[i], tops[i + 1])
		var inner_tops := PackedVector3Array()
		var outer_tops := PackedVector3Array()
		var inner_feet := PackedVector3Array()
		var outer_feet := PackedVector3Array()
		for i in count + 1:
			var z := length * float(i) / float(count)
			inner_tops.append(frame * Vector3(inner, tops[i], z))
			outer_tops.append(frame * Vector3(outer, tops[i], z))
			inner_feet.append(frame * Vector3(inner, bed - 1.0, z))
			outer_feet.append(frame * Vector3(outer, bed - 1.0, z))
		var across := frame.basis.x * side
		surface.add_strip(inner_tops, inner_feet, PackedVector3Array([-across]), _STONE)
		surface.add_strip(outer_tops, outer_feet, PackedVector3Array([across]), _STONE)
		surface.add_strip(inner_tops, outer_tops, PackedVector3Array([Vector3.UP]), _RING)
		surface.add_quad_facing(inner_tops[count], outer_tops[count], outer_feet[count],
				inner_feet[count], outward, _STONE)


## The outside of the bore behind a mouth: side walls and a flat roof at
## [constant SHELL_HALF] and [constant SHELL_TOP], closed at the far end. The
## ground is cut out exactly inside it, so where the hill over the tunnel is
## shallow this is what shows instead of a hole - and where it is deep, it is
## buried.
func _build_shell(surface: MeshSurface, mouth: Vector2) -> void:
	var lefts_top := PackedVector3Array()
	var rights_top := PackedVector3Array()
	var lefts_foot := PackedVector3Array()
	var rights_foot := PackedVector3Array()
	var outsides := PackedVector3Array()
	for at in _bore_distances(mouth):
		var frame := flat_frame(at)
		var right := frame.basis.x
		var roof := frame.origin + Vector3.UP * SHELL_TOP
		var foot := frame.origin + Vector3.DOWN * (rail.surface_offset + 1.0)
		lefts_top.append(roof - right * SHELL_HALF)
		rights_top.append(roof + right * SHELL_HALF)
		lefts_foot.append(foot - right * SHELL_HALF)
		rights_foot.append(foot + right * SHELL_HALF)
		outsides.append(right)
	surface.add_strip(lefts_top, lefts_foot, negated(outsides), _RING)
	surface.add_strip(rights_top, rights_foot, outsides, _RING)
	surface.add_strip(lefts_top, rights_top, PackedVector3Array([Vector3.UP]), _RING)
	var last := lefts_top.size() - 1
	var inward := (lefts_top[last] - lefts_top[last - 1]).normalized()
	surface.add_quad_facing(lefts_top[last], rights_top[last], rights_foot[last],
			lefts_foot[last], inward, _RING)
#endregion


#region Bore
## Distances along the rail the bore behind [param mouth] is sampled at, from
## the portal's face inward - never past halfway, where the other mouth's bore
## takes over.
func _bore_distances(mouth: Vector2) -> PackedFloat64Array:
	var depth := minf(_BORE_LENGTH, span_length() * (0.5 if mouths().size() > 1 else 1.0))
	var found := PackedFloat64Array()
	var count := maxi(2, ceili(depth / 1.0))
	for i in count + 1:
		found.append(mouth.x + mouth.y * depth * float(i) / float(count))
	return found


## The arch's cross-section as (across, up) above the railhead, from the floor
## on the left round to the floor on the right.
static func _section(bed: float) -> PackedVector2Array:
	var points := PackedVector2Array([Vector2(-OPEN_HALF, bed)])
	for i in 13:
		var angle := PI - PI * float(i) / 12.0
		points.append(Vector2(cos(angle) * OPEN_HALF, SPRINGING + sin(angle) * OPEN_HALF))
	points.append(Vector2(OPEN_HALF, bed))
	return points


## Walls, roof and floor, lit by nothing: bright enough at the portal to read as
## stone, black a few metres in, and closed off by a black wall at the far end.
func _build_bore(surface: MeshSurface, mouth: Vector2) -> void:
	var bed := -rail.surface_offset
	var section := _section(bed)
	var all := _bore_distances(mouth)
	var depth := absf(all[-1] - all[0])
	var frames: Array[Transform3D] = []
	for at in all:
		frames.append(flat_frame(at))
	for i in all.size() - 1:
		var t0 := absf(all[i] - all[0]) / maxf(depth, 1e-3)
		var t1 := absf(all[i + 1] - all[0]) / maxf(depth, 1e-3)
		var c0 := MeshSurface.shade(_STONE, 0.45 * (1.0 - smoothstep(0.0, 0.55, t0)))
		var c1 := MeshSurface.shade(_STONE, 0.45 * (1.0 - smoothstep(0.0, 0.55, t1)))
		var color := c0.lerp(c1, 0.5)
		var a := frames[i]
		var b := frames[i + 1]
		var middle := (a.origin + b.origin) * 0.5 + Vector3.UP * SPRINGING * 0.5
		for k in section.size() - 1:
			var p := section[k]
			var q := section[k + 1]
			var corner_a := a.origin + a.basis.x * p.x + Vector3.UP * p.y
			var corner_b := a.origin + a.basis.x * q.x + Vector3.UP * q.y
			var corner_c := b.origin + b.basis.x * q.x + Vector3.UP * q.y
			var corner_d := b.origin + b.basis.x * p.x + Vector3.UP * p.y
			var edge_middle := (corner_a + corner_c) * 0.5
			surface.add_quad_facing(corner_a, corner_b, corner_c, corner_d,
					middle - edge_middle, color)
		# The floor the cut-away terrain no longer provides.
		var floor_a := a.origin + Vector3.UP * (bed - 0.02)
		var floor_b := b.origin + Vector3.UP * (bed - 0.02)
		surface.add_quad_facing(floor_a - a.basis.x * OPEN_HALF, floor_a + a.basis.x * OPEN_HALF,
				floor_b + b.basis.x * OPEN_HALF, floor_b - b.basis.x * OPEN_HALF,
				Vector3.UP, MeshSurface.shade(color, 0.7))
	# Black end wall, facing back out of the tunnel: a fan round the whole
	# section, the floor edge included.
	var end := frames[-1]
	var towards_mouth := frames[0].origin - end.origin
	for k in section.size():
		var p := section[k]
		var q := section[(k + 1) % section.size()]
		surface.add_triangle_facing(end.origin + Vector3.UP * SPRINGING,
				end.origin + end.basis.x * p.x + Vector3.UP * p.y,
				end.origin + end.basis.x * q.x + Vector3.UP * q.y,
				towards_mouth, Color.BLACK)
#endregion
