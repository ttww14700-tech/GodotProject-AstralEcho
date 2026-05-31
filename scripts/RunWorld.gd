extends Node3D

signal run_finished(result: Dictionary)

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

@export var world_rotation_speed := 0.5
@export var giant_monster_world_rotation_speed := 0.1
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
@export var player_visual_forward_shift_speed := 3.33
@export var planet_visible_height_ratio := 0.58
@export var camera_fov := 48.0

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
var control_scheme := "mouse"
var current_world_rotation_speed := 0.5
var current_player_visual_forward_angle := 0.0
var next_giant_resonance_threshold := 10.0
var active_events: Array[Dictionary] = []
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
var camera_debug_timer := 0.0
var hud_label: Label
var log_label: Label
var danger_overlay: ColorRect


func _ready() -> void:
	concentration = clampf(GameState.blue_concentration, 0.0, 100.0)
	_build_world()
	_build_hud()
	_restore_resume_state()
	if elapsed > 0.0:
		_log("繼續探索：已恢復撤退當下的紀錄。")
	else:
		_log("進入藍色寶石世界。觀察球體自動轉動與濃度消耗。")


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


func _build_world() -> void:
	world_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = WORLD_RADIUS
	sphere.height = WORLD_RADIUS * 2.0
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

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 20, 0)
	add_child(light)


func _add_surface_grid() -> void:
	var grid := MeshInstance3D.new()
	grid.name = "SurfaceGrid"
	grid.mesh = _create_surface_grid_mesh()
	grid.material_override = _grid_material()
	world_mesh.add_child(grid)


func _create_surface_grid_mesh() -> Mesh:
	var mesh := ImmediateMesh.new()
	var radius := WORLD_RADIUS + GRID_RADIUS_OFFSET
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
	var distance := WORLD_RADIUS * camera_distance_ratio
	camera.fov = camera_fov
	var target := _get_camera_surface_anchor()
	camera.position = Vector3(0, target.y + _camera_height_for_distance(distance), target.z + distance)
	camera.look_at(target, Vector3.UP)


func _get_camera_surface_anchor() -> Vector3:
	var planet_center := Vector3.ZERO
	var player_position := _get_gameplay_player_position()
	if player_position.distance_squared_to(planet_center) < 0.001:
		player_position = Vector3(0, WORLD_RADIUS + 0.55, 0)

	var player_surface_normal := (player_position - planet_center).normalized()
	var toward_center := -player_surface_normal
	return player_position + toward_center * WORLD_RADIUS * camera_target_toward_center_ratio


func _get_gameplay_player_position() -> Vector3:
	var local_radius := sqrt(maxf(WORLD_RADIUS * WORLD_RADIUS - lane_target * lane_target, 0.0))
	return Vector3(lane_target, local_radius + 0.55, 0.0)


func _get_visual_player_position() -> Vector3:
	var local_radius := sqrt(maxf(WORLD_RADIUS * WORLD_RADIUS - lane_target * lane_target, 0.0))
	var angle := -current_player_visual_forward_angle
	return Vector3(lane_target, cos(angle) * local_radius + 0.55, sin(angle) * local_radius)


func _camera_height_for_distance(distance: float) -> float:
	var pitch_height := tan(deg_to_rad(camera_pitch_deg)) * distance
	var min_height := WORLD_RADIUS * camera_height_ratio
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
	controls.text = "基礎操作\nA/D 或 ←/→：鍵盤接管左右移動\n移動滑鼠：滑鼠接管左右方向\nW：長按前移角色視覺\nS：長按減速\nSpace：迴避閃過事件\nF：使用技能\nB：提前撤退"
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls_panel.add_child(controls)

	_apply_font_size(layer)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.relative.length() > MOUSE_DEADZONE:
		control_scheme = "mouse"


func _handle_input(delta: float) -> void:
	var lateral_axis := Input.get_axis("move_left", "move_right")
	if not is_zero_approx(lateral_axis):
		control_scheme = "keyboard"
		lane_target = clampf(lane_target + lateral_axis * LATERAL_SPEED * delta, -PLAYER_MOVE_LIMIT, PLAYER_MOVE_LIMIT)
	elif control_scheme == "mouse":
		var viewport_width := float(get_viewport().get_visible_rect().size.x)
		if viewport_width > 0.0:
			var mouse_x := get_viewport().get_mouse_position().x
			var mouse_ratio := clampf(mouse_x / viewport_width, 0.0, 1.0)
			var mouse_target := lerpf(-PLAYER_MOVE_LIMIT, PLAYER_MOVE_LIMIT, mouse_ratio)
			lane_target = move_toward(lane_target, mouse_target, LATERAL_SPEED * delta)
	player_lane = clampi(roundi(lane_target / LANE_STEP), -1, 1)
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


func _update_timers(delta: float) -> void:
	dodge_timer = maxf(dodge_timer - delta, 0.0)
	dodge_cooldown = maxf(dodge_cooldown - delta, 0.0)
	skill_timer = maxf(skill_timer - delta, 0.0)
	skill_cooldown = maxf(skill_cooldown - delta, 0.0)


func _update_player_visual_forward(delta: float) -> void:
	var target := player_visual_forward_angle_max if Input.is_action_pressed("camera_push_forward") else 0.0
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


func _update_visuals(delta: float) -> void:
	world_mesh.rotate_x(delta * current_world_rotation_speed)
	player_mesh.position = _get_visual_player_position()
	player_mesh.rotation_degrees.z = -lane_target * 4.0
	if run_camera:
		_solve_camera_composition(run_camera)

	var danger_alpha := 0.13 if entered_danger else 0.0
	danger_overlay.color = Color(0.6, 0.05, 0.1, danger_alpha)


func _update_world_rotation_speed() -> void:
	var environment_speed := world_rotation_speed
	for event in active_events:
		if event["type"] != "monster" or not event.get("is_giant", false):
			continue
		environment_speed = giant_monster_world_rotation_speed
		break
	current_world_rotation_speed = environment_speed * _get_player_speed_multiplier()


func _get_player_speed_multiplier() -> float:
	var multiplier := equipment_speed_multiplier
	if Input.is_action_pressed("slow_down"):
		multiplier *= slow_down_multiplier
	return multiplier


func _solve_camera_composition(camera: Camera3D) -> void:
	camera.fov = camera_fov
	camera.v_offset = 0.0
	var distance := WORLD_RADIUS * camera_distance_ratio
	var target := _get_camera_surface_anchor()

	for iteration in 6:
		_apply_camera_transform(camera, target, distance)
		_solve_player_screen_y_offset(camera)
		var planet_top_y := _measure_planet_top_screen_y(camera)
		var visible_height := 1.0 - planet_top_y
		var top_error := planet_top_screen_y - planet_top_y
		var visible_error := planet_visible_height_ratio - visible_height
		distance = clampf(distance + top_error * WORLD_RADIUS * 1.8 - visible_error * WORLD_RADIUS * 1.2, WORLD_RADIUS * 0.75, WORLD_RADIUS * 3.0)

	camera.v_offset = 0.0
	_apply_camera_transform(camera, target, distance)
	_solve_player_screen_y_offset(camera)
	_print_camera_debug(camera)


func _apply_camera_transform(camera: Camera3D, target: Vector3, distance: float) -> void:
	camera.position = Vector3(0, target.y + _camera_height_for_distance(distance), target.z + distance)
	camera.look_at(target, Vector3.UP)


func _solve_player_screen_y_offset(camera: Camera3D) -> void:
	var step := 0.1
	for iteration in 5:
		var current_y := _normalized_screen_y(camera, _get_gameplay_player_position())
		var error := player_screen_y - current_y
		if absf(error) < 0.005:
			return

		var base_offset := camera.v_offset
		camera.v_offset = base_offset + step
		var stepped_y := _normalized_screen_y(camera, _get_gameplay_player_position())
		var derivative := (stepped_y - current_y) / step
		camera.v_offset = base_offset

		if absf(derivative) < 0.0001:
			camera.v_offset = clampf(base_offset + error * 4.0, -10.0, 10.0)
		else:
			camera.v_offset = clampf(base_offset + error / derivative, -10.0, 10.0)


func _normalized_screen_y(camera: Camera3D, world_position: Vector3) -> float:
	var viewport_height := maxf(float(get_viewport().get_visible_rect().size.y), 1.0)
	return camera.unproject_position(world_position).y / viewport_height


func _measure_planet_top_screen_y(camera: Camera3D) -> float:
	var top_y := INF
	for x_index in range(-4, 5):
		for z_index in range(-4, 5):
			var x := float(x_index) / 4.0 * WORLD_RADIUS
			var z := float(z_index) / 4.0 * WORLD_RADIUS
			var remaining := WORLD_RADIUS * WORLD_RADIUS - x * x - z * z
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
	hud_label.text = "時間 %s / 濃度 %.1f%% / 本輪共鳴 +%.1f%% / 資源 %d / 礦點 %d / 模組 %s\n方向 %d / 控制 %s / 速度 %.0f%% %s / 迴避 %.1fs / 技能 %.1fs / 狀態 %s" % [
		_format_time(elapsed),
		concentration,
		resonance_gained,
		resources,
		mine_points,
		module_name,
		player_lane,
		control_text,
		_get_player_speed_multiplier() * 100.0,
		slow_text,
		dodge_cooldown,
		skill_cooldown,
		"危險期" if entered_danger else "穩定期"
	]


func _spawn_event() -> void:
	var event_type := _pick_event_type()
	if event_type == "monster":
		var group_count := randi_range(1, 3)
		for index in group_count:
			var lane := randi_range(-1, 1)
			_create_event(event_type, lane, -0.9 - float(index) * 0.08)
		return

	_create_event(event_type, randi_range(-1, 1), -0.9)


func _create_event(event_type: String, lane: int, angle: float, is_giant := false) -> void:
	event_serial += 1
	var marker := MeshInstance3D.new()
	marker.name = "Event_%s_%d" % [event_type, event_serial]
	marker.mesh = _event_mesh(event_type)
	marker.material_override = _material(_event_color(event_type))
	if event_type == "monster":
		var size_multiplier := GIANT_MONSTER_SCALE if is_giant else randf_range(NORMAL_MONSTER_MIN_SCALE, NORMAL_MONSTER_MAX_SCALE)
		marker.scale = Vector3.ONE * size_multiplier
	add_child(marker)

	var start_x := float(lane) * LANE_STEP
	var event := {
		"type": event_type,
		"lane": lane,
		"x": start_x,
		"angle": angle,
		"node": marker,
		"is_giant": is_giant
	}
	active_events.append(event)
	_position_event(event)


func _position_event(event: Dictionary) -> void:
	var x: float = event.get("x", float(event["lane"]) * LANE_STEP)
	var local_radius := sqrt(maxf(WORLD_RADIUS * WORLD_RADIUS - x * x, 0.0))
	var angle: float = event["angle"]
	var marker: MeshInstance3D = event["node"]
	marker.position = Vector3(x, cos(angle) * local_radius + 0.18, sin(angle) * local_radius)
	marker.look_at(Vector3(x, 0, 0), Vector3.UP)


func _update_monster_chase(event: Dictionary, delta: float) -> void:
	if event["type"] != "monster":
		return
	var monster_x: float = event.get("x", float(event["lane"]) * LANE_STEP)
	monster_x = move_toward(monster_x, lane_target, MONSTER_CHASE_SPEED * delta)
	event["x"] = monster_x
	event["lane"] = clampi(roundi(monster_x / LANE_STEP), -1, 1)


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
	while resonance_gained >= next_giant_resonance_threshold:
		_create_event("monster", randi_range(-1, 1), -0.9 - float(spawned) * 0.08, true)
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
	var data := GameState.consume_resume_run_data()
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
	lane_target = data.get("lane_target", player_lane * LANE_STEP)
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
