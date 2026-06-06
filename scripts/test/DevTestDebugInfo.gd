extends Label3D

const TARGET_PATHS := [
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

	var bounds_size := _calculate_bounds_size(target)
	var bounds_text := _format_vector3(bounds_size) if has_mesh_bounds else "unavailable"

	text = "target name: %s\nposition: %s\nrotation: %s\nscale: %s\nbounding box size: %s" % [
		target.name,
		_format_vector3(target.position),
		_format_vector3(target.rotation_degrees),
		_format_vector3(target.scale),
		bounds_text,
	]


func _find_target() -> Node3D:
	for target_path in TARGET_PATHS:
		var target := get_node_or_null(target_path) as Node3D
		if target:
			return target
	return null


func _calculate_bounds_size(target: Node3D) -> Vector3:
	var combined_bounds := AABB()
	has_mesh_bounds = false
	var pending_nodes: Array[Node] = [target]

	while not pending_nodes.is_empty():
		var node := pending_nodes.pop_back() as Node
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
