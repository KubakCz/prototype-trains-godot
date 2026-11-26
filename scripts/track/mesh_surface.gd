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


## A quad seen from above, a colour per corner - the ballast's bed, shading
## into the ground. Lit as its corners [param a], [param b], [param d] lie,
## turned upward whichever way they were wound.
func add_quad_up(a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	var normal := (b - a).cross(d - a)
	if normal.y < 0.0:
		normal = -normal
	normal = normal.normalized() if normal.length_squared() > 1e-12 else Vector3.UP
	var base := vertices.size()
	vertices.append_array(PackedVector3Array([a, b, c, d]))
	normals.append_array(PackedVector3Array([normal, normal, normal, normal]))
	colors.append_array(PackedColorArray([ca, cb, cc, cd]))
	if (b - a).cross(c - a).dot(normal) > 0.0:
		indices.append_array(PackedInt32Array([base, base + 2, base + 1,
				base, base + 3, base + 2]))
	else:
		indices.append_array(PackedInt32Array([base, base + 1, base + 2,
				base, base + 2, base + 3]))


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
	var basis := basis_from_forward_up(forward, up)
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
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays())
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)


## Everything collected, laid out for [method ArrayMesh.add_surface_from_arrays].
## A blend shape takes positions and normals only.
func arrays(blend_shape := false) -> Array:
	var result := []
	result.resize(Mesh.ARRAY_MAX)
	result[Mesh.ARRAY_VERTEX] = vertices
	result[Mesh.ARRAY_NORMAL] = normals
	if not blend_shape:
		result[Mesh.ARRAY_COLOR] = colors
		result[Mesh.ARRAY_INDEX] = indices
	return result


## [param color] darkened by [param amount], alpha left opaque.
static func shade(color: Color, amount: float) -> Color:
	return Color(color.r * amount, color.g * amount, color.b * amount)


## Orthonormal basis whose -Z looks along [param forward] (Godot's convention for
## which way a node faces) and whose +Y is as close to [param up] as the forward
## direction allows.
## Lives here rather than on [Rail] (which forwards to it) so that [MeshSurface],
## which [Ground] uses, names no class that leads back to [Ground].
static func basis_from_forward_up(forward: Vector3, up: Vector3) -> Basis:
	var back := -forward.normalized()
	var right := up.cross(back)
	if right.length_squared() < 1e-9:
		# Looking straight along `up`; any perpendicular axis will do.
		right = Vector3.RIGHT.cross(back)
	if right.length_squared() < 1e-9:
		right = Vector3.FORWARD.cross(back)
	right = right.normalized()
	return Basis(right, back.cross(right), back)
