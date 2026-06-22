class_name GeodesicSphere
extends RefCounted

var vertices: PackedVector3Array = PackedVector3Array()
var triangles: Array = []   # Array of [a:int, b:int, c:int]
var tiles: Array = []       # Array of PlanetTile


func generate(subdivision_depth: int = 3) -> void:
	_init_icosahedron()
	for _i in range(subdivision_depth):
		_subdivide()
	_build_tiles()


func _init_icosahedron() -> void:
	var t: float = (1.0 + sqrt(5.0)) / 2.0

	# 12 vertices of a regular icosahedron, normalized to unit sphere
	vertices = PackedVector3Array([
		Vector3(-1.0,  t,  0.0).normalized(),  # 0
		Vector3( 1.0,  t,  0.0).normalized(),  # 1
		Vector3(-1.0, -t,  0.0).normalized(),  # 2
		Vector3( 1.0, -t,  0.0).normalized(),  # 3
		Vector3( 0.0, -1.0,  t).normalized(),  # 4
		Vector3( 0.0,  1.0,  t).normalized(),  # 5
		Vector3( 0.0, -1.0, -t).normalized(),  # 6
		Vector3( 0.0,  1.0, -t).normalized(),  # 7
		Vector3( t,  0.0, -1.0).normalized(),  # 8
		Vector3( t,  0.0,  1.0).normalized(),  # 9
		Vector3(-t,  0.0, -1.0).normalized(),  # 10
		Vector3(-t,  0.0,  1.0).normalized(),  # 11
	])

	# 20 triangular faces, CCW winding from outside
	triangles = [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9],  [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4],  [3, 4, 2],  [3, 2, 6],   [3, 6, 8],  [3, 8, 9],
		[4, 9, 5],  [2, 4, 11], [6, 2, 10],  [8, 6, 7],  [9, 8, 1],
	]


func _subdivide() -> void:
	# Split every triangle into 4 by inserting edge midpoints.
	# Edge midpoints are shared between adjacent triangles via the cache.
	var edge_cache: Dictionary = {}
	var new_tris: Array = []

	for tri in triangles:
		var a: int = tri[0]
		var b: int = tri[1]
		var c: int = tri[2]

		var ab: int = _get_midpoint(a, b, edge_cache)
		var bc: int = _get_midpoint(b, c, edge_cache)
		var ca: int = _get_midpoint(c, a, edge_cache)

		new_tris.append([a,  ab, ca])
		new_tris.append([b,  bc, ab])
		new_tris.append([c,  ca, bc])
		new_tris.append([ab, bc, ca])

	triangles = new_tris


func _get_midpoint(v1: int, v2: int, cache: Dictionary) -> int:
	# Canonical key is order-independent so both (a,b) and (b,a) hit the same slot.
	var key: int = min(v1, v2) * 1000000 + max(v1, v2)
	if cache.has(key):
		return cache[key]
	var mid: Vector3 = (vertices[v1] + vertices[v2]).normalized()
	var idx: int = vertices.size()
	vertices.append(mid)
	cache[key] = idx
	return idx


func _build_tiles() -> void:
	# Build: for each icosphere vertex, which triangles contain it?
	var vertex_to_tris: Array = []
	vertex_to_tris.resize(vertices.size())
	for i in range(vertices.size()):
		vertex_to_tris[i] = []

	for fi in range(triangles.size()):
		var tri = triangles[fi]
		vertex_to_tris[tri[0]].append(fi)
		vertex_to_tris[tri[1]].append(fi)
		vertex_to_tris[tri[2]].append(fi)

	# Each triangle's centroid (projected to sphere) becomes a polygon corner in the dual.
	var tri_centers: PackedVector3Array = PackedVector3Array()
	for tri in triangles:
		var c: Vector3 = (vertices[tri[0]] + vertices[tri[1]] + vertices[tri[2]]).normalized()
		tri_centers.append(c)

	# One tile per icosphere vertex — its polygon is the ring of tri_centers around it.
	tiles = []
	for vi in range(vertices.size()):
		var face_list: Array = vertex_to_tris[vi]
		var sorted_faces: Array = _sort_faces_around_vertex(face_list, tri_centers, vertices[vi])

		var polygon: PackedVector3Array = PackedVector3Array()
		for fi in sorted_faces:
			polygon.append(tri_centers[fi])

		var tile: PlanetTile = PlanetTile.new()
		tile.tile_id = vi
		tile.center_position = vertices[vi]
		tile.normal = vertices[vi]
		tile.polygon = polygon
		tile.is_pentagon = (face_list.size() == 5)
		tiles.append(tile)

	_build_neighbours(vertex_to_tris)


func _sort_faces_around_vertex(
		face_indices: Array,
		face_centers: PackedVector3Array,
		normal: Vector3) -> Array:
	if face_indices.size() <= 2:
		return face_indices

	# Build a tangent frame on the plane perpendicular to normal.
	var ref: Vector3 = Vector3.UP if abs(normal.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var tangent_x: Vector3 = normal.cross(ref).normalized()
	var tangent_y: Vector3 = normal.cross(tangent_x).normalized()

	var face_angles: Array = []
	for fi in face_indices:
		var fc: Vector3 = face_centers[fi]
		# Project the face center onto the tangent plane at this vertex.
		var projected: Vector3 = fc - normal * normal.dot(fc)
		var angle: float = atan2(projected.dot(tangent_y), projected.dot(tangent_x))
		face_angles.append({"fi": fi, "angle": angle})

	face_angles.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return a.angle < b.angle
	)

	var result: Array = []
	for item in face_angles:
		result.append(item.fi)
	return result


func _build_neighbours(vertex_to_tris: Array) -> void:
	# Two tiles are neighbours when they share a triangle edge,
	# i.e. both their icosphere vertices appear in the same triangle.
	var sets: Array = []
	for _i in range(tiles.size()):
		sets.append({})

	for tri in triangles:
		var a: int = tri[0]
		var b: int = tri[1]
		var c: int = tri[2]
		sets[a][b] = true;  sets[a][c] = true
		sets[b][a] = true;  sets[b][c] = true
		sets[c][a] = true;  sets[c][b] = true

	for vi in range(tiles.size()):
		tiles[vi].neighbours = sets[vi].keys()
