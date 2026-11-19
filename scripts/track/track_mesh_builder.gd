class_name TrackMeshBuilder
extends RefCounted
## Turns a [TrackLayout] into meshes: the static track cut into square chunks of
## [constant CHUNK_SIZE] metres - one mesh per chunk, one surface per material -
## and a small mesh per turnout for its two blades, whose second position is a
## blend shape so throwing the points is a single weight to animate.
##
## Chunks are the plan's "reasonable big chunks": a level's whole track is a few
## dozen draw calls, while a camera looking at one corner of it still culls the
## rest. Everything is built in global space; the instances that show it sit at
## the origin.
##
## The ground is asked about through two callables, so the builder needs no
## knowledge of [Ground] or [SurfaceSnapper]: [member ground_height] answers a
## global point with a height or [code]null[/code], [member ground_color] with
## the colour of the ground there. [member ballast_mode] lets a bridge take the
## ballast away (an open deck) or hold it in (a filled deck).

const CHUNK_SIZE := 64.0

enum Ballast {
	## A full bed, its sides running down to the ground.
	BED,
	## Held in by a bridge's parapets: shoulders only, no slope to the ground.
	DECK,
	## None: sleepers on an open deck.
	NONE,
}

const _STEEL_TOP := Color(0.66, 0.66, 0.68)
const _STEEL_SIDE := Color(0.36, 0.25, 0.18)
const _CHECK_SIDE := Color(0.30, 0.27, 0.25)
const _TIMBER := Color(0.36, 0.27, 0.19)
const _STONES := Color(0.52, 0.5, 0.47)
const _BUFFER_RED := Color(0.72, 0.14, 0.1)
const _BUFFER_DARK := Color(0.18, 0.18, 0.2)
const _BUFFER_FACE := Color(0.95, 0.85, 0.2)
## How much of the ground's own colour the top of the bed takes on.
const _BALLAST_BLEND := 0.42
const _SHOULDER := 1.6
const _BLADE_STEP := 0.25

var ground_height: Callable = func(_point: Vector3) -> Variant: return null
var ground_color: Callable = func(_point: Vector3) -> Color: return Color(0.33, 0.42, 0.25)
var ballast_mode: Callable = func(_rail: Rail, _distance: float) -> Ballast: return Ballast.BED

## Per chunk, one [MeshSurface] per material.
var _metal: Dictionary[Vector2i, MeshSurface] = {}
var _wood: Dictionary[Vector2i, MeshSurface] = {}
var _ballast: Dictionary[Vector2i, MeshSurface] = {}


## The static track, chunk by chunk.
func build_chunks(layout: TrackLayout) -> Dictionary[Vector2i, ArrayMesh]:
	for piece in layout.pieces:
		_add_piece(layout, piece)
	for sleeper in layout.sleepers:
		_add_sleeper(sleeper)
	for rail in layout.rails:
		_add_ballast(layout, rail)
	for stop in layout.buffer_stops:
		_add_buffer_stop(stop)

	var meshes: Dictionary[Vector2i, ArrayMesh] = {}
	var cells: Dictionary[Vector2i, bool] = {}
	for table: Dictionary in [_metal, _wood, _ballast]:
		for cell: Vector2i in table:
			cells[cell] = true
	for cell in cells:
		var mesh := ArrayMesh.new()
		if _metal.has(cell):
			_metal[cell].commit(mesh, TrackMaterials.metal())
		if _wood.has(cell):
			_wood[cell].commit(mesh, TrackMaterials.wood())
		if _ballast.has(cell):
			_ballast[cell].commit(mesh, TrackMaterials.ballast())
		if mesh.get_surface_count() > 0:
			meshes[cell] = mesh
	return meshes


## One mesh per turnout holding both its blades, in the normal position, with
## the reverse position as blend shape 0.
static func build_blades(layout: TrackLayout) -> Dictionary[Turnout, ArrayMesh]:
	var by_turnout: Dictionary[Turnout, Array] = {}
	for blade in layout.blades:
		if not by_turnout.has(blade.turnout):
			by_turnout[blade.turnout] = []
		by_turnout[blade.turnout].append(blade)

	var meshes: Dictionary[Turnout, ArrayMesh] = {}
	for turnout in by_turnout:
		var normal := MeshSurface.new()
		var reverse := MeshSurface.new()
		for blade: TrackLayout.Blade in by_turnout[turnout]:
			_add_blade(normal, blade, blade.closed_when == Turnout.Position.NORMAL)
			_add_blade(reverse, blade, blade.closed_when == Turnout.Position.REVERSE)
		if normal.is_empty():
			continue
		var mesh := ArrayMesh.new()
		mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
		mesh.add_blend_shape(&"reverse")
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = normal.vertices
		arrays[Mesh.ARRAY_NORMAL] = normal.normals
		arrays[Mesh.ARRAY_COLOR] = normal.colors
		arrays[Mesh.ARRAY_INDEX] = normal.indices
		var shape := []
		shape.resize(Mesh.ARRAY_MAX)
		shape[Mesh.ARRAY_VERTEX] = reverse.vertices
		shape[Mesh.ARRAY_NORMAL] = reverse.normals
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [shape])
		mesh.surface_set_material(0, TrackMaterials.metal())
		meshes[turnout] = mesh
	return meshes


#region Rails
func _add_piece(layout: TrackLayout, piece: TrackLayout.Piece) -> void:
	var all := TrackLayout.span_stations(layout.stations[piece.rail], piece.from, piece.to)
	if piece.flare > 0.0:
		all = _with_flare_stations(all, piece)
	# Cut long pieces into runs about half a chunk long, each filed under the
	# chunk its middle falls in.
	var run_start := 0
	for i in range(1, all.size()):
		var is_last := i == all.size() - 1
		if is_last or all[i] - all[run_start] >= CHUNK_SIZE * 0.5:
			var centres := PackedVector3Array()
			var rights := PackedVector3Array()
			var ups := PackedVector3Array()
			var widths := PackedFloat32Array()
			for j in range(run_start, i + 1):
				var at := all[j]
				var frame := TrackLayout.frame_at(piece.rail, at)
				var lateral := piece.lateral - signf(piece.lateral) * _flare_at(piece, at)
				centres.append(frame.origin + frame.basis.x * lateral)
				rights.append(frame.basis.x)
				ups.append(frame.basis.y)
				widths.append(TrackLayout.HEAD_WIDTH)
			var middle := centres[centres.size() >> 1]
			var side := _CHECK_SIDE if piece.is_check else _STEEL_SIDE
			extrude_rail(_surface(_metal, middle), centres, rights, ups, widths, side,
					run_start == 0, is_last)
			run_start = i


## How far a check rail's end has bent away from its running rail at [param at].
static func _flare_at(piece: TrackLayout.Piece, at: float) -> float:
	if piece.flare <= 0.0:
		return 0.0
	var into := INF
	if piece.flare_from:
		into = at - piece.from
	if piece.flare_to:
		into = minf(into, piece.to - at)
	return piece.flare * clampf(1.0 - into / TrackLayout.CHECK_FLARE, 0.0, 1.0)


static func _with_flare_stations(all: PackedFloat64Array,
		piece: TrackLayout.Piece) -> PackedFloat64Array:
	var extra := PackedFloat64Array(all)
	if piece.flare_from:
		extra.append(piece.from + TrackLayout.CHECK_FLARE)
	if piece.flare_to:
		extra.append(piece.to - TrackLayout.CHECK_FLARE)
	extra.sort()
	var cleaned := PackedFloat64Array()
	for at in extra:
		if at >= piece.from and at <= piece.to and (cleaned.is_empty() or at - cleaned[-1] > 1e-3):
			cleaned.append(at)
	return cleaned


## A rail's cross-section - head, web, foot - for a railhead [param head]
## metres wide, as (across, up) from the middle of the railhead's top. Runs round
## the outline so that each edge's outward normal is its direction turned left.
static func rail_profile(head: float) -> PackedVector2Array:
	var hh := TrackLayout.HEAD_HEIGHT
	var rh := TrackLayout.RAIL_HEIGHT
	var fh := TrackLayout.FOOT_HEIGHT
	var w := TrackLayout.WEB_WIDTH * 0.5
	var f := TrackLayout.FOOT_WIDTH * 0.5
	var h := head * 0.5
	return PackedVector2Array([
		Vector2(-h, 0.0), Vector2(h, 0.0), Vector2(h, -hh), Vector2(w, -hh),
		Vector2(w, -rh + fh), Vector2(f, -rh + fh), Vector2(f, -rh), Vector2(-f, -rh),
		Vector2(-f, -rh + fh), Vector2(-w, -rh + fh), Vector2(-w, -hh), Vector2(-h, -hh),
	])


## Sweeps [method rail_profile] through [param centres]. Edges share vertices
## along the rail, so a long straight is two vertices per edge per sample. The
## underside of the foot is left out; the ends get caps where asked.
static func extrude_rail(surface: MeshSurface, centres: PackedVector3Array,
		rights: PackedVector3Array, ups: PackedVector3Array, heads: PackedFloat32Array,
		side_color: Color, cap_start: bool, cap_end: bool) -> void:
	var count := centres.size()
	if count < 2:
		return
	const EDGES := 12
	const BOTTOM := 6
	var base := surface.vertices.size()
	for i in count:
		var outline := rail_profile(heads[i])
		for e in EDGES:
			if e == BOTTOM:
				continue
			var p := outline[e]
			var q := outline[(e + 1) % EDGES]
			var d := q - p
			var n := Vector2(-d.y, d.x).normalized()
			var normal := (rights[i] * n.x + ups[i] * n.y).normalized()
			var color := _STEEL_TOP if e == 0 else side_color
			surface.vertices.append(centres[i] + rights[i] * p.x + ups[i] * p.y)
			surface.vertices.append(centres[i] + rights[i] * q.x + ups[i] * q.y)
			surface.normals.append(normal)
			surface.normals.append(normal)
			surface.colors.append(color)
			surface.colors.append(color)

	# Pick the winding once, from the top face of the first step: Godot's front
	# face is the one whose (b - a) x (c - a) points away from the viewer.
	var per_station := (EDGES - 1) * 2
	var a := surface.vertices[base]
	var b := surface.vertices[base + 1]
	var c := surface.vertices[base + per_station + 1]
	var flip := (b - a).cross(c - a).dot(surface.normals[base]) > 0.0
	for i in count - 1:
		for slot in EDGES - 1:
			var v0 := base + i * per_station + slot * 2
			var v1 := v0 + 1
			var v2 := v1 + per_station
			var v3 := v0 + per_station
			if flip:
				surface.indices.append_array(PackedInt32Array([v0, v2, v1, v0, v3, v2]))
			else:
				surface.indices.append_array(PackedInt32Array([v0, v1, v2, v0, v2, v3]))

	if cap_start:
		_cap(surface, centres[0], rights[0], ups[0], heads[0], centres[0] - centres[1],
				side_color)
	if cap_end:
		_cap(surface, centres[-1], rights[-1], ups[-1], heads[-1], centres[-1] - centres[-2],
				side_color)


static func _cap(surface: MeshSurface, centre: Vector3, right: Vector3, up: Vector3,
		head: float, outward: Vector3, color: Color) -> void:
	var rects: Array[Rect2] = [
		Rect2(-head * 0.5, -TrackLayout.HEAD_HEIGHT, head, TrackLayout.HEAD_HEIGHT),
		Rect2(-TrackLayout.WEB_WIDTH * 0.5, -TrackLayout.RAIL_HEIGHT,
				TrackLayout.WEB_WIDTH, TrackLayout.RAIL_HEIGHT - TrackLayout.HEAD_HEIGHT),
		Rect2(-TrackLayout.FOOT_WIDTH * 0.5, -TrackLayout.RAIL_HEIGHT,
				TrackLayout.FOOT_WIDTH, TrackLayout.FOOT_HEIGHT),
	]
	for rect in rects:
		var corners: Array[Vector3] = []
		for corner: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
				Vector2(rect.position.x, rect.end.y)]:
			corners.append(centre + right * corner.x + up * corner.y)
		surface.add_quad_facing(corners[0], corners[1], corners[2], corners[3], outward, color)


static func _add_blade(surface: MeshSurface, blade: TrackLayout.Blade, closed: bool) -> void:
	var centres := PackedVector3Array()
	var rights := PackedVector3Array()
	var ups := PackedVector3Array()
	var heads := PackedFloat32Array()
	var along := 0.0
	while true:
		var frame := TrackLayout.frame_at(blade.line.rail,
				blade.start + float(blade.direction) * along)
		centres.append(TrackLayout.blade_point(blade, along, closed))
		# Turned to face the way the blade runs, so a blade drawn against its
		# rail's direction keeps the same winding as one drawn along it.
		rights.append(frame.basis.x * float(blade.direction))
		ups.append(frame.basis.y)
		heads.append(TrackLayout.blade_head_width(along))
		if along >= blade.heel:
			break
		along = minf(along + (_BLADE_STEP if along < TrackLayout.BLADE_TAPER else 0.5),
				blade.heel)
	extrude_rail(surface, centres, rights, ups, heads, _STEEL_SIDE, true, false)
#endregion


#region Sleepers and ballast
func _add_sleeper(sleeper: TrackLayout.Sleeper) -> void:
	var frame := sleeper.frame
	var middle := frame.origin + frame.basis.x * ((sleeper.lo + sleeper.hi) * 0.5) \
			- frame.basis.y * (TrackLayout.SLEEPER_HEIGHT * 0.5)
	# Not every sleeper the same brown.
	var shade := 0.88 + 0.24 * fposmod(sin(sleeper.distance * 12.9898) * 43758.5453, 1.0)
	var color := Color(_TIMBER.r * shade, _TIMBER.g * shade, _TIMBER.b * shade)
	_surface(_wood, middle).add_box(Transform3D(frame.basis, middle),
			Vector3(sleeper.hi - sleeper.lo, TrackLayout.SLEEPER_HEIGHT,
			TrackLayout.SLEEPER_WIDTH), color, false)


## A trapezoid under the sleepers: a flat top a little wider than they are, and
## sides running down to wherever the ground is - which is what hides the
## sleepers' ends hanging over a dip or burying themselves in a bump. The top
## takes on some of the ground's colour and the toes all of it, so the bed
## reads as stones half grown over rather than a grey ribbon laid on the grass.
func _add_ballast(layout: TrackLayout, rail: Rail) -> void:
	var all := layout.stations[rail]
	var top_drop := TrackLayout.RAIL_HEIGHT + TrackLayout.SLEEPER_HEIGHT * 0.6
	var previous: Array[Vector3] = []
	var previous_colors: Array[Color] = []
	var previous_mode := Ballast.NONE
	for i in all.size():
		var at := all[i]
		var mode: Ballast = ballast_mode.call(rail, at)
		var frame := TrackLayout.frame_at(rail, at)
		var flat := Vector3(frame.basis.x.x, 0.0, frame.basis.x.z).normalized()
		var top := frame.origin - frame.basis.y * top_drop
		var row: Array[Vector3] = []
		var colors: Array[Color] = []
		var shoulder_l := top - frame.basis.x * _SHOULDER
		var shoulder_r := top + frame.basis.x * _SHOULDER
		var toe_l := _toe(top, shoulder_l, -flat, mode)
		var toe_r := _toe(top, shoulder_r, flat, mode)
		var ground_l: Color = ground_color.call(toe_l)
		var ground_r: Color = ground_color.call(toe_r)
		row.assign([toe_l, shoulder_l, shoulder_r, toe_r])
		colors.assign([ground_l, _STONES.lerp(ground_l, _BALLAST_BLEND),
				_STONES.lerp(ground_r, _BALLAST_BLEND), ground_r])
		if not previous.is_empty() and mode != Ballast.NONE and previous_mode != Ballast.NONE:
			var surface := _surface(_ballast, top)
			for k in 3:
				_ballast_quad(surface, previous[k], previous[k + 1], row[k + 1], row[k],
						previous_colors[k], previous_colors[k + 1], colors[k + 1], colors[k])
		previous = row
		previous_colors = colors
		previous_mode = mode


## Where the side of the bed meets the ground, beyond [param shoulder] along
## [param outward]: a 1:1.5 slope down to the ground, buried a little so no
## seam shows. On a bridge's deck it only drops to the deck.
func _toe(top: Vector3, shoulder: Vector3, outward: Vector3, mode: Ballast) -> Vector3:
	if mode == Ballast.DECK:
		return shoulder + outward * 0.3 + Vector3.DOWN * 0.2
	var drop := 0.2
	for attempt in 2:
		var guess := shoulder + outward * (drop * 1.5)
		var height = ground_height.call(guess)
		var ground_y: float = top.y - 0.2 if height == null else float(height)
		drop = clampf(top.y - ground_y + 0.05, 0.08, 6.0)
	var toe := shoulder + outward * (drop * 1.5)
	toe.y = top.y - drop
	return toe


static func _ballast_quad(surface: MeshSurface, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	var normal := (b - a).cross(d - a)
	if normal.y < 0.0:
		normal = -normal
	normal = normal.normalized() if normal.length_squared() > 1e-12 else Vector3.UP
	var base := surface.vertices.size()
	surface.vertices.append_array(PackedVector3Array([a, b, c, d]))
	surface.normals.append_array(PackedVector3Array([normal, normal, normal, normal]))
	surface.colors.append_array(PackedColorArray([ca, cb, cc, cd]))
	# Whichever way the quad was wound, the face that looks up is the front.
	if (b - a).cross(c - a).dot(normal) > 0.0:
		surface.indices.append_array(PackedInt32Array([base, base + 2, base + 1,
				base, base + 3, base + 2]))
	else:
		surface.indices.append_array(PackedInt32Array([base, base + 1, base + 2,
				base, base + 2, base + 3]))
#endregion


#region Buffer stops
## A red beam on two posts with a pair of buffers facing the track, braced back
## to the rails behind it.
func _add_buffer_stop(stop: TrackLayout.BufferStop) -> void:
	var f := stop.frame
	var surface := _surface(_metal, f.origin)
	var beam_y := 0.95
	surface.add_box(f * Transform3D(Basis.IDENTITY, Vector3(0.0, beam_y, -0.2)),
			Vector3(2.4, 0.4, 0.3), _BUFFER_RED)
	for x: float in [-0.85, 0.85]:
		surface.add_box(f * Transform3D(Basis.IDENTITY, Vector3(x, beam_y, 0.12)),
				Vector3(0.34, 0.34, 0.34), _BUFFER_DARK)
		surface.add_box(f * Transform3D(Basis.IDENTITY, Vector3(x, beam_y, 0.3)),
				Vector3(0.42, 0.42, 0.04), _BUFFER_FACE)
		var post_x := x * 0.88
		surface.add_box(f * Transform3D(Basis.IDENTITY,
				Vector3(post_x, (beam_y - TrackLayout.RAIL_HEIGHT) * 0.5, -0.3)),
				Vector3(0.18, beam_y + TrackLayout.RAIL_HEIGHT, 0.18), _BUFFER_DARK)
		surface.add_beam(f * Vector3(post_x, beam_y - 0.1, -0.35),
				f * Vector3(post_x, -0.05, -1.05), 0.14, 0.14, _BUFFER_DARK)
#endregion


static func cell_of(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / CHUNK_SIZE), floori(point.z / CHUNK_SIZE))


static func _surface(table: Dictionary[Vector2i, MeshSurface], point: Vector3) -> MeshSurface:
	var cell := cell_of(point)
	if not table.has(cell):
		table[cell] = MeshSurface.new()
	return table[cell]
