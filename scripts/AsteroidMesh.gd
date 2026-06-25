class_name AsteroidMesh
extends RefCounted

# Generates a flat-shaded low-poly asteroid MeshInstance3D that matches
# the planet's putty/clay visual style. Uses a displaced icosahedron so
# each asteroid reads as a chunky rock rather than a smooth sphere.

static func create(radius: float = 0.55, seed_val: int = 0) -> MeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	# Icosahedron base vertices (12 points on unit sphere)
	var phi := (1.0 + sqrt(5.0)) / 2.0
	var raw: Array[Vector3] = [
		Vector3(-1,  phi,  0), Vector3( 1,  phi,  0),
		Vector3(-1, -phi,  0), Vector3( 1, -phi,  0),
		Vector3( 0, -1,  phi), Vector3( 0,  1,  phi),
		Vector3( 0, -1, -phi), Vector3( 0,  1, -phi),
		Vector3( phi,  0, -1), Vector3( phi,  0,  1),
		Vector3(-phi,  0, -1), Vector3(-phi,  0,  1),
	]

	# Normalize to sphere, then apply per-vertex random displacement
	var displaced: Array[Vector3] = []
	displaced.resize(raw.size())
	for i in range(raw.size()):
		var n := raw[i].normalized()
		var jitter := 1.0 + rng.randf_range(-0.20, 0.20)
		displaced[i] = n * radius * jitter

	# Icosahedron face index table (20 triangles, winding consistent)
	var faces: Array = [
		[0,11,5], [0,5,1], [0,1,7], [0,7,10], [0,10,11],
		[1,5,9],  [5,11,4],[11,10,2],[10,7,6],[7,1,8],
		[3,9,4],  [3,4,2], [3,2,6], [3,6,8], [3,8,9],
		[4,9,5],  [2,4,11],[6,2,10],[8,6,7], [9,8,1],
	]

	# Build flat-shaded mesh: each triangle gets its own 3 vertices sharing
	# the face normal, so hard edges appear between faces (putty look).
	var verts   := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var idx     := 0

	for face in faces:
		var a: Vector3 = displaced[face[0]]
		var b: Vector3 = displaced[face[1]]
		var c: Vector3 = displaced[face[2]]
		var fn: Vector3 = (b - a).cross(c - a).normalized()
		verts.append_array([a, b, c])
		normals.append_array([fn, fn, fn])
		indices.append_array([idx, idx + 1, idx + 2])
		idx += 3

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX]  = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/pixel_rock.gdshader") as Shader
	# Vary pixel grid slightly per slot so each rock has its own texture pattern
	mat.set_shader_parameter("pixel_size", 0.06 + seed_val * 0.003)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.set_surface_override_material(0, mat)
	return mi
