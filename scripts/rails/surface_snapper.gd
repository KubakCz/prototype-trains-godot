@tool
class_name SurfaceSnapper
extends RefCounted
## Straight-down raycasts against the level's ground meshes.
##
## Rails are snapped in the editor, and the editor does not step the physics
## server, so a [PhysicsDirectSpaceState3D] raycast finds nothing there. This
## intersects the surface's mesh triangles directly instead, which behaves
## identically in the editor and at runtime.

## One surface mesh, with its triangles already baked into global space and an
## XZ bounding rect used to skip meshes the ray misses entirely.
class Surface:
	var triangles: PackedVector3Array
	var bounds: Rect2

	func _init(global_triangles: PackedVector3Array) -> void:
		triangles = global_triangles
		if triangles.is_empty():
			bounds = Rect2()
			return
		bounds = Rect2(triangles[0].x, triangles[0].z, 0.0, 0.0)
		for vertex in triangles:
			bounds = bounds.expand(Vector2(vertex.x, vertex.z))


## Bakes every [MeshInstance3D] at or below [param roots] into queryable
## surfaces. Do this once per snapping pass and reuse the result for all points -
## reading mesh faces is not cheap.
static func collect(roots: Array[Node]) -> Array[Surface]:
	var surfaces: Array[Surface] = []
	for root in roots:
		if root == null:
			continue
		for node in _mesh_instances(root):
			var mesh := node.mesh
			if mesh == null:
				continue
			var faces := mesh.get_faces()
			if faces.is_empty():
				continue
			var to_global := node.global_transform
			var global_faces := PackedVector3Array()
			global_faces.resize(faces.size())
			for i in faces.size():
				global_faces[i] = to_global * faces[i]
			surfaces.append(Surface.new(global_faces))
	return surfaces


## Highest surface height at [param x]/[param z], or [code]null[/code] when the
## column hits nothing. Returns a [Variant] so that "no surface here" stays
## distinguishable from "surface at height zero".
static func height_at(surfaces: Array[Surface], x: float, z: float) -> Variant:
	const RAY_START_HEIGHT := 10_000.0
	var from := Vector3(x, RAY_START_HEIGHT, z)
	var column := Vector2(x, z)
	var found := false
	var highest := 0.0
	for surface in surfaces:
		if not surface.bounds.has_point(column):
			continue
		var triangles := surface.triangles
		var i := 0
		while i + 2 < triangles.size():
			var hit = Geometry3D.ray_intersects_triangle(
					from, Vector3.DOWN, triangles[i], triangles[i + 1], triangles[i + 2])
			if hit != null and (not found or hit.y > highest):
				highest = hit.y
				found = true
			i += 3
	return highest if found else null


static func _mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		found.append(root)
	for child in root.get_children():
		found.append_array(_mesh_instances(child))
	return found
