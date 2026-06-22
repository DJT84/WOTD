class_name PlanetTile
extends RefCounted

var tile_id: int = 0
var center_position: Vector3 = Vector3.ZERO
var normal: Vector3 = Vector3.UP
var neighbours: Array = []
var polygon: PackedVector3Array = PackedVector3Array()
var is_pentagon: bool = false
var terrain_type: String = "any"
var is_land: bool = false
var landmark_type: String = ""
var is_volcano: bool = false
var feature: String = ""
var damage_state: int = 0
var life_count: float = 1.0
var life_suppressed: bool = false
var suppression_timer: float = 0.0
var mesh_instance: MeshInstance3D = null
var material: ShaderMaterial = null
