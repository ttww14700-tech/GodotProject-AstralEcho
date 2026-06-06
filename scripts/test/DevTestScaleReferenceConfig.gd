@tool
extends Node3D
class_name DevTestScaleReferenceConfig

const PLAYER_HEIGHT := 1.7
const SMALL_MONSTER_HEIGHT := 1.5
const MEDIUM_MONSTER_HEIGHT := 2.0
const LARGE_MONSTER_HEIGHT := 3.0

enum ReferenceKind {
	PLAYER,
	SMALL_MONSTER,
	MEDIUM_MONSTER,
	LARGE_MONSTER,
}

@export var reference_kind: ReferenceKind = ReferenceKind.PLAYER:
	set(value):
		reference_kind = value
		_apply_reference_values()

@export var body_radius := 0.22:
	set(value):
		body_radius = value
		_apply_reference_values()


static func get_height(reference_type: ReferenceKind) -> float:
	match reference_type:
		ReferenceKind.SMALL_MONSTER:
			return SMALL_MONSTER_HEIGHT
		ReferenceKind.MEDIUM_MONSTER:
			return MEDIUM_MONSTER_HEIGHT
		ReferenceKind.LARGE_MONSTER:
			return LARGE_MONSTER_HEIGHT
		_:
			return PLAYER_HEIGHT


static func get_label(reference_type: ReferenceKind) -> String:
	match reference_type:
		ReferenceKind.SMALL_MONSTER:
			return "Small 1.5m"
		ReferenceKind.MEDIUM_MONSTER:
			return "Medium 2.0m"
		ReferenceKind.LARGE_MONSTER:
			return "Large 3.0m"
		_:
			return "Player 1.7m"


func _ready() -> void:
	_make_meshes_unique_to_reference()
	_apply_reference_values()


func _make_meshes_unique_to_reference() -> void:
	for node_path in [
		"BodyHeightSilhouette",
		"HeightRuler",
		"FootHeightTick",
		"HalfHeightTick",
		"HeadHeightTick",
	]:
		var mesh_instance := get_node_or_null(node_path) as MeshInstance3D
		if mesh_instance and mesh_instance.mesh:
			mesh_instance.mesh = mesh_instance.mesh.duplicate()


func _apply_reference_values() -> void:
	var height := get_height(reference_kind)
	var body := get_node_or_null("BodyHeightSilhouette") as MeshInstance3D
	var ruler := get_node_or_null("HeightRuler") as MeshInstance3D
	var foot_tick := get_node_or_null("FootHeightTick") as MeshInstance3D
	var half_tick := get_node_or_null("HalfHeightTick") as MeshInstance3D
	var head_tick := get_node_or_null("HeadHeightTick") as MeshInstance3D
	var label := get_node_or_null("HeightLabel") as Label3D

	if body:
		body.position.y = height * 0.5
		var capsule := body.mesh as CapsuleMesh
		if capsule:
			capsule.height = height
			capsule.radius = body_radius

	if ruler:
		ruler.position.y = height * 0.5
		var ruler_box := ruler.mesh as BoxMesh
		if ruler_box:
			ruler_box.size.y = height

	if foot_tick:
		foot_tick.position.y = 0.0
	if half_tick:
		half_tick.position.y = height * 0.5
	if head_tick:
		head_tick.position.y = height
	if label:
		label.position.y = height + 0.38
		label.text = get_label(reference_kind)
