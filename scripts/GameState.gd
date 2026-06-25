extends Node

signal dust_changed(current: float, alltime: float)

var current_dust: float = 0.0
var alltime_dust: float = 0.0


func add_dust(amount: float) -> void:
	current_dust += amount
	alltime_dust += amount
	dust_changed.emit(current_dust, alltime_dust)


func spend_dust(amount: float) -> bool:
	if current_dust < amount:
		return false
	current_dust -= amount
	dust_changed.emit(current_dust, alltime_dust)
	return true
