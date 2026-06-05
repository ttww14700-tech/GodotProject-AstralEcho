extends Node3D
class_name HubSphereController

signal central_tower_interaction_changed(active: bool)

@export var godot_unit_meters := 1.0
@export var player_height_units := 1.7
@export var natural_step_distance := 0.65
@export var lane_width := 1.2
@export var short_dash_lane_ratio := 0.5
@export var short_dash_distance := 0.6
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
@export var visual_rotation_multiplier := 0.35
@export var player_move_speed := 2.0
@export var hub_walk_radius := 6.0
@export var central_tower_interaction_radius := 2.25
@export var central_tower_interaction_height := 3.2
@export var player_visual_offset_max := 0.4
@export var player_visual_offset_follow_speed := 6.0
@export var project_scene_primitives_to_sphere := true
@export var hub_placement_plane_size := 12.0
@export var show_hub_placement_plane_debug := true
@export var show_hub_grid_alignment_debug := false

const PLAYER_RADIUS_RATIO := 0.16
const CAMERA_DISTANCE_RATIO := 2.2
const CAMERA_HEIGHT_RATIO := 1.25
const SURFACE_OFFSET := 0.02
const GRID_RADIUS_OFFSET := 0.02
const SURFACE_GRID_EXTENT_RATIO := 0.82
const SURFACE_GRID_STEP := 4.0
const SURFACE_GRID_SEGMENT_STEP := 1.0
const DEBUG_PANEL_WIDTH := 430.0
const DEBUG_PANEL_HEIGHT := 280.0
const HUB_CAMERA_MODE := "Angled Mid Follow"
const RECENT_MOVE_DEBUG_HOLD_TIME := 0.5
const HUB_REFERENCE_BOX_SPECS := [
	{"name": "CentralBlockTower", "offset": Vector2(0.0, -2.4), "size": Vector3(1.1, 2.6, 1.1)},
	{"name": "NpcBlockA", "offset": Vector2(-2.2, -0.6), "size": Vector3(0.55, 0.85, 0.55)},
	{"name": "NpcBlockB", "offset": Vector2(2.1, -0.4), "size": Vector3(0.55, 0.85, 0.55)},
	{"name": "NpcBlockC", "offset": Vector2(-1.3, 2.0), "size": Vector3(0.55, 0.85, 0.55)},
	{"name": "DoorFrameLeftPost", "offset": Vector2(2.8, 1.6), "size": Vector3(0.24, 1.25, 0.28)},
	{"name": "DoorFrameRightPost", "offset": Vector2(3.6, 1.6), "size": Vector3(0.24, 1.25, 0.28)},
	{"name": "DoorFrameTopBeam", "offset": Vector2(3.2, 1.6), "size": Vector3(1.08, 0.24, 0.28)},
	{"name": "StepBlockA", "offset": Vector2(-3.0, 1.5), "size": Vector3(1.2, 0.16, 0.42)},
	{"name": "StepBlockB", "offset": Vector2(-3.0, 1.95), "size": Vector3(1.2, 0.22, 0.42)},
	{"name": "StepBlockC", "offset": Vector2(-3.0, 2.4), "size": Vector3(1.2, 0.28, 0.42)},
	{"name": "StepBlockD", "offset": Vector2(-3.0, 2.85), "size": Vector3(1.2, 0.34, 0.42)}
]

var hub_sphere_visual: Node3D
var hub_sphere_mesh: MeshInstance3D
var hub_reference_visuals: Node3D
var hub_placement_plane_debug: MeshInstance3D
var hub_logical_origin_marker: MeshInstance3D
var hub_visual_grid_center_marker: MeshInstance3D
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
var camera_follow_position := Vector3.ZERO
var camera_follow_target := Vector3.ZERO
var camera_follow_initialized := false
var central_tower_interaction_area: Area3D
var central_tower_interaction_shape: CollisionShape3D
var central_tower_interaction_active := false


func _ready() -> void:
	_build_hub_sphere()
	_setup_hub_logical_origin_marker()
	_setup_hub_visual_grid_center_marker()
	_build_player()
	_update_player_visual()
	_setup_hub_reference_primitives()
	_setup_placement_plane_debug()
	_build_camera()
	_build_light()
	_build_debug_overlay()
	_update_debug_label()


func _process(delta: float) -> void:
	_update_recent_move_debug_timer(delta)
	_update_player_movement(delta)
	_update_hub_visual_grid_center_marker()
	_update_grid_alignment_debug_visibility()
	_update_player_visual()
	_update_central_tower_interaction()
	_update_camera_transform(delta)
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
	var extent := radius * SURFACE_GRID_EXTENT_RATIO

	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var offsets := [0.0]
	var offset := SURFACE_GRID_STEP
	while offset <= extent:
		offsets.append(-offset)
		offsets.append(offset)
		offset += SURFACE_GRID_STEP

	for line_offset in offsets:
		_add_projected_grid_line(mesh, Vector2(line_offset, -extent), Vector2(line_offset, extent), radius)
		_add_projected_grid_line(mesh, Vector2(-extent, line_offset), Vector2(extent, line_offset), radius)
	mesh.surface_end()
	return mesh


func _add_projected_grid_line(mesh: ImmediateMesh, start: Vector2, end: Vector2, radius: float) -> void:
	var length := start.distance_to(end)
	var segments := maxi(1, int(ceil(length / SURFACE_GRID_SEGMENT_STEP)))
	var previous := _surface_grid_point(start, radius)
	for segment_index in range(1, segments + 1):
		var t := float(segment_index) / float(segments)
		var current := _surface_grid_point(start.lerp(end, t), radius)
		mesh.surface_add_vertex(previous)
		mesh.surface_add_vertex(current)
		previous = current


func _surface_grid_point(offset: Vector2, radius: float) -> Vector3:
	var clamped_offset := offset.limit_length(maxf(radius - 0.001, 0.0))
	var y := sqrt(maxf(radius * radius - clamped_offset.length_squared(), 0.0))
	return Vector3(clamped_offset.x, y, clamped_offset.y)


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


func _setup_hub_reference_primitives() -> void:
	hub_reference_visuals = get_node_or_null("HubPrimitiveReferenceVisuals") as Node3D
	if not hub_reference_visuals:
		hub_reference_visuals = Node3D.new()
		hub_reference_visuals.name = "HubPrimitiveReferenceVisuals"

	var current_parent := hub_reference_visuals.get_parent()
	if current_parent != hub_sphere_visual:
		if current_parent:
			current_parent.remove_child(hub_reference_visuals)
		hub_sphere_visual.add_child(hub_reference_visuals)

	var reference_material := _material(Color(0.42, 0.42, 0.42))
	for box_spec in HUB_REFERENCE_BOX_SPECS:
		_setup_reference_box(box_spec, reference_material)
	if project_scene_primitives_to_sphere:
		_project_reference_primitives_to_sphere()
	_setup_central_tower_interaction_capsule()


func _setup_reference_box(box_spec: Dictionary, material: Material) -> void:
	var node_name := String(box_spec["name"])
	var surface_offset := box_spec["offset"] as Vector2
	var box_size := box_spec["size"] as Vector3
	var mesh_instance := hub_reference_visuals.get_node_or_null(node_name) as MeshInstance3D
	var created_from_spec := false
	if not mesh_instance:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = node_name
		hub_reference_visuals.add_child(mesh_instance)
		created_from_spec = true

	if not mesh_instance.mesh:
		var box := BoxMesh.new()
		box.size = box_size
		mesh_instance.mesh = box
	if not mesh_instance.material_override:
		mesh_instance.material_override = material

	if created_from_spec:
		mesh_instance.position = Vector3(surface_offset.x, 0.0, surface_offset.y)
		mesh_instance.rotation = Vector3.ZERO


func _project_reference_primitives_to_sphere() -> void:
	if not hub_reference_visuals:
		return

	for child in hub_reference_visuals.get_children():
		var mesh_instance := child as MeshInstance3D
		if mesh_instance:
			_project_reference_primitive_to_sphere(mesh_instance)


func _project_reference_primitive_to_sphere(mesh_instance: MeshInstance3D) -> void:
	var plane_position := mesh_instance.position
	var plane_offset := Vector2(plane_position.x, plane_position.z)
	var height_offset := plane_position.y
	var editor_yaw := mesh_instance.rotation.y
	var local_scale := mesh_instance.scale
	var surface_position := _surface_position_from_offset(plane_offset)
	var surface_normal := surface_position.normalized()
	var mesh_half_height := _get_mesh_half_height(mesh_instance)

	mesh_instance.position = surface_position + surface_normal * (mesh_half_height + height_offset)
	mesh_instance.transform.basis = _basis_from_surface_normal_with_yaw(surface_normal, editor_yaw)
	mesh_instance.scale = local_scale


func _get_mesh_half_height(mesh_instance: MeshInstance3D) -> float:
	if not mesh_instance.mesh:
		return 0.0
	return mesh_instance.mesh.get_aabb().size.y * absf(mesh_instance.scale.y) * 0.5


func _setup_placement_plane_debug() -> void:
	hub_placement_plane_debug = get_node_or_null("HubPlacementPlaneDebug") as MeshInstance3D
	if not hub_placement_plane_debug:
		hub_placement_plane_debug = MeshInstance3D.new()
		hub_placement_plane_debug.name = "HubPlacementPlaneDebug"
		add_child(hub_placement_plane_debug)

	var plane := PlaneMesh.new()
	plane.size = Vector2(hub_placement_plane_size, hub_placement_plane_size)
	hub_placement_plane_debug.mesh = plane
	hub_placement_plane_debug.material_override = _placement_plane_material()
	hub_placement_plane_debug.position = Vector3.ZERO
	hub_placement_plane_debug.rotation = Vector3.ZERO
	hub_placement_plane_debug.visible = show_hub_placement_plane_debug


func _setup_hub_logical_origin_marker() -> void:
	hub_logical_origin_marker = get_node_or_null("HubLogicalOriginMarker") as MeshInstance3D
	if not hub_logical_origin_marker:
		hub_logical_origin_marker = MeshInstance3D.new()
		hub_logical_origin_marker.name = "HubLogicalOriginMarker"
		add_child(hub_logical_origin_marker)

	var marker_mesh := SphereMesh.new()
	marker_mesh.radius = 0.25
	marker_mesh.height = 0.5
	marker_mesh.radial_segments = 16
	marker_mesh.rings = 8
	hub_logical_origin_marker.mesh = marker_mesh
	hub_logical_origin_marker.material_override = _material(Color(1.0, 0.86, 0.18))
	hub_logical_origin_marker.position = _surface_position_from_offset(Vector2.ZERO)
	hub_logical_origin_marker.rotation = Vector3.ZERO
	_update_grid_alignment_debug_visibility()


func _setup_hub_visual_grid_center_marker() -> void:
	hub_visual_grid_center_marker = get_node_or_null("HubVisualGridCenterMarker") as MeshInstance3D
	if not hub_visual_grid_center_marker:
		hub_visual_grid_center_marker = MeshInstance3D.new()
		hub_visual_grid_center_marker.name = "HubVisualGridCenterMarker"
		add_child(hub_visual_grid_center_marker)

	var marker_mesh := SphereMesh.new()
	marker_mesh.radius = 0.18
	marker_mesh.height = 0.36
	marker_mesh.radial_segments = 16
	marker_mesh.rings = 8
	hub_visual_grid_center_marker.mesh = marker_mesh
	hub_visual_grid_center_marker.material_override = _material(Color(0.95, 0.18, 0.18))
	_update_hub_visual_grid_center_marker()
	_update_grid_alignment_debug_visibility()


func _update_hub_visual_grid_center_marker() -> void:
	if not hub_visual_grid_center_marker or not hub_sphere_visual:
		return

	var grid_center_local := _surface_grid_point(Vector2.ZERO, hub_sphere_radius + GRID_RADIUS_OFFSET)
	hub_visual_grid_center_marker.global_position = hub_sphere_visual.to_global(grid_center_local)


func _update_grid_alignment_debug_visibility() -> void:
	if hub_logical_origin_marker:
		hub_logical_origin_marker.visible = show_hub_grid_alignment_debug
	if hub_visual_grid_center_marker:
		hub_visual_grid_center_marker.visible = show_hub_grid_alignment_debug


func _setup_central_tower_interaction_capsule() -> void:
	var central_tower := hub_reference_visuals.get_node_or_null("CentralBlockTower") as Node3D
	if not central_tower:
		return

	central_tower_interaction_area = central_tower.get_node_or_null("InteractionCapsule") as Area3D
	if not central_tower_interaction_area:
		central_tower_interaction_area = Area3D.new()
		central_tower_interaction_area.name = "InteractionCapsule"
		central_tower.add_child(central_tower_interaction_area)

	central_tower_interaction_shape = central_tower_interaction_area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not central_tower_interaction_shape:
		central_tower_interaction_shape = CollisionShape3D.new()
		central_tower_interaction_shape.name = "CollisionShape3D"
		central_tower_interaction_area.add_child(central_tower_interaction_shape)

	var capsule := CapsuleShape3D.new()
	capsule.radius = central_tower_interaction_radius
	capsule.height = central_tower_interaction_height
	central_tower_interaction_shape.shape = capsule


func _surface_position_from_offset(surface_offset: Vector2) -> Vector3:
	var radius := maxf(hub_sphere_radius + SURFACE_OFFSET, 0.001)
	var clamped_offset := surface_offset.limit_length(maxf(radius - 0.001, 0.0))
	var surface_y := sqrt(maxf(radius * radius - clamped_offset.length_squared(), 0.0))
	return Vector3(clamped_offset.x, surface_y, clamped_offset.y)


func _update_central_tower_interaction() -> void:
	var is_active := _is_player_inside_central_tower_capsule()
	if is_active == central_tower_interaction_active:
		return
	central_tower_interaction_active = is_active
	central_tower_interaction_changed.emit(central_tower_interaction_active)


func _is_player_inside_central_tower_capsule() -> bool:
	if not player_node or not central_tower_interaction_area:
		return false

	var tower_position := central_tower_interaction_area.global_position
	var player_position := player_node.global_position
	var tower_normal := tower_position.normalized()
	if tower_normal.is_zero_approx():
		tower_normal = Vector3.UP

	var to_player := player_position - tower_position
	var vertical_distance := to_player.dot(tower_normal)
	var horizontal_distance := (to_player - tower_normal * vertical_distance).length()
	return absf(vertical_distance) <= central_tower_interaction_height * 0.5 and horizontal_distance <= central_tower_interaction_radius


func _build_camera() -> void:
	camera_rig = Node3D.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)

	hub_camera = Camera3D.new()
	hub_camera.name = "HubCamera"
	hub_camera.fov = hub_camera_fov
	hub_camera.current = true
	camera_rig.add_child(hub_camera)
	_update_camera_transform(0.0, true)


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

	var player_global_position := player_node.global_position if player_node else Vector3.ZERO
	var player_local_position := player_node.position if player_node else Vector3.ZERO
	var player_bottom_projected_point := _get_player_bottom_projected_point()
	var sphere_rotation_degrees := hub_sphere_visual.rotation_degrees if hub_sphere_visual else Vector3.ZERO
	var camera_global_rotation_degrees := hub_camera.global_rotation_degrees if hub_camera else Vector3.ZERO
	debug_label.text = "Hub Spawn Debug\nplayer global_position: %s\nplayer local position: %s\nlogical_hub_position: %s\nplayer bottom projected point: %s\nHub controller global_position: %s\nHubSphereVisual rotation_degrees: %s\ncamera global_rotation_degrees: %s" % [
		_format_vector3(player_global_position),
		_format_vector3(player_local_position),
		_format_vector2(logical_hub_position),
		_format_vector3(player_bottom_projected_point),
		_format_vector3(global_position),
		_format_vector3(sphere_rotation_degrees),
		_format_vector3(camera_global_rotation_degrees)
	]
	if show_hub_grid_alignment_debug:
		debug_label.text += "\norigin_grid_center_distance: %.3f" % _get_origin_grid_center_distance()


func _get_origin_grid_center_distance() -> float:
	if not hub_logical_origin_marker or not hub_visual_grid_center_marker:
		return 0.0
	return hub_logical_origin_marker.global_position.distance_to(hub_visual_grid_center_marker.global_position)


func _get_player_bottom_projected_point() -> Vector3:
	if not player_node:
		return Vector3.ZERO

	var player_bottom_local := player_node.position
	var projected_local := _surface_position_from_offset(Vector2(player_bottom_local.x, player_bottom_local.z))
	return global_transform * projected_local


func _format_vector2(value: Vector2) -> String:
	return "(%.3f, %.3f)" % [value.x, value.y]


func _format_vector3(value: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [value.x, value.y, value.z]


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


func _basis_from_surface_normal_with_yaw(surface_normal: Vector3, yaw: float) -> Basis:
	var up := surface_normal.normalized()
	return Basis(up, yaw) * _basis_from_surface_normal(up)


func _update_camera_transform(delta: float, snap := false) -> void:
	if not hub_camera:
		return

	hub_camera.fov = hub_camera_fov
	var player_anchor := _get_hub_camera_anchor()
	var yaw := deg_to_rad(hub_camera_yaw_offset_deg)
	var camera_direction := Vector3(sin(yaw), 0.0, cos(yaw)).normalized()
	var desired_position := player_anchor + camera_direction * hub_camera_distance + Vector3.UP * hub_camera_height
	var pitch_drop := tan(deg_to_rad(hub_camera_pitch_deg)) * hub_camera_distance
	var screen_offset_lift := clampf(hub_camera_screen_offset_y, 0.0, 0.2) * hub_camera_distance
	var desired_target := Vector3(player_anchor.x, desired_position.y - pitch_drop + hub_camera_look_at_height + screen_offset_lift, player_anchor.z)

	if snap or not camera_follow_initialized:
		camera_follow_position = desired_position
		camera_follow_target = desired_target
		camera_follow_initialized = true
	else:
		var follow_weight := clampf(delta * hub_camera_follow_lerp_speed, 0.0, 1.0)
		camera_follow_position = camera_follow_position.lerp(desired_position, follow_weight)
		camera_follow_target = camera_follow_target.lerp(desired_target, follow_weight)

	camera_rig.position = Vector3.ZERO
	hub_camera.global_position = camera_follow_position
	hub_camera.look_at(camera_follow_target, Vector3.UP)


func _get_hub_camera_anchor() -> Vector3:
	if player_node:
		return player_node.global_position
	return Vector3(0.0, hub_sphere_radius + SURFACE_OFFSET, 0.0)


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


func _placement_plane_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.22, 0.62, 0.9, 0.18)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
