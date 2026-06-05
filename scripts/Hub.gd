extends Control

signal start_run

const HUB_SPHERE_CONTROLLER := preload("res://scripts/HubSphereController.gd")

@export var hub_player_move_speed := 2.0
@export var hub_walk_radius := 6.0
@export var hub_sphere_radius := 10.0
@export var hub_camera_reference_radius := 10.0
@export var hub_camera_pitch_deg := 32.0
@export var hub_camera_yaw_offset_deg := 30.0
@export var hub_camera_distance := 21.0
@export var hub_camera_height := 15.0
@export var hub_camera_look_at_height := 1.4
@export var hub_camera_follow_lerp_speed := 7.0
@export_range(0.0, 0.2, 0.01) var hub_camera_screen_offset_y := 0.12
@export_range(30.0, 75.0, 1.0) var hub_camera_fov := 52.0
@export var project_scene_primitives_to_sphere := true
@export var hub_placement_plane_size := 12.0
@export var show_hub_placement_plane_debug := true
@export var show_hub_grid_alignment_debug := false

var module_buttons := {}
var expectation_label: Label
var save_label: Label
var doctor_restore_button: Button
var hub_sphere_controller: HubSphereController
var hub_interaction_ui: Control
var is_central_tower_interaction_active := false


func _enter_tree() -> void:
	_find_existing_hub_sphere()
	if hub_sphere_controller:
		_apply_hub_sphere_settings()


func _ready() -> void:
	_build_hub_sphere()
	_build_ui()
	_refresh_ui()


func _build_hub_sphere() -> void:
	if not hub_sphere_controller:
		hub_sphere_controller = HUB_SPHERE_CONTROLLER.new()
		hub_sphere_controller.name = "HubSphereController"
		add_child(hub_sphere_controller)
	_apply_hub_sphere_settings()
	if not hub_sphere_controller.central_tower_interaction_changed.is_connected(_set_central_tower_interaction_active):
		hub_sphere_controller.central_tower_interaction_changed.connect(_set_central_tower_interaction_active)


func _find_existing_hub_sphere() -> void:
	hub_sphere_controller = get_node_or_null("HubSphereController") as HubSphereController


func _apply_hub_sphere_settings() -> void:
	hub_sphere_controller.player_move_speed = hub_player_move_speed
	hub_sphere_controller.hub_walk_radius = hub_walk_radius
	hub_sphere_controller.hub_sphere_radius = hub_sphere_radius
	hub_sphere_controller.hub_camera_reference_radius = hub_camera_reference_radius
	hub_sphere_controller.hub_camera_pitch_deg = hub_camera_pitch_deg
	hub_sphere_controller.hub_camera_yaw_offset_deg = hub_camera_yaw_offset_deg
	hub_sphere_controller.hub_camera_distance = hub_camera_distance
	hub_sphere_controller.hub_camera_height = hub_camera_height
	hub_sphere_controller.hub_camera_look_at_height = hub_camera_look_at_height
	hub_sphere_controller.hub_camera_follow_lerp_speed = hub_camera_follow_lerp_speed
	hub_sphere_controller.hub_camera_screen_offset_y = hub_camera_screen_offset_y
	hub_sphere_controller.hub_camera_fov = hub_camera_fov
	hub_sphere_controller.project_scene_primitives_to_sphere = project_scene_primitives_to_sphere
	hub_sphere_controller.hub_placement_plane_size = hub_placement_plane_size
	hub_sphere_controller.show_hub_placement_plane_debug = show_hub_placement_plane_debug
	hub_sphere_controller.show_hub_grid_alignment_debug = show_hub_grid_alignment_debug


func _build_ui() -> void:
	var root := VBoxContainer.new()
	hub_interaction_ui = root
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 32
	root.offset_top = 28
	root.offset_right = -32
	root.offset_bottom = -28
	root.add_theme_constant_override("separation", 14)
	add_child(root)

	var title := Label.new()
	title.text = "Astral Echo 灰模據點"
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "藍色寶石世界 / 修正器孔位 1 / 無美術玩法測試"
	root.add_child(subtitle)

	save_label = Label.new()
	root.add_child(save_label)

	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 8)
	root.add_child(save_row)

	var clear_button := Button.new()
	clear_button.text = "清除寶石資料"
	clear_button.pressed.connect(_clear_progress)
	save_row.add_child(clear_button)

	var doctor_row := HBoxContainer.new()
	doctor_row.add_theme_constant_override("separation", 8)
	root.add_child(doctor_row)

	var doctor_name := Label.new()
	doctor_name.text = "璃博士"
	doctor_row.add_child(doctor_name)

	doctor_restore_button = Button.new()
	doctor_restore_button.text = "復原寶石"
	doctor_restore_button.pressed.connect(_restore_blue_gem)
	doctor_row.add_child(doctor_restore_button)

	var gem_module_separator := HSeparator.new()
	root.add_child(gem_module_separator)

	var module_title := Label.new()
	module_title.text = "探索模組"
	root.add_child(module_title)

	var module_row := HBoxContainer.new()
	module_row.add_theme_constant_override("separation", 8)
	root.add_child(module_row)

	for key in GameState.MODULES.keys():
		var button := Button.new()
		button.text = GameState.MODULES[key]["name"]
		button.toggle_mode = true
		button.pressed.connect(_select_module.bind(key))
		module_row.add_child(button)
		module_buttons[key] = button

	expectation_label = Label.new()
	expectation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(expectation_label)

	var start_button := Button.new()
	start_button.text = "進入藍色寶石世界"
	start_button.custom_minimum_size = Vector2(0, 48)
	start_button.pressed.connect(func(): start_run.emit())
	root.add_child(start_button)

	var controls := Label.new()
	controls.text = "局內操作：A/D、←/→ 或滑鼠控制左右方向，雙擊 A/D 可短距離閃避，W 長按前移角色視覺，S 長按減速並後退角色視覺，Space 迴避閃過事件，F 使用技能，B 提前撤退。"
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(controls)
	_apply_font_size(root)
	_set_central_tower_interaction_active(false)


func _select_module(module_key: String) -> void:
	GameState.selected_module = module_key
	GameState.save_game()
	_refresh_ui()


func _clear_progress() -> void:
	GameState.reset_progress()
	_refresh_ui()


func _restore_blue_gem() -> void:
	GameState.restore_blue_gem()
	_refresh_ui()


func _refresh_ui() -> void:
	for key in module_buttons.keys():
		module_buttons[key].button_pressed = key == GameState.selected_module

	doctor_restore_button.visible = GameState.blue_concentration < 80.0
	doctor_restore_button.disabled = not GameState.can_restore_blue_gem()

	var module_data := GameState.get_selected_module_data()
	var expectation := GameState.get_generation_expectation()
	expectation_label.text = "%s：%s\n生成預期：資源 %s / 礦點 %s / 怪物 %s / 記憶 %s / 危險 %s" % [
		module_data["name"],
		module_data["description"],
		expectation["資源"],
		expectation["礦點"],
		expectation["怪物"],
		expectation["記憶"],
		expectation["危險"]
	]
	save_label.text = "寶石濃度 %.1f%% / 資源 %d / 礦點 %d / 永久共鳴 %.1f%% / 世界復原 %.1f%% / 已探索 %d 次" % [
		GameState.blue_concentration,
		GameState.blue_resources,
		GameState.blue_mine_points,
		GameState.blue_resonance,
		GameState.blue_restoration,
		GameState.total_runs
	]


func _set_central_tower_interaction_active(active: bool) -> void:
	is_central_tower_interaction_active = active
	if hub_interaction_ui:
		hub_interaction_ui.visible = is_central_tower_interaction_active


func _apply_font_size(node: Node) -> void:
	if node is Control:
		node.add_theme_font_size_override("font_size", 25)
	for child in node.get_children():
		_apply_font_size(child)
