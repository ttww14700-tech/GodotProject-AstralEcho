extends CharacterBody3D

@export var use_original_model_materials := true
@export var use_segmented_runner := true
@export var hide_imported_model_when_segmented := true
@export var greybox_albedo := Color(0.72, 0.74, 0.76, 1.0)
@export var greybox_roughness := 0.72
@export var run_bob_height := 0.045
@export var run_side_sway := 0.018
@export var run_frequency := 8.5
@export var run_forward_lean_deg := 4.0
@export var lateral_lean_deg := 7.0
@export var dash_lean_deg := 14.0
@export var dodge_crouch_height := 0.06
@export var skill_pulse_scale := 0.04
@export var attack_slash_raise_deg := 148.0
@export var attack_slash_forward_deg := 64.0
@export var attack_slash_side_deg := 34.0
@export var attack_torso_twist_deg := 11.0
@export var visual_lerp_speed := 12.0

var _greybox_material: StandardMaterial3D
var _visual_root: Node3D
var _base_visual_position := Vector3.ZERO
var _base_visual_rotation_degrees := Vector3.ZERO
var _base_visual_scale := Vector3.ONE
var _run_phase := 0.0
var _current_visual_position := Vector3.ZERO
var _current_visual_rotation_degrees := Vector3.ZERO
var _current_visual_scale := Vector3.ONE
var _segmented_runner_root: Node3D
var _runner_parts := {}
var _runner_part_base_rotations := {}


func _ready() -> void:
	_visual_root = get_node_or_null("VisualRoot") as Node3D
	if _visual_root:
		_base_visual_position = _visual_root.position
		_base_visual_rotation_degrees = _visual_root.rotation_degrees
		_base_visual_scale = _visual_root.scale
		_current_visual_position = _base_visual_position
		_current_visual_rotation_degrees = _base_visual_rotation_degrees
		_current_visual_scale = _base_visual_scale
		if use_segmented_runner:
			_setup_segmented_runner()
	if not use_original_model_materials:
		_apply_greybox_material()


func update_run_visual_state(delta: float, lateral_axis: float, forward_axis: float, speed_ratio: float, is_controlled: bool, lane_dash_active: bool, lane_dash_direction: float, dodge_active: bool, skill_active: bool, attack_active: bool, attack_progress: float, target_yaw_deg: float) -> void:
	if not _visual_root:
		return

	var stride_strength := clampf(speed_ratio, 0.25, 1.65)
	if not is_controlled:
		stride_strength *= 0.85
	_run_phase = fmod(_run_phase + delta * run_frequency * stride_strength, TAU)

	var stride := sin(_run_phase)
	var footfall := absf(stride)
	var bob_y := footfall * run_bob_height * stride_strength
	var sway_x := stride * run_side_sway * stride_strength
	var dodge_crouch := dodge_crouch_height if dodge_active else 0.0

	var effective_lateral_axis := lateral_axis
	if lane_dash_active and not is_zero_approx(lane_dash_direction):
		effective_lateral_axis = lane_dash_direction
	var target_roll := -effective_lateral_axis * lateral_lean_deg
	if lane_dash_active:
		target_roll += -lane_dash_direction * dash_lean_deg

	var forward_lean := -run_forward_lean_deg * stride_strength
	if forward_axis > 0.0:
		forward_lean -= 2.5
	elif forward_axis < 0.0:
		forward_lean += 6.0
	if dodge_active:
		forward_lean += 4.0

	var skill_scale := 1.0
	if skill_active:
		skill_scale += skill_pulse_scale * (0.5 + 0.5 * sin(_run_phase * 2.0))

	var target_position := _base_visual_position + Vector3(sway_x, bob_y - dodge_crouch, 0.0)
	var target_rotation := _base_visual_rotation_degrees + Vector3(forward_lean, target_yaw_deg, target_roll)
	var target_scale := _base_visual_scale * skill_scale
	var alpha := clampf(1.0 - exp(-visual_lerp_speed * delta), 0.0, 1.0)

	_current_visual_position = _current_visual_position.lerp(target_position, alpha)
	_current_visual_rotation_degrees = _current_visual_rotation_degrees.lerp(target_rotation, alpha)
	_current_visual_scale = _current_visual_scale.lerp(target_scale, alpha)
	_visual_root.position = _current_visual_position
	_visual_root.rotation_degrees = _current_visual_rotation_degrees
	_visual_root.scale = _current_visual_scale
	_update_segmented_runner_pose(stride, footfall, stride_strength, effective_lateral_axis, lane_dash_active, lane_dash_direction, dodge_active, skill_active, attack_active, attack_progress)


func _setup_segmented_runner() -> void:
	if not _visual_root:
		return
	_set_imported_model_visible(not hide_imported_model_when_segmented)
	_segmented_runner_root = _visual_root.get_node_or_null("SegmentedRunnerRoot") as Node3D
	if not _segmented_runner_root:
		_segmented_runner_root = Node3D.new()
		_segmented_runner_root.name = "SegmentedRunnerRoot"
		_visual_root.add_child(_segmented_runner_root)
	_build_segmented_runner_parts()


func _set_imported_model_visible(is_visible: bool) -> void:
	if not _visual_root:
		return
	for child in _visual_root.get_children():
		if child.name == "SegmentedRunnerRoot":
			continue
		var node_3d := child as Node3D
		if node_3d:
			node_3d.visible = is_visible


func _build_segmented_runner_parts() -> void:
	for child in _segmented_runner_root.get_children():
		child.queue_free()
	_runner_parts.clear()
	_runner_part_base_rotations.clear()

	var body_color := Color(0.62, 0.68, 0.76)
	var head_color := Color(0.78, 0.80, 0.82)
	var arm_color := Color(0.56, 0.62, 0.70)
	var leg_color := Color(0.42, 0.48, 0.58)
	var accent_color := Color(0.30, 0.55, 0.95)

	_add_box_part("Pelvis", _segmented_runner_root, Vector3(0.0, 0.43, 0.0), Vector3(0.28, 0.12, 0.16), body_color)
	_add_box_part("Torso", _segmented_runner_root, Vector3(0.0, 0.65, 0.0), Vector3(0.34, 0.34, 0.18), body_color)
	_add_box_part("ChestAccent", _segmented_runner_root, Vector3(0.0, 0.70, -0.095), Vector3(0.20, 0.15, 0.02), accent_color)
	_add_sphere_part("Head", _segmented_runner_root, Vector3(0.0, 0.94, 0.0), 0.09, head_color)

	_add_limb_part("LeftArm", Vector3(-0.23, 0.75, 0.0), 0.36, 0.075, arm_color)
	_add_limb_part("RightArm", Vector3(0.23, 0.75, 0.0), 0.36, 0.075, arm_color)
	_add_limb_part("LeftLeg", Vector3(-0.105, 0.40, 0.0), 0.40, 0.085, leg_color)
	_add_limb_part("RightLeg", Vector3(0.105, 0.40, 0.0), 0.40, 0.085, leg_color)

	_store_runner_base_rotation("LeftArm", Vector3(8.0, 0.0, -8.0))
	_store_runner_base_rotation("RightArm", Vector3(8.0, 0.0, 8.0))
	_store_runner_base_rotation("LeftLeg", Vector3.ZERO)
	_store_runner_base_rotation("RightLeg", Vector3.ZERO)


func _add_box_part(part_name: String, parent: Node3D, local_position: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = part_name
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.position = local_position
	mesh_instance.material_override = _runner_material(color)
	parent.add_child(mesh_instance)
	_runner_parts[part_name] = mesh_instance
	return mesh_instance


func _add_sphere_part(part_name: String, parent: Node3D, local_position: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = part_name
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	mesh_instance.mesh = sphere
	mesh_instance.position = local_position
	mesh_instance.material_override = _runner_material(color)
	parent.add_child(mesh_instance)
	_runner_parts[part_name] = mesh_instance
	return mesh_instance


func _add_limb_part(part_name: String, pivot_position: Vector3, length: float, thickness: float, color: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = "%sPivot" % part_name
	pivot.position = pivot_position
	_segmented_runner_root.add_child(pivot)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = part_name
	var box := BoxMesh.new()
	box.size = Vector3(thickness, length, thickness)
	mesh_instance.mesh = box
	mesh_instance.position = Vector3(0.0, -length * 0.5, 0.0)
	mesh_instance.material_override = _runner_material(color)
	pivot.add_child(mesh_instance)

	_runner_parts[part_name] = pivot
	return pivot


func _store_runner_base_rotation(part_name: String, rotation_degrees_value: Vector3) -> void:
	var part := _runner_parts.get(part_name) as Node3D
	if not part:
		return
	part.rotation_degrees = rotation_degrees_value
	_runner_part_base_rotations[part_name] = rotation_degrees_value


func _update_segmented_runner_pose(stride: float, footfall: float, stride_strength: float, lateral_axis: float, lane_dash_active: bool, lane_dash_direction: float, dodge_active: bool, skill_active: bool, attack_active: bool, attack_progress: float) -> void:
	if not _segmented_runner_root:
		return
	var swing := stride * 34.0 * stride_strength
	var secondary_swing := cos(_run_phase) * 8.0 * stride_strength
	var crouch := 0.045 if dodge_active else 0.0
	var dash_boost := 9.0 if lane_dash_active else 0.0
	var dash_sign := lane_dash_direction if not is_zero_approx(lane_dash_direction) else lateral_axis

	_segmented_runner_root.position = Vector3(0.0, -crouch, 0.0)
	_segmented_runner_root.rotation_degrees = Vector3(0.0, 0.0, -lateral_axis * 4.0 - dash_sign * dash_boost)
	_set_part_rotation("LeftArm", Vector3(8.0 - swing, 0.0, -8.0 + secondary_swing * 0.25))
	_set_part_rotation("RightArm", Vector3(8.0 + swing, 0.0, 8.0 - secondary_swing * 0.25))
	_set_part_rotation("LeftLeg", Vector3(swing * 0.85, 0.0, -3.0 * footfall))
	_set_part_rotation("RightLeg", Vector3(-swing * 0.85, 0.0, 3.0 * footfall))

	var torso := _runner_parts.get("Torso") as Node3D
	if torso:
		torso.rotation_degrees = Vector3(-footfall * 2.5, 0.0, lateral_axis * 2.0)
	var pelvis := _runner_parts.get("Pelvis") as Node3D
	if pelvis:
		pelvis.rotation_degrees = Vector3(0.0, 0.0, -stride * 3.0)
	var head := _runner_parts.get("Head") as Node3D
	if head:
		head.position.y = 0.94 + footfall * 0.015 * stride_strength
	if skill_active:
		_set_part_rotation("RightArm", Vector3(-72.0, -10.0, 18.0))
	if attack_active:
		_apply_attack_slash_pose(clampf(attack_progress, 0.0, 1.0), lateral_axis)


func _set_part_rotation(part_name: String, rotation_degrees_value: Vector3) -> void:
	var part := _runner_parts.get(part_name) as Node3D
	if part:
		part.rotation_degrees = rotation_degrees_value


func _apply_attack_slash_pose(progress: float, lateral_axis: float) -> void:
	var base_pose := Vector3(8.0, 0.0, 8.0)
	var raised_pose := Vector3(attack_slash_raise_deg, -attack_slash_side_deg, 40.0)
	var strike_pose := Vector3(attack_slash_forward_deg, attack_slash_side_deg * 0.45, -34.0)
	var recovery_pose := Vector3(18.0, attack_slash_side_deg * 0.15, -6.0)
	var arm_pose := base_pose
	var strike_weight := 0.0

	if progress < 0.34:
		var t := _ease_out_cubic(progress / 0.34)
		arm_pose = base_pose.lerp(raised_pose, t)
	elif progress < 0.68:
		var t := _ease_in_cubic((progress - 0.34) / 0.34)
		arm_pose = raised_pose.lerp(strike_pose, t)
		strike_weight = t
	elif progress < 0.86:
		var t := _ease_out_cubic((progress - 0.68) / 0.18)
		arm_pose = strike_pose.lerp(recovery_pose, t)
		strike_weight = 1.0 - t * 0.35
	else:
		var t := _ease_out_cubic((progress - 0.86) / 0.14)
		arm_pose = recovery_pose.lerp(base_pose, t)
		strike_weight = 0.25 * (1.0 - t)

	_set_part_rotation("RightArm", arm_pose)

	var torso := _runner_parts.get("Torso") as Node3D
	if torso:
		torso.rotation_degrees.x -= 5.0 * strike_weight
		torso.rotation_degrees.y = attack_torso_twist_deg * strike_weight
		torso.rotation_degrees.z += lateral_axis * 1.5 - attack_torso_twist_deg * 0.35 * strike_weight


func _ease_in_cubic(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * t


func _ease_out_cubic(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)


func _runner_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.0
	material.roughness = 0.78
	return material


func _apply_greybox_material() -> void:
	_greybox_material = StandardMaterial3D.new()
	_greybox_material.albedo_color = greybox_albedo
	_greybox_material.metallic = 0.0
	_greybox_material.roughness = greybox_roughness
	_greybox_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_apply_material_recursive(self)


func _apply_material_recursive(node: Node) -> void:
	var mesh_instance := node as MeshInstance3D
	if mesh_instance and mesh_instance.mesh:
		mesh_instance.material_override = _greybox_material

	for child in node.get_children():
		_apply_material_recursive(child)
