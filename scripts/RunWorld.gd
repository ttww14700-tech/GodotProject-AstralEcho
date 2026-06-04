extends Node3D

signal run_finished(result: Dictionary)

const RUN_EVENT_PREVIEW_LAYER_SCRIPT := preload("res://scripts/RunEventPreviewLayer.gd")
const RUN_EVENT_PREVIEW_LAYER_SCENE := preload("res://scenes/ui/RunEventPreviewLayer.tscn")
const RUN_DURATION := 600.0
const WORLD_RADIUS := 8.0
const EVENT_TRIGGER_ANGLE := 0.08
const EVENT_EXPIRE_ANGLE := 0.75
const LANE_STEP := 4.4
const PLAYER_MOVE_LIMIT := 5.2
const LATERAL_SPEED := 3.2
const MOUSE_DEADZONE := 0.5
const MONSTER_CHASE_SPEED := 0.8
const GRID_RADIUS_OFFSET := 0.018
const GIANT_RESONANCE_STEP := 10.0
const GIANT_MONSTER_SCALE := 2.5
const NORMAL_MONSTER_MIN_SCALE := 1.1
const NORMAL_MONSTER_MAX_SCALE := 1.5
const EVENT_SPAWN_ANGLE := -0.9
const EVENT_GROUP_ANGLE_STEP := 0.08
const WORLD_SIZE_OPTIONS := [
	{"name": "小型球", "scale": 1.3},
	{"name": "中型球", "scale": 2.2},
	{"name": "大型球", "scale": 3.0}
]

@export var base_surface_speed := 3.64
@export var giant_monster_surface_speed := 1.04
@export var slow_down_multiplier := 0.4
@export var equipment_speed_multiplier := 1.0
@export var camera_preset := "SmallPlanetSurfaceArcView"
@export var camera_target_mode := "PlayerSurfaceAnchor"
@export var camera_distance_ratio := 2.05
@export var camera_height_ratio := 0.9
@export var camera_pitch_deg := 24.0
@export var camera_target_toward_center_ratio := 0.25
@export var planet_top_screen_y := 0.56
@export var player_screen_y := 0.62
@export var player_visual_forward_angle_max := 0.18
@export var player_visual_backward_angle_max := 0.06
@export var player_visual_forward_shift_speed := 3.33
@export var lane_dash_double_tap_window := 0.28
@export var lane_dash_distance_ratio := 0.5
@export var lane_dash_duration := 0.18
@export var lane_dash_cooldown_duration := 0.45
@export var planet_visible_height_ratio := 0.58
@export var camera_fov := 48.0
@export var event_preview_enabled := true
@export var event_preview_layer_scene: PackedScene = RUN_EVENT_PREVIEW_LAYER_SCENE
@export var event_preview_use_runworld_visual_overrides := false
@export var event_preview_lead_angle := 1.4
@export var event_preview_scale_with_world_radius := true
@export var event_preview_reference_world_scale := 1.3
@export var event_preview_far_screen_y := 0.22
@export var event_preview_near_screen_y := 0.42
@export var event_preview_center_x := 0.50
@export var event_preview_lane_screen_spacing := 0.12
@export var event_preview_marker_size := 24.0
@export var event_preview_position_lerp_speed := 3.0
@export var event_preview_hide_progress := 0.12
@export var event_preview_fade_progress := 0.08
@export var event_preview_debug_enabled := false
@export var event_preview_debug_log_interval := 0.5
@export var event_preview_use_grid_alignment := true
@export var event_preview_grid_columns := 3
@export var event_preview_grid_forward_bands := 4
@export var event_preview_grid_lateral_span_lanes := 1.0
@export var event_preview_grid_safe_screen_x_min := 0.08
@export var event_preview_grid_safe_screen_x_max := 0.92
@export var event_preview_projection_blend := 0.45
@export var event_preview_projection_compression := 0.60
@export var event_preview_min_screen_x := 0.14
@export var event_preview_max_screen_x := 0.86

var concentration := 100.0
var resonance_gained := 0.0
var restoration_gained := 0.0
var resources := 0
var mine_points := 0
var elapsed := 0.0
var entered_danger := false
var finished := false
var player_lane := 0
var lane_target := 0.0
var dodge_timer := 0.0
var dodge_cooldown := 0.0
var skill_timer := 0.0
var skill_cooldown := 0.0
var spawn_timer := 2.0
var event_serial := 0
var preview_event_serial := 0
var preview_group_serial := 0
var control_scheme := "mouse"
var current_surface_speed := 0.0
var current_world_rotation_speed := 0.0
var current_world_size_name := "小型球"
var current_world_scale := 1.0
var current_world_radius := WORLD_RADIUS
var camera_reference_radius := WORLD_RADIUS
var current_player_visual_forward_angle := 0.0
var last_left_tap_time := -999.0
var last_right_tap_time := -999.0
var lane_dash_elapsed := 0.0
var lane_dash_cooldown := 0.0
var lane_dash_start := 0.0
var lane_dash_target := 0.0
var lane_dash_distance_multiplier := 1.0
var lane_dash_duration_multiplier := 1.0
var lane_dash_cooldown_multiplier := 1.0
var next_giant_resonance_threshold := 10.0
var active_events: Array[Dictionary] = []
var preview_event_queue: Array[Dictionary] = []
var pending_resume_data := {}
var stats := {
	"resource_events": 0,
	"mine_events": 0,
	"monster_events": 0,
	"memory_events": 0,
	"skipped_events": 0,
	"skill_uses": 0
}

var world_mesh: MeshInstance3D
var player_mesh: MeshInstance3D
var run_camera: Camera3D
var event_preview_layer
var camera_debug_timer := 0.0
var event_preview_debug_timer := 0.0
var hud_label: Label
var log_label: Label
var danger_overlay: ColorRect


func _ready() -> void:
	randomize()
	concentration = clampf(GameState.blue_concentration, 0.0, 100.0)
	pending_resume_data = GameState.consume_resume_run_data()
	_select_world_size()
	_update_world_rotation_speed()
	_build_world()
	_build_hud()
	_restore_resume_state()
	_update_world_rotation_speed()
	_update_hud()
	if elapsed > 0.0:
		_log("繼續探索：已恢復撤退當下的紀錄。球體 %s x%.1f。" % [current_world_size_name, current_world_scale])
	else:
		_log("進入藍色寶石世界。球體 %s x%.1f，觀察球體自動轉動與濃度消耗。" % [current_world_size_name, current_world_scale])


func _process(delta: float) -> void:
	if finished:
		return

	_handle_input(delta)
	_update_player_visual_forward(delta)
	_update_timers(delta)
	_update_run(delta)
	_update_events(delta)
	_update_visuals(delta)
	_update_hud()


func _select_world_size() -> void:
	if not pending_resume_data.is_empty():
		current_world_size_name = pending_resume_data.get("world_size_name", current_world_size_name)
		current_world_scale = float(pending_resume_data.get("world_scale", current_world_scale))
		current_world_radius = float(pending_resume_data.get("world_radius", WORLD_RADIUS * current_world_scale))
		camera_reference_radius = WORLD_RADIUS
		return

	var selected: Dictionary = WORLD_SIZE_OPTIONS.pick_random()
	current_world_size_name = selected["name"]
	current_world_scale = float(selected["scale"])
	current_world_radius = WORLD_RADIUS * current_world_scale
	camera_reference_radius = WORLD_RADIUS


func _lane_step() -> float:
	return LANE_STEP * current_world_scale


func _player_move_limit() -> float:
	return PLAYER_MOVE_LIMIT * current_world_scale


func _event_preview_reference_radius() -> float:
	return maxf(WORLD_RADIUS * event_preview_reference_world_scale, 0.001)


func _resolved_event_preview_lead_angle() -> float:
	var lead_angle := maxf(event_preview_lead_angle, 0.001)
	if not event_preview_scale_with_world_radius:
		return lead_angle
	return lead_angle * _event_preview_reference_radius() / maxf(current_world_radius, 0.001)


func _event_preview_arc_length(angle: float) -> float:
	return maxf(angle, 0.0) * current_world_radius


func _event_preview_grid_column_from_lane(lane: int) -> int:
	var columns := maxi(event_preview_grid_columns, 1)
	if columns <= 1:
		return 0
	var span_lanes := maxf(event_preview_grid_lateral_span_lanes, 0.001)
	var normalized := (clampf(float(lane), -span_lanes, span_lanes) + span_lanes) / (span_lanes * 2.0)
	return clampi(roundi(normalized * float(columns - 1)), 0, columns - 1)


func _event_preview_grid_x_from_column(column: int) -> float:
	var columns := maxi(event_preview_grid_columns, 1)
	if columns <= 1:
		return 0.0
	var safe_column := clampi(column, 0, columns - 1)
	var span_lanes := maxf(event_preview_grid_lateral_span_lanes, 0.001)
	var t := float(safe_column) / float(columns - 1)
	return lerpf(-span_lanes * _lane_step(), span_lanes * _lane_step(), t)


func _create_event_preview_grid_cell(lane: int, spawn_angle: float) -> Dictionary:
	var column := _event_preview_grid_column_from_lane(lane)
	var grid_x := _event_preview_grid_x_from_column(column)
	return {
		"column": column,
		"columns": maxi(event_preview_grid_columns, 1),
		"lane": lane,
		"x": grid_x,
		"spawn_angle": spawn_angle,
		"spawn_forward_band": 0
	}


func _event_preview_grid_cell_label(grid_cell: Dictionary) -> String:
	if grid_cell.is_empty():
		return "{}"
	return "col=%s/%s lane=%s x=%.3f spawn_angle=%.3f band=%s" % [
		str(grid_cell.get("column", "?")),
		str(grid_cell.get("columns", "?")),
		str(grid_cell.get("lane", "?")),
		float(grid_cell.get("x", 0.0)),
		float(grid_cell.get("spawn_angle", 0.0)),
		str(grid_cell.get("spawn_forward_band", "?"))
	]


func _event_preview_grid_world_position(grid_x: float, angle: float) -> Vector3:
	var local_radius := sqrt(maxf(current_world_radius * current_world_radius - grid_x * grid_x, 0.0))
	return Vector3(grid_x, cos(angle) * local_radius + 0.18, sin(angle) * local_radius)


func _event_preview_forward_band(raw_progress: float) -> int:
	var bands := maxi(event_preview_grid_forward_bands, 1)
	return clampi(floori((1.0 - clampf(raw_progress, 0.0, 1.0)) * float(bands)), 0, bands - 1)


func _build_world() -> void:
	world_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = current_world_radius
	sphere.height = current_world_radius * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	world_mesh.mesh = sphere
	world_mesh.material_override = _material(Color(0.36, 0.38, 0.4))
	add_child(world_mesh)
	_add_surface_grid()

	player_mesh = MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.28
	capsule.height = 0.95
	player_mesh.mesh = capsule
	player_mesh.material_override = _material(Color(0.15, 0.45, 0.95))
	add_child(player_mesh)

	run_camera = Camera3D.new()
	add_child(run_camera)
	_apply_camera_settings(run_camera)
	_build_event_preview_layer()

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 20, 0)
	add_child(light)


func _build_event_preview_layer() -> void:
	if event_preview_layer_scene:
		event_preview_layer = event_preview_layer_scene.instantiate()
	else:
		event_preview_layer = RUN_EVENT_PREVIEW_LAYER_SCRIPT.new()
	event_preview_layer.name = "RunEventPreviewLayer"
	_apply_event_preview_layer_settings()
	add_child(event_preview_layer)


func _add_surface_grid() -> void:
	var grid := MeshInstance3D.new()
	grid.name = "SurfaceGrid"
	grid.mesh = _create_surface_grid_mesh()
	grid.material_override = _grid_material()
	world_mesh.add_child(grid)


func _create_surface_grid_mesh() -> Mesh:
	var mesh := ImmediateMesh.new()
	var radius := current_world_radius + GRID_RADIUS_OFFSET
	var latitude_steps := 8
	var longitude_steps := 24
	var segment_steps := 96

	mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	for lat_index in range(1, latitude_steps):
		var theta := -PI * 0.5 + PI * float(lat_index) / float(latitude_steps)
		var y := sin(theta) * radius
		var ring_radius := cos(theta) * radius
		for step in range(segment_steps):
			var a := TAU * float(step) / float(segment_steps)
			var b := TAU * float(step + 1) / float(segment_steps)
			mesh.surface_add_vertex(Vector3(cos(a) * ring_radius, y, sin(a) * ring_radius))
			mesh.surface_add_vertex(Vector3(cos(b) * ring_radius, y, sin(b) * ring_radius))

	for lon_index in range(longitude_steps):
		var phi := TAU * float(lon_index) / float(longitude_steps)
		for step in range(segment_steps):
			var theta_a := -PI * 0.5 + PI * float(step) / float(segment_steps)
			var theta_b := -PI * 0.5 + PI * float(step + 1) / float(segment_steps)
			mesh.surface_add_vertex(Vector3(cos(theta_a) * cos(phi) * radius, sin(theta_a) * radius, cos(theta_a) * sin(phi) * radius))
			mesh.surface_add_vertex(Vector3(cos(theta_b) * cos(phi) * radius, sin(theta_b) * radius, cos(theta_b) * sin(phi) * radius))

	mesh.surface_end()
	return mesh


func _grid_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.78, 0.82, 0.84, 0.144)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = false
	return material


func _apply_camera_settings(camera: Camera3D) -> void:
	var distance := camera_reference_radius * camera_distance_ratio
	camera.fov = camera_fov
	var target := _get_camera_surface_anchor()
	camera.position = Vector3(0, target.y + _camera_height_for_distance(distance), target.z + distance)
	camera.look_at(target, Vector3.UP)


func _get_camera_surface_anchor() -> Vector3:
	var planet_center := Vector3.ZERO
	var player_position := _get_gameplay_player_position()
	if player_position.distance_squared_to(planet_center) < 0.001:
		player_position = Vector3(0, current_world_radius + 0.55, 0)

	var player_surface_normal := (player_position - planet_center).normalized()
	var toward_center := -player_surface_normal
	return player_position + toward_center * current_world_radius * camera_target_toward_center_ratio


func _get_gameplay_player_position() -> Vector3:
	var local_radius := sqrt(maxf(current_world_radius * current_world_radius - lane_target * lane_target, 0.0))
	return Vector3(lane_target, local_radius + 0.55, 0.0)


func _get_visual_player_position() -> Vector3:
	var local_radius := sqrt(maxf(current_world_radius * current_world_radius - lane_target * lane_target, 0.0))
	var angle := -current_player_visual_forward_angle
	return Vector3(lane_target, cos(angle) * local_radius + 0.55, sin(angle) * local_radius)


func _camera_height_for_distance(distance: float) -> float:
	var pitch_height := tan(deg_to_rad(camera_pitch_deg)) * distance
	var min_height := camera_reference_radius * camera_height_ratio
	return maxf(pitch_height, min_height)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	danger_overlay = ColorRect.new()
	danger_overlay.color = Color(0.6, 0.05, 0.1, 0.0)
	danger_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	danger_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(danger_overlay)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 18
	root.offset_top = 16
	root.offset_right = -18
	root.offset_bottom = -16
	root.add_theme_constant_override("separation", 8)
	layer.add_child(root)

	hud_label = Label.new()
	hud_label.add_theme_font_size_override("font_size", 25)
	root.add_child(hud_label)

	log_label = Label.new()
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.custom_minimum_size = Vector2(0, 58)
	root.add_child(log_label)

	var retreat_button := Button.new()
	retreat_button.text = "提前撤退 (B)"
	retreat_button.anchor_left = 1.0
	retreat_button.anchor_top = 0.0
	retreat_button.anchor_right = 1.0
	retreat_button.anchor_bottom = 0.0
	retreat_button.offset_left = -220
	retreat_button.offset_top = 18
	retreat_button.offset_right = -18
	retreat_button.offset_bottom = 62
	retreat_button.pressed.connect(_finish_run.bind("提前撤退"))
	layer.add_child(retreat_button)

	var controls_panel := PanelContainer.new()
	controls_panel.anchor_left = 1.0
	controls_panel.anchor_top = 1.0
	controls_panel.anchor_right = 1.0
	controls_panel.anchor_bottom = 1.0
	controls_panel.offset_left = -360
	controls_panel.offset_top = -150
	controls_panel.offset_right = -18
	controls_panel.offset_bottom = -18
	layer.add_child(controls_panel)

	var controls := Label.new()
	controls.text = "基礎操作\nA/D 或 ←/→：左右移動，雙擊 A/D 可短距離閃避\n移動滑鼠：滑鼠接管左右方向\nW：長按前移角色視覺\nS：長按減速並後退角色視覺\nSpace：迴避閃過事件\nF：使用技能\nB：提前撤退"
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls_panel.add_child(controls)

	_apply_font_size(layer)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.relative.length() > MOUSE_DEADZONE:
		control_scheme = "mouse"


func _handle_input(delta: float) -> void:
	_handle_lane_dash_taps()
	if lane_dash_elapsed > 0.0:
		_update_lane_dash(delta)
		return

	var lateral_axis := Input.get_axis("move_left", "move_right")
	if not is_zero_approx(lateral_axis):
		control_scheme = "keyboard"
		var move_limit := _player_move_limit()
		lane_target = clampf(lane_target + lateral_axis * LATERAL_SPEED * current_world_scale * delta, -move_limit, move_limit)
	elif control_scheme == "mouse":
		var viewport_width := float(get_viewport().get_visible_rect().size.x)
		if viewport_width > 0.0:
			var mouse_x := get_viewport().get_mouse_position().x
			var mouse_ratio := clampf(mouse_x / viewport_width, 0.0, 1.0)
			var move_limit := _player_move_limit()
			var mouse_target := lerpf(-move_limit, move_limit, mouse_ratio)
			lane_target = move_toward(lane_target, mouse_target, LATERAL_SPEED * current_world_scale * delta)
	player_lane = clampi(roundi(lane_target / _lane_step()), -1, 1)
	if Input.is_action_just_pressed("dodge") and dodge_cooldown <= 0.0:
		dodge_timer = 0.55
		dodge_cooldown = 1.1
		_log("迴避姿態：下一個接觸事件會被閃過。")
	if Input.is_action_just_pressed("skill") and skill_cooldown <= 0.0:
		skill_timer = 1.2
		skill_cooldown = 7.0
		stats["skill_uses"] += 1
		_log("使用技能：短時間降低怪物成本並提高收益。")
	if Input.is_action_just_pressed("retreat"):
		_finish_run("提前撤退")


func _handle_lane_dash_taps() -> void:
	if Input.is_action_just_pressed("move_left"):
		control_scheme = "keyboard"
		var previous_tap := last_left_tap_time
		last_left_tap_time = elapsed
		if elapsed - previous_tap <= lane_dash_double_tap_window:
			_try_start_lane_dash(-1)
	if Input.is_action_just_pressed("move_right"):
		control_scheme = "keyboard"
		var previous_tap := last_right_tap_time
		last_right_tap_time = elapsed
		if elapsed - previous_tap <= lane_dash_double_tap_window:
			_try_start_lane_dash(1)


func _try_start_lane_dash(direction: int) -> void:
	if lane_dash_cooldown > 0.0:
		return
	var move_limit := _player_move_limit()
	var dash_distance := _get_lane_dash_distance()
	var target := clampf(lane_target + float(direction) * dash_distance, -move_limit, move_limit)
	if is_equal_approx(target, lane_target):
		return

	lane_dash_elapsed = _get_lane_dash_duration()
	lane_dash_cooldown = _get_lane_dash_cooldown_duration()
	lane_dash_start = lane_target
	lane_dash_target = target
	player_lane = clampi(roundi(lane_dash_target / _lane_step()), -1, 1)
	_log("短距離閃避：方向 %d，距離 %.0f%% lane。" % [direction, lane_dash_distance_ratio * lane_dash_distance_multiplier * 100.0])


func _update_lane_dash(delta: float) -> void:
	var duration := maxf(_get_lane_dash_duration(), 0.001)
	lane_dash_elapsed = maxf(lane_dash_elapsed - delta, 0.0)
	var progress := 1.0 - lane_dash_elapsed / duration
	lane_target = lerpf(lane_dash_start, lane_dash_target, progress)
	if lane_dash_elapsed <= 0.0:
		lane_target = lane_dash_target
	player_lane = clampi(roundi(lane_target / _lane_step()), -1, 1)


func _get_lane_dash_distance() -> float:
	return _lane_step() * lane_dash_distance_ratio * lane_dash_distance_multiplier


func _get_lane_dash_duration() -> float:
	return lane_dash_duration * lane_dash_duration_multiplier


func _get_lane_dash_cooldown_duration() -> float:
	return lane_dash_cooldown_duration * lane_dash_cooldown_multiplier


func set_lane_dash_modifiers(distance_multiplier := 1.0, duration_multiplier := 1.0, cooldown_multiplier := 1.0) -> void:
	lane_dash_distance_multiplier = maxf(distance_multiplier, 0.0)
	lane_dash_duration_multiplier = maxf(duration_multiplier, 0.01)
	lane_dash_cooldown_multiplier = maxf(cooldown_multiplier, 0.0)


func _update_timers(delta: float) -> void:
	dodge_timer = maxf(dodge_timer - delta, 0.0)
	dodge_cooldown = maxf(dodge_cooldown - delta, 0.0)
	skill_timer = maxf(skill_timer - delta, 0.0)
	skill_cooldown = maxf(skill_cooldown - delta, 0.0)
	lane_dash_cooldown = maxf(lane_dash_cooldown - delta, 0.0)


func _update_player_visual_forward(delta: float) -> void:
	var target := 0.0
	if Input.is_action_pressed("slow_down"):
		target = -player_visual_backward_angle_max
	elif Input.is_action_pressed("camera_push_forward"):
		target = player_visual_forward_angle_max
	current_player_visual_forward_angle = move_toward(current_player_visual_forward_angle, target, player_visual_forward_shift_speed * delta)


func _update_run(delta: float) -> void:
	elapsed += delta
	var drain := 0.3 if entered_danger else 0.1
	concentration = maxf(concentration - drain * delta, 0.0)

	if concentration <= 10.0 and not entered_danger:
		entered_danger = true
		_log("危險期開始：素材降低，怪物與高價值事件提高。")

	if concentration <= 0.0:
		_finish_run("濃度歸零")


func _update_events(delta: float) -> void:
	_update_world_rotation_speed()
	_update_preview_event_queue(delta)
	spawn_timer -= delta
	var spawn_interval := 6.5
	if entered_danger:
		spawn_interval = 4.2
	if spawn_timer <= 0.0:
		_spawn_event()
		spawn_timer = spawn_interval

	for event in active_events.duplicate():
		event["angle"] += delta * current_world_rotation_speed
		_update_monster_chase(event, delta)
		_position_event(event)

		if absf(event["angle"]) <= EVENT_TRIGGER_ANGLE and event["lane"] == player_lane:
			_resolve_event(event)
			_remove_event(event)
		elif event["angle"] >= EVENT_EXPIRE_ANGLE:
			_remove_event(event)
	_print_event_preview_debug(delta)


func _update_visuals(delta: float) -> void:
	world_mesh.rotate_x(delta * current_world_rotation_speed)
	player_mesh.position = _get_visual_player_position()
	player_mesh.rotation_degrees.z = -lane_target * 4.0
	if run_camera:
		_solve_camera_composition(run_camera)
		_sync_event_preview_layer(delta)

	var danger_alpha := 0.13 if entered_danger else 0.0
	danger_overlay.color = Color(0.6, 0.05, 0.1, danger_alpha)


func _sync_event_preview_layer(delta: float) -> void:
	if not event_preview_layer:
		return
	_apply_event_preview_layer_settings()
	_update_preview_event_grid_projections()
	event_preview_layer.sync_preview_events(preview_event_queue, delta)


func _update_preview_event_grid_projections() -> void:
	if preview_event_queue.is_empty():
		return
	var safe_min := minf(event_preview_grid_safe_screen_x_min, event_preview_grid_safe_screen_x_max)
	var safe_max := maxf(event_preview_grid_safe_screen_x_min, event_preview_grid_safe_screen_x_max)
	for preview_event in preview_event_queue:
		var lane := int(preview_event.get("lane", 0))
		var spawn_angle := float(preview_event.get("spawn_angle", EVENT_SPAWN_ANGLE))
		var grid_cell: Dictionary = preview_event.get("grid_cell", {})
		if grid_cell.is_empty():
			grid_cell = _create_event_preview_grid_cell(lane, spawn_angle)
			preview_event["grid_cell"] = grid_cell

		var max_preview_angle := maxf(float(preview_event.get("max_preview_angle", 0.001)), 0.001)
		var preview_angle_remaining := clampf(float(preview_event.get("preview_angle_remaining", 0.0)), 0.0, max_preview_angle)
		var raw_progress := clampf(preview_angle_remaining / max_preview_angle, 0.0, 1.0)
		var preview_angle := float(grid_cell.get("spawn_angle", spawn_angle)) - preview_angle_remaining
		var grid_x := float(grid_cell.get("x", float(lane) * _lane_step()))
		var grid_world_position := _event_preview_grid_world_position(grid_x, preview_angle)
		var projected_screen_x := _projected_screen_x(grid_world_position)
		var projected_valid := event_preview_use_grid_alignment and run_camera != null and projected_screen_x > -10.0 and projected_screen_x < 10.0
		var fallback_reason := ""
		if not event_preview_use_grid_alignment:
			fallback_reason = "grid_disabled"
		elif not projected_valid:
			fallback_reason = "projection_invalid"

		preview_event["grid_world_position"] = grid_world_position
		preview_event["grid_preview_angle"] = preview_angle
		preview_event["grid_projected_screen_x"] = projected_screen_x
		preview_event["grid_projected_valid"] = projected_valid
		preview_event["grid_screen_x"] = projected_screen_x
		preview_event["grid_safe_screen_x"] = clampf(projected_screen_x, safe_min, safe_max)
		preview_event["grid_projection_fallback_reason"] = fallback_reason
		preview_event["grid_forward_band"] = _event_preview_forward_band(raw_progress)


func _event_preview_lane_screen_x(lane: int) -> float:
	var resolved_center_x := event_preview_center_x
	var resolved_lane_spacing := event_preview_lane_screen_spacing
	if event_preview_layer:
		resolved_center_x = float(event_preview_layer.get("center_x"))
		resolved_lane_spacing = float(event_preview_layer.get("lane_screen_spacing"))
	return clampf(resolved_center_x + float(lane) * resolved_lane_spacing, 0.0, 1.0)


func _projected_screen_x(world_position: Vector3) -> float:
	if not run_camera:
		return -1.0
	var viewport_width := maxf(float(get_viewport().get_visible_rect().size.x), 1.0)
	return run_camera.unproject_position(world_position).x / viewport_width


func _apply_event_preview_layer_settings() -> void:
	if not event_preview_layer:
		return
	event_preview_layer.enabled = event_preview_enabled
	event_preview_layer.use_grid_alignment = event_preview_use_grid_alignment
	event_preview_layer.projection_blend = event_preview_projection_blend
	event_preview_layer.projection_compression = event_preview_projection_compression
	event_preview_layer.min_screen_x = event_preview_min_screen_x
	event_preview_layer.max_screen_x = event_preview_max_screen_x
	if not event_preview_use_runworld_visual_overrides:
		return
	event_preview_layer.far_screen_y = event_preview_far_screen_y
	event_preview_layer.near_screen_y = event_preview_near_screen_y
	event_preview_layer.center_x = event_preview_center_x
	event_preview_layer.lane_screen_spacing = event_preview_lane_screen_spacing
	event_preview_layer.marker_size = event_preview_marker_size
	event_preview_layer.position_lerp_speed = event_preview_position_lerp_speed
	event_preview_layer.hide_progress = event_preview_hide_progress
	event_preview_layer.fade_progress = event_preview_fade_progress


func _print_event_preview_debug(delta: float) -> void:
	if not event_preview_debug_enabled:
		return
	event_preview_debug_timer -= delta
	if event_preview_debug_timer > 0.0:
		return
	event_preview_debug_timer = maxf(event_preview_debug_log_interval, 0.05)

	var resolved_lead_angle := _resolved_event_preview_lead_angle()
	var lead_arc_length := _event_preview_arc_length(resolved_lead_angle)
	var hide_arc_length := _event_preview_arc_length(resolved_lead_angle * event_preview_hide_progress)
	var fade_arc_length := _event_preview_arc_length(resolved_lead_angle * event_preview_fade_progress)
	var fade_start_arc_length := _event_preview_arc_length(resolved_lead_angle * (event_preview_hide_progress + event_preview_fade_progress))
	var lane_anchor_rows := []
	for lane in [-1, 0, 1]:
		lane_anchor_rows.append("lane=%d screen_x=%.3f" % [
			lane,
			_event_preview_lane_screen_x(lane)
		])

	var preview_rows := []
	for preview_event in preview_event_queue:
		var max_preview_angle := maxf(float(preview_event.get("max_preview_angle", 0.001)), 0.001)
		var preview_angle_remaining := float(preview_event.get("preview_angle_remaining", 0.0))
		var raw_progress := clampf(preview_angle_remaining / max_preview_angle, 0.0, 1.0)
		var grid_cell: Dictionary = preview_event.get("grid_cell", {})
		var grid_projected_screen_x := float(preview_event.get("grid_projected_screen_x", -1.0))
		var grid_safe_screen_x := float(preview_event.get("grid_safe_screen_x", -1.0))
		var grid_projected_valid := bool(preview_event.get("grid_projected_valid", false))
		var ui_marker_screen_x := float(preview_event.get("ui_marker_screen_x", _event_preview_lane_screen_x(int(preview_event.get("lane", 0)))))
		var fixed_x := float(preview_event.get("ui_marker_fixed_x", _event_preview_lane_screen_x(int(preview_event.get("lane", 0)))))
		var projected_x := float(preview_event.get("ui_marker_projected_x", grid_projected_screen_x))
		var compressed_projected_x := float(preview_event.get("ui_marker_compressed_projected_x", projected_x))
		var unclamped_screen_x := float(preview_event.get("ui_marker_unclamped_screen_x", ui_marker_screen_x))
		var clamp_delta := float(preview_event.get("ui_marker_clamp_delta", 0.0))
		var projection_blend := float(preview_event.get("ui_marker_projection_blend", event_preview_projection_blend))
		var projection_compression := float(preview_event.get("ui_marker_projection_compression", event_preview_projection_compression))
		var ui_marker_source := String(preview_event.get("ui_marker_screen_x_source", "pending"))
		var fallback_reason := String(preview_event.get("grid_projection_fallback_reason", ""))
		preview_rows.append("%s lane=%s grid={%s} band=%s remaining=%.3f raw=%.3f arc=%.3f fixed_x=%.3f projected_x=%.3f compressed_x=%.3f unclamped_x=%.3f final_x=%.3f clamp_delta=%.3f blend=%.2f compression=%.2f grid_safe_x=%.3f grid_valid=%s ui_source=%s fallback=%s visible=%s" % [
			String(preview_event.get("type", "?")),
			str(preview_event.get("lane", "?")),
			_event_preview_grid_cell_label(grid_cell),
			str(preview_event.get("grid_forward_band", "?")),
			preview_angle_remaining,
			raw_progress,
			_event_preview_arc_length(preview_angle_remaining),
			fixed_x,
			projected_x,
			compressed_projected_x,
			unclamped_screen_x,
			ui_marker_screen_x,
			clamp_delta,
			projection_blend,
			projection_compression,
			grid_safe_screen_x,
			"YES" if grid_projected_valid else "NO",
			ui_marker_source,
			fallback_reason,
			"YES" if event_preview_enabled else "NO"
		])

	var active_rows := []
	for event in active_events:
		var grid_cell: Dictionary = event.get("grid_cell", {})
		active_rows.append("%s lane=%s grid={%s} x=%.3f angle=%.3f" % [
			String(event.get("type", "?")),
			str(event.get("lane", "?")),
			_event_preview_grid_cell_label(grid_cell),
			float(event.get("x", 0.0)),
			float(event.get("angle", 0.0))
		])

	print("EventPreviewDebug world=%s scale=%.2f radius=%.3f reference_radius=%.3f resolved_lead_angle=%.3f lead_arc=%.3f hide_arc=%.3f fade_arc=%.3f fade_start_arc=%.3f lane_anchors=[%s] active_events=%d preview_candidates=%d queue=[%s] active=[%s]" % [
		current_world_size_name,
		current_world_scale,
		current_world_radius,
		_event_preview_reference_radius(),
		resolved_lead_angle,
		lead_arc_length,
		hide_arc_length,
		fade_arc_length,
		fade_start_arc_length,
		"; ".join(lane_anchor_rows),
		active_events.size(),
		preview_event_queue.size(),
		"; ".join(preview_rows),
		"; ".join(active_rows)
	])


func _update_world_rotation_speed() -> void:
	var surface_speed := base_surface_speed
	for event in active_events:
		if event["type"] != "monster" or not event.get("is_giant", false):
			continue
		surface_speed = giant_monster_surface_speed
		break
	current_surface_speed = surface_speed * _get_surface_speed_multiplier()
	current_world_rotation_speed = current_surface_speed / maxf(current_world_radius, 0.001)


func _get_surface_speed_multiplier() -> float:
	var multiplier := equipment_speed_multiplier
	if Input.is_action_pressed("slow_down"):
		multiplier *= slow_down_multiplier
	return multiplier


func _solve_camera_composition(camera: Camera3D) -> void:
	camera.fov = camera_fov
	camera.v_offset = 0.0
	var distance := camera_reference_radius * camera_distance_ratio
	var target := _get_camera_surface_anchor()

	_apply_camera_transform(camera, target, distance)
	_solve_player_screen_y_offset(camera)
	_print_camera_debug(camera)


func _apply_camera_transform(camera: Camera3D, target: Vector3, distance: float) -> void:
	camera.position = Vector3(0, target.y + _camera_height_for_distance(distance), target.z + distance)
	camera.look_at(target, Vector3.UP)


func _solve_player_screen_y_offset(camera: Camera3D) -> void:
	var step := maxf(camera_reference_radius * 0.02, 0.1)
	var max_correction := camera_reference_radius * 1.5
	var camera_up := camera.global_transform.basis.y.normalized()
	for iteration in 8:
		var current_y := _normalized_screen_y(camera, _get_gameplay_player_position())
		var error := player_screen_y - current_y
		if absf(error) < 0.005:
			return

		var base_position := camera.global_position
		camera.global_position = base_position + camera_up * step
		var stepped_y := _normalized_screen_y(camera, _get_gameplay_player_position())
		var derivative := (stepped_y - current_y) / step
		camera.global_position = base_position

		if absf(derivative) < 0.0001:
			camera.global_position = base_position + camera_up * clampf(error * current_world_radius, -max_correction, max_correction)
		else:
			camera.global_position = base_position + camera_up * clampf(error / derivative, -max_correction, max_correction)


func _normalized_screen_y(camera: Camera3D, world_position: Vector3) -> float:
	var viewport_height := maxf(float(get_viewport().get_visible_rect().size.y), 1.0)
	return camera.unproject_position(world_position).y / viewport_height


func _measure_planet_top_screen_y(camera: Camera3D) -> float:
	var top_y := INF
	for x_index in range(-4, 5):
		for z_index in range(-4, 5):
			var x := float(x_index) / 4.0 * current_world_radius
			var z := float(z_index) / 4.0 * current_world_radius
			var remaining := current_world_radius * current_world_radius - x * x - z * z
			if remaining < 0.0:
				continue
			var point := Vector3(x, sqrt(remaining), z)
			top_y = minf(top_y, _normalized_screen_y(camera, point))
	if top_y == INF:
		return 0.5
	return top_y


func _print_camera_debug(camera: Camera3D) -> void:
	camera_debug_timer -= get_process_delta_time()
	if camera_debug_timer > 0.0:
		return
	camera_debug_timer = 0.5
	print("CameraSolver targetPlayerScreenY=%.3f actualPlayerScreenY=%.3f targetPlanetTopScreenY=%.3f actualPlanetTopScreenY=%.3f" % [
		player_screen_y,
		_normalized_screen_y(camera, _get_gameplay_player_position()),
		planet_top_screen_y,
		_measure_planet_top_screen_y(camera)
	])


func _update_hud() -> void:
	var module_name: String = GameState.get_selected_module_data()["name"]
	var control_text := "鍵盤" if control_scheme == "keyboard" else "滑鼠"
	var slow_text := "慢速中" if Input.is_action_pressed("slow_down") else "一般"
	var surface_speed_multiplier := _get_surface_speed_multiplier()
	hud_label.text = "時間 %s / 濃度 %.1f%% / 本輪共鳴 +%.1f%% / 資源 %d / 礦點 %d / 模組 %s\n球體 %s x%.1f / 半徑 %.2f / surface倍率 %.0f%% / surface %.2f / angular %.4f\n方向 %d / 控制 %s / 速度 %s / 迴避 %.1fs / 技能 %.1fs / 狀態 %s" % [
		_format_time(elapsed),
		concentration,
		resonance_gained,
		resources,
		mine_points,
		module_name,
		current_world_size_name,
		current_world_scale,
		current_world_radius,
		surface_speed_multiplier * 100.0,
		current_surface_speed,
		current_world_rotation_speed,
		player_lane,
		control_text,
		slow_text,
		dodge_cooldown,
		skill_cooldown,
		"危險期" if entered_danger else "穩定期"
	]


func _spawn_event() -> void:
	var event_type := _pick_event_type()
	if event_type == "monster":
		var group_count := randi_range(1, 3)
		var group_id := _next_preview_group_id()
		for index in group_count:
			var lane := randi_range(-1, 1)
			var angle_offset := -float(index) * EVENT_GROUP_ANGLE_STEP
			_queue_preview_event(event_type, lane, false, group_id, index, angle_offset)
		return

	_queue_preview_event(event_type, randi_range(-1, 1))


func _next_preview_group_id() -> int:
	preview_group_serial += 1
	return preview_group_serial


func _queue_preview_event(event_type: String, lane: int, is_giant := false, group_id := 0, group_member_index := 0, angle_offset := 0.0) -> void:
	preview_event_serial += 1
	var size_multiplier := 1.0
	if event_type == "monster":
		size_multiplier = GIANT_MONSTER_SCALE if is_giant else randf_range(NORMAL_MONSTER_MIN_SCALE, NORMAL_MONSTER_MAX_SCALE)
	var max_preview_angle := _resolved_event_preview_lead_angle()
	var spawn_angle := EVENT_SPAWN_ANGLE + angle_offset
	var grid_cell := _create_event_preview_grid_cell(lane, spawn_angle)
	var preview_event := {
		"id": preview_event_serial,
		"type": event_type,
		"lane": lane,
		"preview_angle_remaining": max_preview_angle,
		"max_preview_angle": max_preview_angle,
		"preview_reference_radius": _event_preview_reference_radius(),
		"preview_world_radius": current_world_radius,
		"preview_lead_arc_length": _event_preview_arc_length(max_preview_angle),
		"spawn_angle": spawn_angle,
		"grid_cell": grid_cell,
		"is_giant": is_giant,
		"group_id": group_id,
		"group_member_index": group_member_index,
		"angle_offset": angle_offset,
		"handoff_state": "queued",
		"handoff_alpha": 1.0,
		"size_multiplier": size_multiplier,
		"color": _event_color(event_type)
	}
	preview_event_queue.append(preview_event)


func _update_preview_event_queue(delta: float) -> void:
	if preview_event_queue.is_empty():
		return
	for preview_event in preview_event_queue.duplicate():
		var remaining := float(preview_event.get("preview_angle_remaining", 0.0))
		remaining = maxf(remaining - current_world_rotation_speed * delta, 0.0)
		preview_event["preview_angle_remaining"] = remaining
		if remaining <= 0.0:
			_flush_preview_event_to_active(preview_event)


func _flush_preview_event_to_active(preview_event: Dictionary) -> void:
	if not preview_event_queue.has(preview_event):
		return
	preview_event["handoff_state"] = "active"
	var grid_cell: Dictionary = preview_event.get("grid_cell", {})
	_create_event(
		String(preview_event.get("type", "resource")),
		int(preview_event.get("lane", 0)),
		float(preview_event.get("spawn_angle", EVENT_SPAWN_ANGLE)),
		bool(preview_event.get("is_giant", false)),
		float(preview_event.get("size_multiplier", 1.0)),
		grid_cell
	)
	preview_event_queue.erase(preview_event)


func _create_event(event_type: String, lane: int, angle: float, is_giant := false, size_multiplier := 0.0, grid_cell: Dictionary = {}) -> void:
	event_serial += 1
	var marker := MeshInstance3D.new()
	marker.name = "Event_%s_%d" % [event_type, event_serial]
	marker.mesh = _event_mesh(event_type)
	marker.material_override = _material(_event_color(event_type))
	if event_type == "monster":
		var monster_size := size_multiplier
		if monster_size <= 0.0:
			monster_size = GIANT_MONSTER_SCALE if is_giant else randf_range(NORMAL_MONSTER_MIN_SCALE, NORMAL_MONSTER_MAX_SCALE)
		marker.scale = Vector3.ONE * monster_size
	add_child(marker)

	var resolved_grid_cell := grid_cell.duplicate(true)
	if resolved_grid_cell.is_empty():
		resolved_grid_cell = _create_event_preview_grid_cell(lane, angle)
	var start_x := float(resolved_grid_cell.get("x", float(lane) * _lane_step()))
	var start_angle := float(resolved_grid_cell.get("spawn_angle", angle))
	var event := {
		"type": event_type,
		"lane": lane,
		"x": start_x,
		"angle": start_angle,
		"node": marker,
		"is_giant": is_giant,
		"grid_cell": resolved_grid_cell
	}
	active_events.append(event)
	_position_event(event)
	_print_event_preview_active_spawn_debug(event)


func _position_event(event: Dictionary) -> void:
	var x: float = event.get("x", float(event["lane"]) * _lane_step())
	var local_radius := sqrt(maxf(current_world_radius * current_world_radius - x * x, 0.0))
	var angle: float = event["angle"]
	var marker: MeshInstance3D = event["node"]
	marker.position = Vector3(x, cos(angle) * local_radius + 0.18, sin(angle) * local_radius)
	marker.look_at(Vector3(x, 0, 0), Vector3.UP)


func _print_event_preview_active_spawn_debug(event: Dictionary) -> void:
	if not event_preview_debug_enabled:
		return
	var marker: MeshInstance3D = event["node"]
	var lane := int(event.get("lane", 0))
	var start_x := float(event.get("x", float(lane) * _lane_step()))
	var projected_screen_x := _projected_screen_x(marker.global_position)
	var ui_marker_screen_x := _event_preview_lane_screen_x(lane)
	var grid_cell: Dictionary = event.get("grid_cell", {})
	print("EventPreviewActiveSpawn type=%s lane=%d grid={%s} start_x=%.3f projected_screen_x=%.3f ui_marker_screen_x=%.3f diff=%.3f" % [
		String(event.get("type", "?")),
		lane,
		_event_preview_grid_cell_label(grid_cell),
		start_x,
		projected_screen_x,
		ui_marker_screen_x,
		projected_screen_x - ui_marker_screen_x
	])


func _update_monster_chase(event: Dictionary, delta: float) -> void:
	if event["type"] != "monster":
		return
	var monster_x: float = event.get("x", float(event["lane"]) * _lane_step())
	monster_x = move_toward(monster_x, lane_target, MONSTER_CHASE_SPEED * delta)
	event["x"] = monster_x
	event["lane"] = clampi(roundi(monster_x / _lane_step()), -1, 1)


func _resolve_event(event: Dictionary) -> void:
	var event_type: String = event["type"]
	if dodge_timer > 0.0:
		stats["skipped_events"] += 1
		_log("閃過 %s：沒有接觸事件，因此不取得收益。" % _event_name(event_type, event.get("is_giant", false)))
		return

	var cost := _event_cost(event_type)
	var resonance := _event_resonance(event_type)
	var resource_gain := _event_resources(event_type)
	var mine_gain := _event_mine_points(event_type)
	if entered_danger:
		resonance *= 1.45
		resource_gain = int(round(resource_gain * 1.35))
		mine_gain = int(round(mine_gain * 1.35))
	if event_type == "monster" and skill_timer > 0.0:
		cost *= 0.45
		resonance += 0.8
		resource_gain += 1

	concentration = maxf(concentration - cost, 0.0)
	resonance_gained += resonance
	restoration_gained += resonance * 0.35
	resources += resource_gain
	mine_points += mine_gain
	stats["%s_events" % event_type] += 1
	var giant_count := _spawn_giant_monsters_for_resonance()
	var message := "%s 觸發：濃度 -%.1f，共鳴 +%.1f，資源 +%d，礦點 +%d。" % [_event_name(event_type, event.get("is_giant", false)), cost, resonance, resource_gain, mine_gain]
	if giant_count > 0:
		message += " 共鳴門檻觸發：大型怪物 x%d。" % giant_count
	_log(message)


func _spawn_giant_monsters_for_resonance() -> int:
	var spawned := 0
	var group_id := _next_preview_group_id()
	while resonance_gained >= next_giant_resonance_threshold:
		var angle_offset := -float(spawned) * EVENT_GROUP_ANGLE_STEP
		_queue_preview_event("monster", randi_range(-1, 1), true, group_id, spawned, angle_offset)
		next_giant_resonance_threshold += GIANT_RESONANCE_STEP
		spawned += 1
	return spawned


func _pick_event_type() -> String:
	var weights: Dictionary = GameState.get_selected_module_data()["weights"].duplicate(true)
	var minute := elapsed / 60.0
	if minute < 1.0:
		weights = {"resource": 1.6, "mine": 0.7, "monster": 0.45, "memory": 0.45}
	elif minute >= 4.0 and minute < 6.0:
		weights["mine"] *= 1.45
		weights["monster"] *= 1.25
	elif minute >= 6.0 and minute < 8.0:
		weights["memory"] *= 1.85
	elif minute >= 8.0:
		weights["monster"] *= 1.35
		weights["memory"] *= 1.25
	if entered_danger:
		weights["resource"] *= 0.55
		weights["monster"] *= 1.8
		weights["memory"] *= 1.35
		weights["mine"] *= 1.25

	var total := 0.0
	for value in weights.values():
		total += float(value)
	var roll := randf() * total
	for key in weights.keys():
		roll -= float(weights[key])
		if roll <= 0.0:
			return key
	return "resource"


func _remove_event(event: Dictionary) -> void:
	active_events.erase(event)
	var marker: Node = event["node"]
	if is_instance_valid(marker):
		marker.queue_free()


func _finish_run(reason: String) -> void:
	if finished:
		return
	finished = true
	var result := {
		"reason": reason,
		"elapsed": elapsed,
		"concentration": concentration,
		"entered_danger": entered_danger,
		"resources": resources,
		"mine_points": mine_points,
		"resonance_gained": resonance_gained,
		"restoration_gained": restoration_gained,
		"player_lane": player_lane,
		"lane_target": lane_target,
		"world_size_name": current_world_size_name,
		"world_scale": current_world_scale,
		"world_radius": current_world_radius,
		"spawn_timer": spawn_timer,
		"next_giant_resonance_threshold": next_giant_resonance_threshold
	}
	for key in stats.keys():
		result[key] = stats[key]
	run_finished.emit(result)


func _event_cost(event_type: String) -> float:
	match event_type:
		"resource":
			return 0.5
		"mine":
			return 0.5
		"monster":
			return 1.0
		"memory":
			return 0.5
	return 1.0


func _event_resonance(event_type: String) -> float:
	match event_type:
		"resource":
			return 0.15
		"mine":
			return 0.35
		"monster":
			return 0.55
		"memory":
			return 1.4
	return 0.0


func _event_resources(event_type: String) -> int:
	match event_type:
		"resource":
			return 2
		"mine":
			return 0
		"monster":
			return 1
		"memory":
			return 0
	return 0


func _event_mine_points(event_type: String) -> int:
	if event_type == "mine":
		return 5
	return 0


func _event_name(event_type: String, is_giant := false) -> String:
	match event_type:
		"resource":
			return "資源點"
		"mine":
			return "礦點"
		"monster":
			if is_giant:
				return "大型怪物"
			return "怪物"
		"memory":
			return "記憶碎片"
	return event_type


func _event_color(event_type: String) -> Color:
	match event_type:
		"resource":
			return Color(0.15, 0.75, 0.35)
		"mine":
			return Color(0.85, 0.72, 0.2)
		"monster":
			return Color(0.85, 0.15, 0.15)
		"memory":
			return Color(0.35, 0.65, 1.0)
	return Color.WHITE


func _event_mesh(event_type: String) -> Mesh:
	if event_type == "monster":
		var box := BoxMesh.new()
		box.size = Vector3(0.55, 0.55, 0.55)
		return box
	var sphere := SphereMesh.new()
	sphere.radius = 0.32
	sphere.height = 0.64
	return sphere


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	return material


func _restore_resume_state() -> void:
	var data := pending_resume_data
	pending_resume_data = {}
	if data.is_empty():
		return

	concentration = data.get("concentration", concentration)
	resonance_gained = data.get("resonance_gained", resonance_gained)
	restoration_gained = data.get("restoration_gained", restoration_gained)
	resources = data.get("resources", resources)
	mine_points = data.get("mine_points", mine_points)
	elapsed = data.get("elapsed", elapsed)
	entered_danger = data.get("entered_danger", entered_danger)
	player_lane = data.get("player_lane", player_lane)
	lane_target = data.get("lane_target", player_lane * _lane_step())
	current_world_size_name = data.get("world_size_name", current_world_size_name)
	current_world_scale = float(data.get("world_scale", current_world_scale))
	current_world_radius = float(data.get("world_radius", current_world_radius))
	spawn_timer = data.get("spawn_timer", spawn_timer)
	next_giant_resonance_threshold = data.get("next_giant_resonance_threshold", _next_giant_threshold_after(resonance_gained))
	for key in stats.keys():
		stats[key] = data.get(key, stats[key])
	_update_visuals(0.0)
	_update_hud()


func _next_giant_threshold_after(value: float) -> float:
	return floorf(value / GIANT_RESONANCE_STEP) * GIANT_RESONANCE_STEP + GIANT_RESONANCE_STEP


func _format_time(value: float) -> String:
	var total := int(value)
	return "%02d:%02d" % [total / 60, total % 60]


func _log(message: String) -> void:
	log_label.text = message


func _apply_font_size(node: Node) -> void:
	if node is Control:
		node.add_theme_font_size_override("font_size", 25)
	for child in node.get_children():
		_apply_font_size(child)
