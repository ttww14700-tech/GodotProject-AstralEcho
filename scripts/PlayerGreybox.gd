extends CharacterBody3D

@export var greybox_albedo := Color(0.72, 0.74, 0.76, 1.0)
@export var greybox_roughness := 0.72

var _greybox_material: StandardMaterial3D


func _ready() -> void:
	_apply_greybox_material()


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
