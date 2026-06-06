extends Node3D

const FACE_DETECTION_RADIUS_MULTIPLIER := 4.0
const MIN_FACE_DETECTION_DISTANCE := 3.0
# Placeholder temporary value only; formal monsters should provide reliable collision shapes.
const PLACEHOLDER_FALLBACK_COLLISION_RADIUS := 0.6

@export var show_forward_debug := false:
	set(value):
		show_forward_debug = value
		_apply_forward_debug_visibility()

# Temporary workaround only for imported test-model facing correction.
# Formal monster models must be exported/imported facing local -Z at rotation (0, 0, 0).
@export var temporary_visual_rotation_correction_degrees := Vector3.ZERO:
	set(value):
		temporary_visual_rotation_correction_degrees = value
		_apply_temporary_visual_rotation_correction()

@onready var visual_root := get_node_or_null("VisualRoot") as Node3D
@onready var forward_debug_root := get_node_or_null("ForwardDebugRoot") as Node3D

var current_player_distance := INF
var current_face_detection_distance := 0.0
var is_player_within_face_detection_distance := false


func _ready() -> void:
	_apply_temporary_visual_rotation_correction()
	_apply_forward_debug_visibility()
	current_face_detection_distance = get_face_detection_distance()


func configure(size_multiplier: float, show_forward_debug_value: bool) -> void:
	scale = Vector3.ONE * maxf(size_multiplier, 0.001)
	show_forward_debug = show_forward_debug_value


func face_toward_global_position(target_position: Vector3) -> void:
	var flat_target := target_position
	flat_target.y = global_position.y
	if global_position.distance_squared_to(flat_target) < 0.0001:
		return
	look_at(flat_target, Vector3.UP)


func get_forward_direction() -> Vector3:
	return -global_transform.basis.z.normalized()


func update_player_face_detection(player_position: Vector3, should_turn_when_detected := true) -> void:
	# Temporary 3D distance. Future sphere/lane gameplay can replace this with path or surface distance.
	current_player_distance = global_position.distance_to(player_position)
	current_face_detection_distance = get_face_detection_distance()
	is_player_within_face_detection_distance = current_player_distance <= current_face_detection_distance
	if should_turn_when_detected and is_player_within_face_detection_distance:
		face_toward_global_position(player_position)


func get_collision_radius() -> float:
	var radius := 0.0
	for collision_shape in _collect_collision_shapes():
		radius = maxf(radius, _collision_shape_horizontal_radius(collision_shape))
	if radius <= 0.0:
		return PLACEHOLDER_FALLBACK_COLLISION_RADIUS * _global_horizontal_scale(self)
	return radius


func get_face_detection_distance() -> float:
	return maxf(get_collision_radius() * FACE_DETECTION_RADIUS_MULTIPLIER, MIN_FACE_DETECTION_DISTANCE)


func get_current_player_distance() -> float:
	return current_player_distance


func is_player_within_face_detection() -> bool:
	return is_player_within_face_detection_distance


func get_visual_rotation_correction_degrees() -> Vector3:
	return temporary_visual_rotation_correction_degrees


func has_zero_visual_rotation_correction() -> bool:
	return temporary_visual_rotation_correction_degrees.is_equal_approx(Vector3.ZERO)


func has_expected_visual_wrapper() -> bool:
	# FireRockGolem placeholder test only; formal monsters are not required to use this wrapper name.
	if not visual_root:
		return false
	return visual_root.has_node("AE_FireRockGolem_TestWrapper")


func _collect_collision_shapes() -> Array[CollisionShape3D]:
	var shapes: Array[CollisionShape3D] = []
	var pending_nodes: Array[Node] = [self]
	while not pending_nodes.is_empty():
		var node := pending_nodes.pop_back() as Node
		for child in node.get_children():
			pending_nodes.append(child)

		var collision_shape := node as CollisionShape3D
		if collision_shape and collision_shape.shape:
			shapes.append(collision_shape)
	return shapes


func _collision_shape_horizontal_radius(collision_shape: CollisionShape3D) -> float:
	var shape := collision_shape.shape
	if shape is BoxShape3D:
		var box_shape := shape as BoxShape3D
		return _box_shape_horizontal_radius(collision_shape, box_shape.size)
	if shape is SphereShape3D:
		var sphere_shape := shape as SphereShape3D
		return sphere_shape.radius * _global_horizontal_scale(collision_shape)
	if shape is CapsuleShape3D:
		var capsule_shape := shape as CapsuleShape3D
		return capsule_shape.radius * _global_horizontal_scale(collision_shape)
	if shape is CylinderShape3D:
		var cylinder_shape := shape as CylinderShape3D
		return cylinder_shape.radius * _global_horizontal_scale(collision_shape)
	return 0.0


func _box_shape_horizontal_radius(collision_shape: CollisionShape3D, size: Vector3) -> float:
	var center: Vector3 = collision_shape.global_position
	var half_x: Vector3 = collision_shape.global_transform.basis.x * size.x * 0.5
	var half_z: Vector3 = collision_shape.global_transform.basis.z * size.z * 0.5
	var radius := 0.0
	for x_index in range(2):
		var x_sign: float = -1.0 if x_index == 0 else 1.0
		for z_index in range(2):
			var z_sign: float = -1.0 if z_index == 0 else 1.0
			var corner: Vector3 = center + half_x * x_sign + half_z * z_sign
			var horizontal_offset: Vector2 = Vector2(corner.x - center.x, corner.z - center.z)
			radius = maxf(radius, horizontal_offset.length())
	return radius


func _global_horizontal_scale(node: Node3D) -> float:
	var basis := node.global_transform.basis
	var xz_scale := Vector2(basis.x.length(), basis.z.length())
	return maxf(xz_scale.x, xz_scale.y)


func _apply_temporary_visual_rotation_correction() -> void:
	if not visual_root:
		return
	visual_root.rotation_degrees = temporary_visual_rotation_correction_degrees


func _apply_forward_debug_visibility() -> void:
	if not forward_debug_root:
		return
	forward_debug_root.visible = show_forward_debug
