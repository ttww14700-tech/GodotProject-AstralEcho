extends Label3D

const TARGET_PATHS := [
	NodePath("../../ModelTestRoot/RunMonsterOrientationCheck"),
	NodePath("../../ModelTestRoot/FireRockGolem"),
	NodePath("../../ModelTestRoot/FireRockGolemTest"),
]

var has_mesh_bounds := false


func _ready() -> void:
	_refresh_debug_text()


func _process(_delta: float) -> void:
	_refresh_debug_text()


func _refresh_debug_text() -> void:
	var target := _find_target()
	if not target:
		text = "No model target found"
		return

	var player_target := _find_player_target()
	if player_target and target.has_method("update_player_face_detection"):
		target.call("update_player_face_detection", player_target.global_position, false)

	var bounds_size := _calculate_bounds_size(target)
	var bounds_text := _format_vector3(bounds_size) if has_mesh_bounds else "unavailable"

	var forward_text := "unavailable"
	if target.has_method("get_forward_direction"):
		var forward_direction: Vector3 = target.call("get_forward_direction")
		forward_text = _format_vector3(forward_direction)

	var visual_correction_text := "unavailable"
	var visual_correction_status := "unavailable"
	if target.has_method("get_visual_rotation_correction_degrees"):
		var visual_correction: Vector3 = target.call("get_visual_rotation_correction_degrees")
		visual_correction_text = _format_vector3(visual_correction)
		if target.has_method("has_zero_visual_rotation_correction") and target.call("has_zero_visual_rotation_correction"):
			visual_correction_status = "zero"
		else:
			visual_correction_status = "non-zero temporary"

	var fire_rock_golem_wrapper_text := "unavailable"
	if target.has_method("has_expected_visual_wrapper"):
		fire_rock_golem_wrapper_text = "yes" if target.call("has_expected_visual_wrapper") else "no"

	var face_detection_distance_text := "unavailable"
	if target.has_method("get_face_detection_distance"):
		face_detection_distance_text = "%.3f" % float(target.call("get_face_detection_distance"))

	var current_player_distance_text := "unavailable"
	if target.has_method("get_current_player_distance"):
		var current_player_distance := float(target.call("get_current_player_distance"))
		current_player_distance_text = "not updated" if current_player_distance >= INF else "%.3f" % current_player_distance

	var within_face_detection_text := "unavailable"
	if target.has_method("is_player_within_face_detection"):
		within_face_detection_text = "yes" if target.call("is_player_within_face_detection") else "no"

	text = "target name: %s\nposition: %s\nrotation: %s\nscale: %s\nforward (-Z): %s\nvisual correction: %s\nvisual correction status: %s\nFireRockGolem wrapper under VisualRoot: %s\nface detection distance: %s\ncurrent distance to player: %s\nwithin face detection: %s\nbounding box size: %s" % [
		target.name,
		_format_vector3(target.position),
		_format_vector3(target.rotation_degrees),
		_format_vector3(target.scale),
		forward_text,
		visual_correction_text,
		visual_correction_status,
		fire_rock_golem_wrapper_text,
		face_detection_distance_text,
		current_player_distance_text,
		within_face_detection_text,
		bounds_text,
	]


func _find_target() -> Node3D:
	for target_path in TARGET_PATHS:
		var target := get_node_or_null(target_path) as Node3D
		if target:
			return target
	return null


func _find_player_target() -> Node3D:
	return get_node_or_null(NodePath("../../PlayerTestRoot/TestCollisionPawn")) as Node3D


func _calculate_bounds_size(target: Node3D) -> Vector3:
	var combined_bounds := AABB()
	has_mesh_bounds = false
	var pending_nodes: Array[Node] = [target]

	while not pending_nodes.is_empty():
		var node := pending_nodes.pop_back() as Node
		if node.name == "ForwardDebugRoot":
			continue
		for child in node.get_children():
			pending_nodes.append(child)

		var mesh_instance := node as MeshInstance3D
		if mesh_instance and mesh_instance.mesh:
			var global_bounds := mesh_instance.global_transform * mesh_instance.get_aabb()
			if has_mesh_bounds:
				combined_bounds = combined_bounds.merge(global_bounds)
			else:
				combined_bounds = global_bounds
				has_mesh_bounds = true

	return combined_bounds.size if has_mesh_bounds else Vector3.ZERO


func _format_vector3(value: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [value.x, value.y, value.z]
