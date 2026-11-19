class_name MeshSurface
extends RefCounted
## One surface of a generated mesh, collected vertex by vertex: positions,
## normals, colours and an index list, plus the handful of shapes the track and
## its structures are made of - quads, strips, boxes and beams.
##
## Flat-shaded throughout: every face gets its own vertices, so edges stay sharp
## and nothing has to work out shared normals. Colours are authored in sRGB, as
## by eye; the materials in [TrackMaterials] set
## [member BaseMaterial3D.vertex_color_is_srgb] to match.

var vertices := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var indices := PackedInt32Array()


func is_empty() -> bool:
	return indices.is_empty()


func vertex_count() -> int:
	return vertices.size()


## A flat quad, corners in order round its edge. Godot's front face is the
## clockwise one, so the quad is visible from the side opposite
## [code](b - a).cross(c - a)[/code]; [method add_quad_facing] works that out
## for you.
func add_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 1e-14:
		normal = (c - a).cross(d - a)
	normal = -normal.normalized() if normal.length_squared() > 1e-14 else Vector3.UP
	var base := vertices.size()
	vertices.append_array(PackedVector3Array([a, b, c, d]))
	normals.append_array(PackedVector3Array([normal, normal, normal, normal]))
	colors.append_array(PackedColorArray([color, color, color, color]))
	indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))


## A quad facing [param outward]: whichever winding the corners came in, the
## face ends up visible from that side. For the shapes where working out the
## winding by hand is more error-prone than it is worth.
func add_quad_facing(a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3,
		color: Color) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 1e-14:
		normal = (c - a).cross(d - a)
	if normal.dot(outward) <= 0.0:
		add_quad(a, b, c, d, color)
	else:
		add_quad(d, c, b, a, color)


func add_triangle_facing(a: Vector3, b: Vector3, c: Vector3, outward: Vector3,
		color: Color) -> void:
	var normal := (b - a).cross(c - a)
	if normal.dot(outward) < 0.0:
		var swap := b
		b = c
		c = swap
		normal = -normal
	normal = normal.normalized() if normal.length_squared() > 1e-14 else outward.normalized()
	var base := vertices.size()
	vertices.append_array(PackedVector3Array([a, c, b]))
	normals.append_array(PackedVector3Array([normal, normal, normal]))
	colors.append_array(PackedColorArray([color, color, color]))
	indices.append_array(PackedInt32Array([base, base + 1, base + 2]))


## A box in [param frame]: centred on its origin, [param size] along its own
## axes. The bottom face is left out when [param bottom] is false, for things
## that sit on something and are never seen from below.
func add_box(frame: Transform3D, size: Vector3, color: Color, bottom := true) -> void:
	var h := size * 0.5
	var c: Array[Vector3] = []
	for corner in 8:
		c.append(frame * Vector3(
				h.x if corner & 1 else -h.x,
				h.y if corner & 2 else -h.y,
				h.z if corner & 4 else -h.z))
	var centre := frame.origin
	# Each face as four corner indices; the facing helper sorts out the winding.
	var faces: Array[PackedInt32Array] = [
		PackedInt32Array([1, 3, 7, 5]), # +x
		PackedInt32Array([0, 4, 6, 2]), # -x
		PackedInt32Array([2, 6, 7, 3]), # +y
		PackedInt32Array([4, 5, 7, 6]), # +z
		PackedInt32Array([0, 2, 3, 1]), # -z
	]
	if bottom:
		faces.append(PackedInt32Array([0, 1, 5, 4])) # -y
	for face in faces:
		var a := c[face[0]]
		var b := c[face[1]]
		var cc := c[face[2]]
		var d := c[face[3]]
		var middle := (a + b + cc + d) * 0.25
		add_quad_facing(a, b, cc, d, middle - centre, color)


## A beam of rectangular section from [param from] to [param to]: [param width]
## across, [param height] along [param up] as far as the beam's direction allows.
func add_beam(from: Vector3, to: Vector3, width: float, height: float, color: Color,
		up := Vector3.UP) -> void:
	var along := to - from
	var length := along.length()
	if length < 1e-4:
		return
	var forward := along / length
	if absf(forward.dot(up.normalized())) > 0.98:
		up = Vector3.FORWARD if absf(forward.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var basis := Rail.basis_from_forward_up(forward, up)
	add_box(Transform3D(basis, (from + to) * 0.5), Vector3(width, height, length), color)


## A ribbon through two rows of points, quad by quad - a wall, a deck, a soffit.
## [param outward] says which side is the visible one at each step; pass one
## vector per point, or a single one for the whole strip.
func add_strip(left: PackedVector3Array, right: PackedVector3Array,
		outward: PackedVector3Array, color: Color) -> void:
	for i in mini(left.size(), right.size()) - 1:
		var facing := outward[mini(i, outward.size() - 1)]
		add_quad_facing(left[i], left[i + 1], right[i + 1], right[i], facing, color)


## Appends everything collected onto [param mesh] as one surface.
func commit(mesh: ArrayMesh, material: Material) -> void:
	if is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)


## The bounding box of everything collected, for the culling AABB of a chunk.
func aabb() -> AABB:
	if vertices.is_empty():
		return AABB()
	var box := AABB(vertices[0], Vector3.ZERO)
	for v in vertices:
		box = box.expand(v)
	return box
