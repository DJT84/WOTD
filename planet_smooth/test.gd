extends Node3D

# GL Compatibility render test for EarthSphere inside the game project.
func _ready() -> void:
	for f in range(8):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://planet_smooth/test.png")
	get_tree().quit()
