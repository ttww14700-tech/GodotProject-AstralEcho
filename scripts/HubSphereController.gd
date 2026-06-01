extends Node3D
class_name HubSphereController

@export var godot_unit_meters := 1.0
@export var player_height_units := 1.7
@export var natural_step_distance := 0.65
@export var lane_width := 1.2
@export var short_dash_lane_ratio := 0.5
@export var short_dash_distance := 0.6
@export var hub_sphere_radius := 10.0
@export var hub_camera_reference_radius := 10.0
@export var visual_rotation_multiplier := 0.35
@export var player_move_speed := 2.0
@export var hub_walk_radius := 6.0
@export var player_visual_offset_max := 0.4
@export var player_visual_offset_follow_speed := 6.0

const PLAYER_RADIUS_RATIO := 0.16
const CAMERA_DISTANCE_RATIO := 2.2
const CAMERA_HEIGHT_RATIO := 1.25
const SURFACE_OFFSET := 0.02
const GRID_RADIUS_OFFSET := 0.02
const DEBUG_PANEL_WIDTH := 430.0
const DEBUG_PANEL_HEIGHT := 360.0
const RECENT_MOVE_DEBUG_HOLD_TIME := 0.5

var hub_sphere_visual: Node3D
var hub_sphere_mesh: MeshInstance3D
var player_node: Node3D
var player_mesh: MeshInstance3D
var camera_rig: Node3D
var hub_camera: Camera3D
var debug_label: Label
var logical_hub_position := Vector2.ZERO
var player_visual_offset := Vector2.ZERO
var player_surface_normal := Vector3.UP
var hub_sphere_visual_basis := Basis.IDENTITY
var last_player_move_distance := 0.0
var last_calculated_rotation_radian := 0.0
var last_is_walk_radius_limited := false
var last_counter_rotation_axis := Vector3.ZERO
var recent_move_debug_timer := 0.0
var recent_input_dir := Vector2.ZERO
var recent_move_distance := 0.0
var recent_rotation_radian := 0.0
var recent_counter_axis := Vector3.ZERO
var recent_visual_rotation := 0.0


func _ready() -> void:
	_build_hub_sphere()
	_build_player()
	_build_camera()
	_build_light()
	_build_debug_overlay()
	_update_player_visual()
	_update_debug_label()


func _process(delta: float) -> void:
	_update_recent_move_debug_timer(delta)
	_update_player_movement(delta)
	_update_player_visual()
	_update_debug_label()


func _build_hub_sphere() -> void:
	hub_sphere_visual = Node3D.new()
	hub_sphere_visual.name = "HubSphereVisual"
	add_child(hub_sphere_visual)

	hub_sphere_mesh = MeshInstance3D.new()
	hub_sphere_mesh.name = "HubSphereMesh"
	var sphere := SphereMesh.new()
	sphere.radius = hub_sphere_radius
	sphere.height = hub_sphere_radius * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	hub_sphere_mesh.mesh = sphere
	hub_sphere_mesh.material_override = _material(Color(0.24, 0.31, 0.36))
	hub_sphere_visual.add_child(hub_sphere_mesh)
	_add_surface_grid()


func _add_surface_grid() -> void:
	var grid := MeshInstance3D.new()
	grid.name = "HubSurfaceGrid"
	grid.mesh = _create_surface_grid_mesh()
	grid.material_override = _grid_material()
	hub_sphere_visual.add_child(grid)


func _create_surface_grid_mesh() -> Mesh:
	var mesh := ImmediateMesh.new()
	var radius := hub_sphere_radius + GRID_RADIUS_OFFSET
	var latitude_steps := 10
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


func _build_player() -> void:
	player_node = Node3D.new()
	player_node.name = "Player"
	add_child(player_node)

	player_mesh = MeshInstance3D.new()
	player_mesh.name = "HubPlayerMesh"
	var capsule := CapsuleMesh.new()
	capsule.radius = player_height_units * PLAYER_RADIUS_RATIO
	capsule.height = player_height_units
	player_mesh.mesh = capsule
	player_mesh.material_override = _material(Color(0.15, 0.47, 0.95))
	player_node.add_child(player_mesh)


func _build_camera() -> void:
	camera_rig = Node3D.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)

	hub_camera = Camera3D.new()
	hub_camera.name = "HubCamera"
	hub_camera.fov = 38.0
	hub_camera.current = true
	camera_rig.add_child(hub_camera)
	_update_camera_transform()


func _build_light() -> void:
	var light := DirectionalLight3D.new()
	light.name = "HubKeyLight"
	light.rotation_degrees = Vector3(-48, 24, 0)
	add_child(light)


func _update_player_movement(delta: float) -> void:
	var screen_input_vector := _get_screen_input_vector()
	if screen_input_vector.is_zero_approx():
		_clear_move_debug_values()
		return

	var input_world_direction := _get_camera_relative_input_direction(screen_input_vector)
	var logical_input_vector := Vector2(input_world_direction.x, input_world_direction.z).limit_length(1.0)
	if logical_input_vector.is_zero_approx():
		_clear_move_debug_values()
		return

	var previous_position := logical_hub_position
	var requested_position := previous_position + logical_input_vector * player_move_speed * delta
	logical_hub_position = _resolve_logical_position_with_walk_wall(previous_position, requested_position)

	var move_delta := logical_hub_position - previous_position
	var velocity := Vector2.ZERO
	if delta > 0.0:
		velocity = move_delta / delta
	last_player_move_distance = velocity.length() * delta
	_update_player_visual_offset(logical_input_vector, delta)
	if is_zero_approx(last_player_move_distance):
		last_calculated_rotation_radian = 0.0
		return

	_apply_counter_rotation_for_player_move(input_world_direction, last_player_move_distance)


func _get_screen_input_vector() -> Vector2:
	var x_axis := Input.get_axis("move_left", "move_right")
	var y_axis := Input.get_action_strength("camera_push_forward") - Input.get_action_strength("slow_down")
	return Vector2(x_axis, y_axis).limit_length(1.0)


func _get_camera_relative_input_direction(screen_input_vector: Vector2) -> Vector3:
	var camera_forward := -hub_camera.global_transform.basis.z
	camera_forward.y = 0.0
	camera_forward = _normalized_or_fallback(camera_forward, Vector3.FORWARD)

	var camera_right := hub_camera.global_transform.basis.x
	camera_right.y = 0.0
	camera_right = _normalized_or_fallback(camera_right, Vector3.RIGHT)

	var input_direction := camera_right * screen_input_vector.x + camera_forward * screen_input_vector.y
	input_direction.y = 0.0
	return _normalized_or_fallback(input_direction, Vector3.ZERO)


func _normalized_or_fallback(vector: Vector3, fallback: Vector3) -> Vector3:
	if vector.length_squared() <= 0.000001:
		return fallback
	return vector.normalized()


func _resolve_logical_position_with_walk_wall(previous_position: Vector2, requested_position: Vector2) -> Vector2:
	var radius := maxf(hub_walk_radius, 0.0)
	var radius_squared := radius * radius
	if requested_position.length_squared() <= radius_squared:
		last_is_walk_radius_limited = false
		return requested_position

	last_is_walk_radius_limited = true
	var movement_delta := requested_position - previous_position
	var movement_delta_squared := movement_delta.length_squared()
	if movement_delta_squared <= 0.000001:
		return previous_position.limit_length(radius)

	var previous_distance_squared := previous_position.length_squared()
	if previous_distance_squared >= radius_squared:
		if requested_position.length_squared() < previous_distance_squared:
			return requested_position.limit_length(radius)
		return previous_position.limit_length(radius)

	var b := 2.0 * previous_position.dot(movement_delta)
	var c := previous_distance_squared - radius_squared
	var discriminant := b * b - 4.0 * movement_delta_squared * c
	if discriminant < 0.0:
		return previous_position

	var sqrt_discriminant := sqrt(discriminant)
	var t_a := (-b - sqrt_discriminant) / (2.0 * movement_delta_squared)
	var t_b := (-b + sqrt_discriminant) / (2.0 * movement_delta_squared)
	var hit_t := 1.0
	if t_a >= 0.0 and t_a <= 1.0:
		hit_t = minf(hit_t, t_a)
	if t_b >= 0.0 and t_b <= 1.0:
		hit_t = minf(hit_t, t_b)
	return previous_position + movement_delta * hit_t


func _clear_move_debug_values() -> void:
	last_player_move_distance = 0.0
	last_calculated_rotation_radian = 0.0
	last_is_walk_radius_limited = false
	last_counter_rotation_axis = Vector3.ZERO


func _update_player_visual_offset(input_vector: Vector2, delta: float) -> void:
	var target_offset := input_vector.limit_length(1.0) * player_visual_offset_max
	player_visual_offset = player_visual_offset.move_toward(target_offset, player_visual_offset_follow_speed * delta)


func _apply_counter_rotation_for_player_move(input_world_direction: Vector3, move_distance: float) -> void:
	last_player_move_distance = move_distance
	last_calculated_rotation_radian = last_player_move_distance / maxf(hub_sphere_radius, 0.001)
	var visual_rotation := -last_calculated_rotation_radian * visual_rotation_multiplier
	var movement_direction := input_world_direction.normalized()
	var counter_rotation_axis := Vector3.UP.cross(movement_direction).normalized()
	last_counter_rotation_axis = counter_rotation_axis
	hub_sphere_visual_basis = Basis(counter_rotation_axis, visual_rotation) * hub_sphere_visual_basis
	hub_sphere_visual.transform.basis = hub_sphere_visual_basis
	_store_recent_move_debug(Vector2(movement_direction.x, movement_direction.z), last_player_move_distance, last_calculated_rotation_radian, counter_rotation_axis, visual_rotation)


func _store_recent_move_debug(input_dir: Vector2, move_distance: float, rotation_radian: float, counter_axis: Vector3, visual_rotation: float) -> void:
	recent_move_debug_timer = RECENT_MOVE_DEBUG_HOLD_TIME
	recent_input_dir = input_dir
	recent_move_distance = move_distance
	recent_rotation_radian = rotation_radian
	recent_counter_axis = counter_axis
	recent_visual_rotation = visual_rotation


func _update_recent_move_debug_timer(delta: float) -> void:
	if recent_move_debug_timer <= 0.0:
		return
	recent_move_debug_timer = maxf(recent_move_debug_timer - delta, 0.0)


func _build_debug_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HubDebugLayer"
	add_child(layer)

	debug_label = Label.new()
	debug_label.name = "HubMoveDebugLabel"
	debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_label.add_theme_font_size_override("font_size", 18)
	debug_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	debug_label.offset_left = -DEBUG_PANEL_WIDTH
	debug_label.offset_top = 18
	debug_label.offset_right = -18
	debug_label.offset_bottom = 18 + DEBUG_PANEL_HEIGHT
	layer.add_child(debug_label)


func _update_debug_label() -> void:
	if not debug_label:
		return

	debug_label.text = "Hub Move Debug\nplayer_move_distance: %.4f\nsphere_radius: %.2f\nvisual_rotation_multiplier: %.2f\ncalculated_rotation_radian: %.5f\nhub_walk_radius: %.2f\nlogical_hub_position: (%.2f, %.2f)\nplayer_visual_offset: %.3f\nplayer_distance_from_hub_center: %.4f\nwalk_radius_limited: %s\ncounter_axis: (%.2f, %.2f, %.2f)\nrecent_hold: %.2f\nlast_input_dir: (%.2f, %.2f)\nlast_move_distance: %.4f\nlast_rotation_radian: %.5f\nlast_counter_axis: (%.2f, %.2f, %.2f)\nlast_visual_rotation: %.5f" % [
		last_player_move_distance,
		hub_sphere_radius,
		visual_rotation_multiplier,
		last_calculated_rotation_radian,
		hub_walk_radius,
		logical_hub_position.x,
		logical_hub_position.y,
		player_visual_offset.length(),
		_get_player_distance_from_hub_center(),
		"YES" if last_is_walk_radius_limited else "NO",
		last_counter_rotation_axis.x,
		last_counter_rotation_axis.y,
		last_counter_rotation_axis.z,
		recent_move_debug_timer,
		recent_input_dir.x,
		recent_input_dir.y,
		recent_move_distance,
		recent_rotation_radian,
		recent_counter_axis.x,
		recent_counter_axis.y,
		recent_counter_axis.z,
		recent_visual_rotation
	]


func _get_player_distance_from_hub_center() -> float:
	if not player_node:
		return 0.0
	return player_node.position.length()


func _update_player_visual() -> void:
	var radius := maxf(hub_sphere_radius + SURFACE_OFFSET, 0.001)
	var surface_y := sqrt(maxf(radius * radius - player_visual_offset.length_squared(), 0.0))
	var surface_position := Vector3(player_visual_offset.x, surface_y, player_visual_offset.y)
	player_surface_normal = surface_position.normalized()
	player_node.position = surface_position
	player_node.transform.basis = _basis_from_surface_normal(player_surface_normal)
	player_mesh.position = Vector3(0.0, player_height_units * 0.5, 0.0)


func _basis_from_surface_normal(surface_normal: Vector3) -> Basis:
	var up := surface_normal.normalized()
	var forward := Vector3.FORWARD
	if absf(up.dot(forward)) > 0.98:
		forward = Vector3.RIGHT
	var right := forward.cross(up).normalized()
	forward = up.cross(right).normalized()
	return Basis(right, up, forward)


func _update_camera_transform() -> void:
	var reference_radius := maxf(hub_camera_reference_radius, 0.001)
	var distance := reference_radius * CAMERA_DISTANCE_RATIO
	var surface_anchor_y := hub_sphere_radius
	var height := surface_anchor_y + reference_radius * (CAMERA_HEIGHT_RATIO - 1.0)
	var target := Vector3(0, surface_anchor_y - reference_radius * 0.45, 0)
	camera_rig.position = Vector3.ZERO
	hub_camera.position = Vector3(0, height, distance)
	hub_camera.look_at(target, Vector3.UP)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	return material


func _grid_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.8, 0.9, 0.95, 0.18)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
