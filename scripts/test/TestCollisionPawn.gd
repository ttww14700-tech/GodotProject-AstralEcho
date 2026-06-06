extends CharacterBody3D

const MOVE_SPEED := 4.0


func _physics_process(_delta: float) -> void:
	var input_vector := Vector2.ZERO

	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_vector.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_vector.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_vector.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_vector.y += 1.0

	if input_vector.length() > 1.0:
		input_vector = input_vector.normalized()

	velocity = Vector3(input_vector.x, 0.0, input_vector.y) * MOVE_SPEED
	move_and_slide()
