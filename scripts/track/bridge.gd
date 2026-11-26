@tool
class_name Bridge
extends TrackStructure
## A bridge carrying [member TrackStructure.rail] over whatever is below it, in
## one of three styles. Each copes with a long span its own way:
##
## - [b]Stone arch[/b]: a viaduct of arches about [constant _ARCH_LENGTH] metres
##   each, piers down to the ground between them. Its deck is filled, so the
##   ballast carries on over it between the parapets.
## - [b]Steel truss[/b]: a through truss per span, the track running inside it,
##   with a pier wherever a span would be longer than
##   [constant _MAX_TRUSS_SPAN]. Trusses are straight, so a curved bridge is
##   split into more, shorter spans until the track stays well inside them.
## - [b]Wooden trestle[/b]: timber bents every few metres along the whole length,
##   braced in storeys as they get taller.
##
## Truss and trestle carry no ballast: the sleepers lie on a deck of their own -
## steel plate between the trusses, planking across the trestle's caps - with
## stringers under it.

enum Style { STONE_ARCH, STEEL_TRUSS, WOODEN_TRESTLE }

@export var style := Style.STONE_ARCH:
	set(value):
		style = value
		_changed()

const _STONE := Color(0.64, 0.6, 0.53)
const _STONE_DARK := Color(0.5, 0.47, 0.42)
const _COPING := Color(0.74, 0.71, 0.65)
const _STEEL := Color(0.3, 0.36, 0.35)
const _TIMBER := Color(0.45, 0.36, 0.27)

## The stone viaduct: deck width to the outer faces, parapet height and thickness.
const _ARCH_LENGTH := 16.0
const _VIADUCT_HALF_WIDTH := 2.4
const _PARAPET_HEIGHT := 0.9
const _PARAPET_THICKNESS := 0.4
## Ballast top sits this far below the railhead; the filled deck under it.
const _DECK_DROP := 0.42
## Solid stone carries on past each end of the span, into the bank.
const _ABUTMENT := 3.0

const _MAX_TRUSS_SPAN := 40.0
## How far a curved track may bow away from a straight truss's centre line.
const _MAX_TRUSS_BOW := 0.45
const _TRUSS_HALF_WIDTH := 2.7
const _TRUSS_MIN_HEIGHT := 6.5

const _BENT_SPACING := 4.5
const _STOREY := 6.0

## Under the sleepers of a truss or a trestle: the deck's half width and
## thickness, and the depth of the trestle's stringers.
const _STEEL_DECK_HALF := 2.2
const _TIMBER_DECK_HALF := 1.8
const _DECK_THICKNESS := 0.08
const _STRINGER_DEPTH := 0.4


func ballast_mode() -> TrackMeshBuilder.Ballast:
	return TrackMeshBuilder.Ballast.DECK if style == Style.STONE_ARCH else TrackMeshBuilder.Ballast.NONE


func _build_mesh(surfaces: Array[SurfaceSnapper.Surface]) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	match style:
		Style.STONE_ARCH:
			var stone := MeshSurface.new()
			_build_viaduct(stone, surfaces)
			stone.commit(mesh, TrackMaterials.stone())
		Style.STEEL_TRUSS:
			var steel := MeshSurface.new()
			var stone := MeshSurface.new()
			_build_truss(steel, stone, surfaces)
			steel.commit(mesh, TrackMaterials.metal())
			stone.commit(mesh, TrackMaterials.stone())
		Style.WOODEN_TRESTLE:
			var timber := MeshSurface.new()
			_build_trestle(timber, surfaces)
			timber.commit(mesh, TrackMaterials.wood())
	return mesh


## Where the arches are: the n spans the length is divided into, as distances
## along the rail, and the pier thickness between them.
func arch_spans() -> Array[Vector2]:
	var length := span_length()
	var count := maxi(1, roundi(length / _ARCH_LENGTH))
	var each := length / float(count)
	var pier := clampf(each * 0.16, 1.2, 3.0)
	var spans: Array[Vector2] = []
	for i in count:
		var from := start_distance() + each * float(i) + (pier * 0.5 if i > 0 else 0.0)
		var to := start_distance() + each * float(i + 1) - (pier * 0.5 if i < count - 1 else 0.0)
		spans.append(Vector2(from, to))
	return spans


## Distances along the rail at which each truss starts and ends: enough spans
## that none is longer than [constant _MAX_TRUSS_SPAN] and the track never
## bows more than [constant _MAX_TRUSS_BOW] off a straight one's centre line.
func truss_joints() -> PackedFloat64Array:
	var count := maxi(1, ceili(span_length() / _MAX_TRUSS_SPAN))
	while count < 64:
		var joints := distances(start_distance(), end_distance(), span_length() / float(count))
		var straight := true
		for i in joints.size() - 1:
			var a := rail.sample_position(joints[i])
			var b := rail.sample_position(joints[i + 1])
			for at in distances(joints[i], joints[i + 1], 1.0):
				var p := rail.sample_position(at)
				var t := clampf((p - a).dot(b - a) / maxf((b - a).length_squared(), 1e-6), 0.0, 1.0)
				if p.distance_to(a.lerp(b, t)) > _MAX_TRUSS_BOW:
					straight = false
					break
			if not straight:
				break
		if straight:
			return joints
		count += 1
	return distances(start_distance(), end_distance(), span_length() / float(count))


#region Stone arch viaduct
## The viaduct is one solid of stone whose underside follows the arches: two
## outer walls from the parapet top down to that underside, the underside itself,
## the deck between the parapets, the parapets' inner faces and tops, and the
## end walls. Piers get buttresses so they read as piers.
func _build_viaduct(surface: MeshSurface, surfaces: Array[SurfaceSnapper.Surface]) -> void:
	var spans := arch_spans()
	var from := start_distance() - _ABUTMENT
	var to := end_distance() + _ABUTMENT
	var stations := distances(maxf(from, 0.0), minf(to, rail.rail_length()), 0.5)
	var deck_top := -_DECK_DROP
	var outer := _VIADUCT_HALF_WIDTH
	var inner := _VIADUCT_HALF_WIDTH - _PARAPET_THICKNESS
	var bed := rail.surface_offset

	# Per span, its arch as (springing y, rise, half chord).
	var arches: Array[Vector3] = []
	for span in spans:
		var crown := flat_frame((span.x + span.y) * 0.5).origin.y + deck_top - 0.9
		var lowest_ground := INF
		for at in distances(span.x, span.y, 1.0):
			var p := flat_frame(at).origin
			lowest_ground = minf(lowest_ground, ground_y(surfaces, p, p.y - bed))
		var half_chord := (span.y - span.x) * 0.5
		var rise := clampf(crown - (lowest_ground + 0.4), 0.6, half_chord)
		arches.append(Vector3(crown - rise, rise, half_chord))

	var tops_l := PackedVector3Array()
	var tops_r := PackedVector3Array()
	var bottoms_l := PackedVector3Array()
	var bottoms_r := PackedVector3Array()
	var decks_l := PackedVector3Array()
	var decks_r := PackedVector3Array()
	var rights := PackedVector3Array()
	for at in stations:
		var frame := flat_frame(at)
		var right := frame.basis.x
		var top_y := frame.origin.y + deck_top + _PARAPET_HEIGHT
		var deck_y := frame.origin.y + deck_top
		var bottom_y := _underside(at, spans, arches, frame, surfaces)
		var middle := frame.origin
		tops_l.append(Vector3(middle.x, top_y, middle.z) - right * outer)
		tops_r.append(Vector3(middle.x, top_y, middle.z) + right * outer)
		bottoms_l.append(Vector3(middle.x, bottom_y, middle.z) - right * outer)
		bottoms_r.append(Vector3(middle.x, bottom_y, middle.z) + right * outer)
		decks_l.append(Vector3(middle.x, deck_y, middle.z) - right * inner)
		decks_r.append(Vector3(middle.x, deck_y, middle.z) + right * inner)
		rights.append(right)

	var lefts := negated(rights)
	var downs := PackedVector3Array([Vector3.DOWN])
	var ups := PackedVector3Array([Vector3.UP])
	surface.add_strip(tops_l, bottoms_l, lefts, _STONE)
	surface.add_strip(tops_r, bottoms_r, rights, _STONE)
	surface.add_strip(bottoms_l, bottoms_r, downs, _STONE_DARK)
	surface.add_strip(decks_l, decks_r, ups, _STONE_DARK)
	# Parapets: inner faces down to the deck, and a coping along the top.
	var lip_l := PackedVector3Array()
	var lip_r := PackedVector3Array()
	var lift := Vector3.UP * _PARAPET_HEIGHT
	for i in stations.size():
		lip_l.append(decks_l[i] + lift)
		lip_r.append(decks_r[i] + lift)
	surface.add_strip(lip_l, decks_l, rights, _STONE)
	surface.add_strip(lip_r, decks_r, lefts, _STONE)
	surface.add_strip(tops_l, lip_l, ups, _COPING)
	surface.add_strip(lip_r, tops_r, ups, _COPING)
	# End walls, where the abutments meet the bank.
	for end: int in [0, stations.size() - 1]:
		var along := flat_frame(stations[end]).basis.z * (1.0 if end == 0 else -1.0)
		surface.add_quad_facing(tops_l[end], tops_r[end], bottoms_r[end], bottoms_l[end],
				along, _STONE)

	# Buttresses on the piers: a little proud of the walls, up to the springing.
	for i in range(1, spans.size()):
		var at := (spans[i - 1].y + spans[i].x) * 0.5
		var thickness := spans[i].x - spans[i - 1].y
		var frame := flat_frame(at)
		var top := minf(arches[i - 1].x, arches[i].x) + 0.4
		var foot := ground_y(surfaces, frame.origin, frame.origin.y - bed) - 1.0
		if top <= foot:
			continue
		var centre := Vector3(frame.origin.x, (top + foot) * 0.5, frame.origin.z)
		surface.add_box(Transform3D(frame.basis, centre),
				Vector3(outer * 2.0 + 0.7, top - foot, thickness + 0.5), _STONE_DARK)


## Height of the viaduct's underside at [param at]: the arch where there is one,
## below the ground under piers and abutments.
func _underside(at: float, spans: Array[Vector2], arches: Array[Vector3], frame: Transform3D,
		surfaces: Array[SurfaceSnapper.Surface]) -> float:
	for i in spans.size():
		var span := spans[i]
		if at > span.x and at < span.y:
			var springing := arches[i].x
			var rise := arches[i].y
			var half := arches[i].z
			# A segmental arch: a circle through both springings and the crown.
			var radius := (half * half + rise * rise) / (2.0 * rise)
			var x := at - (span.x + span.y) * 0.5
			return springing + sqrt(maxf(radius * radius - x * x, 0.0)) - (radius - rise)
	var ground := ground_y(surfaces, frame.origin, frame.origin.y - rail.surface_offset)
	return minf(ground - 1.0, frame.origin.y - _DECK_DROP - 1.0)
#endregion


#region Steel truss
## Per span: two trusses either side of the track, cross girders and stringers
## under it, bracing across the top, and stone piers and abutments to stand on.
func _build_truss(steel: MeshSurface, stone: MeshSurface,
		surfaces: Array[SurfaceSnapper.Surface]) -> void:
	var joints := truss_joints()
	var deck_drop := TrackLayout.RAIL_HEIGHT + TrackLayout.SLEEPER_HEIGHT
	_add_deck(steel, _STEEL_DECK_HALF, _STEEL)
	# The cross girders' tops are 0.25 over the bottom chords; the stringers fill
	# the depth between them and the deck plate.
	var chord_y := -deck_drop - 0.5
	var plate_bottom := -deck_drop - _DECK_THICKNESS
	var stringer_depth := plate_bottom - (chord_y + 0.25)
	var stringer_y := plate_bottom - stringer_depth * 0.5
	for i in joints.size() - 1:
		var a := rail.sample_position(joints[i])
		var b := rail.sample_position(joints[i + 1])
		var along := (b - a)
		var length := along.length()
		if length < 1.0:
			continue
		var forward := Vector3(along.x, 0.0, along.z).normalized()
		var right := forward.cross(Vector3.UP).normalized()
		var height := maxf(_TRUSS_MIN_HEIGHT, length * 0.16)
		var panels := maxi(3, roundi(length / 5.0))
		for side: float in [-1.0, 1.0]:
			var offset := right * _TRUSS_HALF_WIDTH * side
			var bottom := PackedVector3Array()
			var top := PackedVector3Array()
			for p in panels + 1:
				var point := a.lerp(b, float(p) / float(panels)) + offset + Vector3.UP * chord_y
				bottom.append(point)
				top.append(point + Vector3.UP * height)
			steel.add_beam(bottom[0], bottom[panels], 0.45, 0.6, _STEEL)
			steel.add_beam(top[1], top[panels - 1], 0.5, 0.45, _STEEL)
			# Inclined end posts, verticals, and diagonals sloping down towards
			# the middle of the span.
			steel.add_beam(bottom[0], top[1], 0.45, 0.45, _STEEL, right)
			steel.add_beam(bottom[panels], top[panels - 1], 0.45, 0.45, _STEEL, right)
			for p in range(1, panels):
				steel.add_beam(bottom[p], top[p], 0.3, 0.3, _STEEL, right)
			for p in range(1, panels - 1):
				if p * 2 < panels:
					steel.add_beam(top[p], bottom[p + 1], 0.22, 0.22, _STEEL, right)
				else:
					steel.add_beam(bottom[p], top[p + 1], 0.22, 0.22, _STEEL, right)
		# Floor: a cross girder at every panel point, two stringers under the rails.
		for p in panels + 1:
			var centre := a.lerp(b, float(p) / float(panels)) + Vector3.UP * chord_y
			steel.add_beam(centre - right * _TRUSS_HALF_WIDTH, centre + right * _TRUSS_HALF_WIDTH,
					0.3, 0.5, _STEEL)
			# Top bracing between the trusses, clear of the tallest train.
			if p >= 1 and p <= panels - 1:
				var lift := Vector3.UP * height
				steel.add_beam(centre - right * _TRUSS_HALF_WIDTH + lift,
						centre + right * _TRUSS_HALF_WIDTH + lift, 0.25, 0.25, _STEEL)
		for x: float in [-0.75, 0.75]:
			var lift := Vector3.UP * stringer_y
			steel.add_beam(a + right * x + lift, b + right * x + lift, 0.25, stringer_depth,
					_STEEL)

	# A pier under every joint between spans, an abutment under each end.
	for i in joints.size():
		var frame := flat_frame(joints[i])
		var top := frame.origin.y - deck_drop - 0.8
		var foot := ground_y(surfaces, frame.origin, frame.origin.y - rail.surface_offset) - 1.0
		var is_end := i == 0 or i == joints.size() - 1
		var length := 4.0 if is_end else 2.4
		var centre_along := 0.0
		if is_end:
			# Abutments sit back into the bank, behind the bearing.
			centre_along = 1.2 if i == 0 else -1.2
		if top <= foot:
			continue
		var centre := frame.origin + frame.basis.z * centre_along
		centre.y = (top + foot) * 0.5
		stone.add_box(Transform3D(frame.basis, centre),
				Vector3(_TRUSS_HALF_WIDTH * 2.0 + 1.4, top - foot, length), _STONE)
#endregion


#region Wooden trestle
## A bent every [constant _BENT_SPACING] metres: two plumb posts under the rails,
## two raked ones outside them, a cap on top, and girts and cross-bracing for
## every [constant _STOREY] metres of height. Stringers run from cap to cap.
func _build_trestle(timber: MeshSurface, surfaces: Array[SurfaceSnapper.Surface]) -> void:
	# Down from the railhead: rail, sleeper, planking, stringers, then the cap,
	# whose middle this is.
	var stringer_drop := TrackLayout.RAIL_HEIGHT + TrackLayout.SLEEPER_HEIGHT + _DECK_THICKNESS \
			+ _STRINGER_DEPTH * 0.5
	var cap_drop := stringer_drop + _STRINGER_DEPTH * 0.5 + 0.175
	_add_deck(timber, _TIMBER_DECK_HALF, _TIMBER)
	var bents := distances(start_distance(), end_distance(), _BENT_SPACING)
	var caps: Array[Vector3] = []
	var rights: Array[Vector3] = []
	for at in bents:
		var frame := flat_frame(at)
		var right := frame.basis.x
		var cap := frame.origin + Vector3.DOWN * cap_drop
		var ground := ground_y(surfaces, frame.origin, frame.origin.y - rail.surface_offset)
		var foot_y := ground - 0.4
		var height := cap.y - foot_y
		caps.append(cap)
		rights.append(right)
		if height < 0.3:
			continue
		var rake := 0.14 * height
		timber.add_beam(cap - right * 2.0, cap + right * 2.0, 0.35, 0.35,
				_TIMBER, Vector3.UP)
		for x: float in [-0.8, 0.8]:
			timber.add_beam(cap + right * x, Vector3(cap.x, foot_y, cap.z) + right * x,
					0.3, 0.3, _TIMBER, frame.basis.z)
		for side: float in [-1.0, 1.0]:
			timber.add_beam(cap + right * (1.6 * side),
					Vector3(cap.x, foot_y, cap.z) + right * ((1.6 + rake) * side),
					0.3, 0.3, _TIMBER, frame.basis.z)
		# Storeys: a girt across at each level and an X between the raked posts.
		var storeys := maxi(1, ceili(height / _STOREY))
		for s in storeys:
			var upper := float(s) / float(storeys)
			var lower := float(s + 1) / float(storeys)
			var y_up := cap.y - height * upper
			var y_low := cap.y - height * lower
			var half_up := 1.6 + rake * upper
			var half_low := 1.6 + rake * lower
			var at_up := Vector3(cap.x, y_up, cap.z)
			var at_low := Vector3(cap.x, y_low, cap.z)
			timber.add_beam(at_low - right * half_low, at_low + right * half_low, 0.22, 0.22,
					_TIMBER)
			var near := frame.basis.z * 0.25
			timber.add_beam(at_up - right * half_up + near, at_low + right * half_low + near,
					0.12, 0.2, _TIMBER, frame.basis.z)
			timber.add_beam(at_up + right * half_up - near, at_low - right * half_low - near,
					0.12, 0.2, _TIMBER, frame.basis.z)
	for i in caps.size() - 1:
		for x: float in [-1.45, -0.75, 0.75, 1.45]:
			var lift := Vector3.UP * (cap_drop - stringer_drop)
			timber.add_beam(caps[i] + rights[i] * x + lift, caps[i + 1] + rights[i + 1] * x + lift,
					0.25, _STRINGER_DEPTH, _TIMBER)
#endregion


## The deck the sleepers lie on: a slab [param half_width] either side of the
## track and [constant _DECK_THICKNESS] thick, following the track itself rather
## than the girders - on a curve the track bows across a straight truss.
func _add_deck(surface: MeshSurface, half_width: float, color: Color) -> void:
	var top_drop := TrackLayout.RAIL_HEIGHT + TrackLayout.SLEEPER_HEIGHT
	var top_l := PackedVector3Array()
	var top_r := PackedVector3Array()
	var bottom_l := PackedVector3Array()
	var bottom_r := PackedVector3Array()
	var rights := PackedVector3Array()
	for at in distances(start_distance(), end_distance(), 1.0):
		var frame := flat_frame(at)
		var right := frame.basis.x * half_width
		var top := frame.origin + Vector3.DOWN * top_drop
		var bottom := top + Vector3.DOWN * _DECK_THICKNESS
		top_l.append(top - right)
		top_r.append(top + right)
		bottom_l.append(bottom - right)
		bottom_r.append(bottom + right)
		rights.append(frame.basis.x)
	surface.add_strip(top_l, top_r, PackedVector3Array([Vector3.UP]), color)
	surface.add_strip(bottom_l, bottom_r, PackedVector3Array([Vector3.DOWN]), color)
	surface.add_strip(top_l, bottom_l, negated(rights), color)
	surface.add_strip(top_r, bottom_r, rights, color)
	for end: int in [0, top_l.size() - 1]:
		var along := (top_l[mini(end + 1, top_l.size() - 1)] - top_l[maxi(end - 1, 0)]) \
				* (-1.0 if end == 0 else 1.0)
		surface.add_quad_facing(top_l[end], top_r[end], bottom_r[end], bottom_l[end], along,
				color)
