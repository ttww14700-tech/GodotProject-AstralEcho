extends Node

const HUB_SCENE := preload("res://scenes/Hub.tscn")
const RUN_WORLD_SCENE := preload("res://scenes/RunWorld.tscn")
const RESULT_SCENE := preload("res://scenes/Result.tscn")

var current_scene: Node


func _ready() -> void:
	show_hub()


func show_hub() -> void:
	_switch_to(HUB_SCENE.instantiate())
	current_scene.start_run.connect(_on_start_run)


func show_run_world() -> void:
	_switch_to(RUN_WORLD_SCENE.instantiate())
	current_scene.run_finished.connect(_on_run_finished)


func show_result() -> void:
	_switch_to(RESULT_SCENE.instantiate())
	current_scene.back_to_hub.connect(_on_result_back_to_hub)
	current_scene.continue_run.connect(_on_continue_run)


func _on_start_run() -> void:
	show_run_world()


func _on_run_finished(result: Dictionary) -> void:
	var is_retreat: bool = result.get("reason", "") == "提前撤退"
	GameState.set_last_result(result, not is_retreat)
	GameState.update_blue_concentration_from_result(result)
	if not is_retreat:
		GameState.apply_run_result(result)
	show_result()


func _on_result_back_to_hub() -> void:
	GameState.settle_last_result()
	show_hub()


func _on_continue_run() -> void:
	GameState.prepare_resume_from_last_result()
	show_run_world()


func _switch_to(scene: Node) -> void:
	if current_scene:
		current_scene.queue_free()
	current_scene = scene
	add_child(current_scene)
