class_name RunEventPreviewLayer
extends CanvasLayer

const RUN_EVENT_PREVIEW_MARKER_SCRIPT := preload("res://scripts/RunEventPreviewMarker.gd")

@export var enabled := true
@export var far_screen_y := 0.22
@export var near_screen_y := 0.42
@export var center_x := 0.50
@export var lane_screen_spacing := 0.12
@export var marker_size := 24.0
@export var position_lerp_speed := 3.0
@export var hide_progress := 0.12
@export var fade_progress := 0.08

@export_group("Marker Components")
@export var monster_marker_scene: PackedScene
@export var resource_marker_scene: PackedScene
@export var mine_marker_scene: PackedScene
@export var memory_marker_scene: PackedScene
@export var default_marker_scene: PackedScene

var preview_nodes := {}
var root: Control


func _ready() -> void:
	layer = 5
	_ensure_root()


func sync_preview_events(events: Array[Dictionary], delta: float) -> void:
	if not enabled:
		_clear_previews()
		return

	_ensure_root()
	var visible_ids := {}
	for event in events:
		if not _should_preview_event(event):
			continue

		var preview_id := int(event.get("id", 0))
		visible_ids[preview_id] = true
		var marker: Control = _get_or_create_marker(preview_id, event)
		_update_marker(marker, event, delta)

	_remove_hidden_previews(visible_ids)


func _ensure_root() -> void:
	if is_instance_valid(root):
		return
	root = get_node_or_null("EventPreviewUIRoot") as Control
	if is_instance_valid(root):
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.set_anchors_preset(Control.PRESET_FULL_RECT)
		return
	root = Control.new()
	root.name = "EventPreviewUIRoot"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)


func _should_preview_event(event: Dictionary) -> bool:
	if int(event.get("id", 0)) <= 0:
		return false
	if String(event.get("handoff_state", "queued")) != "queued":
		return false
	var max_preview_angle := float(event.get("max_preview_angle", 0.0))
	if max_preview_angle <= 0.0:
		return false
	var preview_angle_remaining := float(event.get("preview_angle_remaining", 0.0))
	var raw_progress := clampf(preview_angle_remaining / max_preview_angle, 0.0, 1.0)
	return raw_progress > hide_progress


func _get_or_create_marker(preview_id: int, event: Dictionary) -> Control:
	if preview_nodes.has(preview_id):
		var existing := preview_nodes[preview_id] as Control
		if is_instance_valid(existing):
			_apply_marker_style(existing, event)
			return existing

	var marker: Control = _instantiate_marker(event)
	marker.name = "EventPreview_%d" % preview_id
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(marker)
	preview_nodes[preview_id] = marker
	_apply_marker_style(marker, event)
	return marker


func _instantiate_marker(event: Dictionary) -> Control:
	var marker_scene := _marker_scene_for_type(String(event.get("type", "")))
	if marker_scene:
		var instanced_marker := marker_scene.instantiate() as Control
		if instanced_marker:
			return instanced_marker

	return RUN_EVENT_PREVIEW_MARKER_SCRIPT.new()


func _marker_scene_for_type(event_type: String) -> PackedScene:
	match event_type:
		"monster":
			if monster_marker_scene:
				return monster_marker_scene
		"resource":
			if resource_marker_scene:
				return resource_marker_scene
		"mine":
			if mine_marker_scene:
				return mine_marker_scene
		"memory":
			if memory_marker_scene:
				return memory_marker_scene
	if default_marker_scene:
		return default_marker_scene
	return null


func _apply_marker_style(marker: Control, event: Dictionary) -> void:
	if marker.has_method("configure_from_event"):
		marker.configure_from_event(event, marker_size)
		return
	marker.custom_minimum_size = Vector2(marker_size, marker_size)
	marker.size = Vector2(marker_size, marker_size)


func _update_marker(marker: Control, event: Dictionary, delta: float) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var max_preview_angle := maxf(float(event.get("max_preview_angle", 0.001)), 0.001)
	var preview_angle_remaining := clampf(float(event.get("preview_angle_remaining", 0.0)), 0.0, max_preview_angle)
	var raw_progress := clampf(preview_angle_remaining / max_preview_angle, 0.0, 1.0)
	var visible_progress := (raw_progress - hide_progress) / maxf(1.0 - hide_progress, 0.001)
	visible_progress = clampf(visible_progress, 0.0, 1.0)

	var lane := int(event.get("lane", 0))
	var screen_x := clampf(center_x + float(lane) * lane_screen_spacing, 0.0, 1.0)
	var screen_y := clampf(lerpf(near_screen_y, far_screen_y, visible_progress), 0.0, 1.0)
	var target_position: Vector2 = Vector2(screen_x * viewport_size.x, screen_y * viewport_size.y) - marker.size * 0.5

	if not marker.has_meta("preview_initialized"):
		marker.position = target_position
		marker.set_meta("preview_initialized", true)
	elif delta > 0.0:
		var alpha := 1.0 - exp(-position_lerp_speed * delta)
		alpha = clampf(alpha, 0.0, 1.0)
		marker.position = marker.position.lerp(target_position, alpha)
	else:
		marker.position = target_position

	var fade_alpha := 1.0
	if fade_progress > 0.0 and raw_progress <= hide_progress + fade_progress:
		fade_alpha = clampf((raw_progress - hide_progress) / fade_progress, 0.0, 1.0)
	marker.modulate.a = fade_alpha
	marker.visible = true


func _remove_hidden_previews(visible_ids: Dictionary) -> void:
	for preview_id in preview_nodes.keys():
		if visible_ids.has(preview_id):
			continue
		var marker := preview_nodes[preview_id] as Node
		preview_nodes.erase(preview_id)
		if is_instance_valid(marker):
			if marker is CanvasItem:
				marker.visible = false
				marker.modulate.a = 0.0
			marker.queue_free()


func _clear_previews() -> void:
	for marker in preview_nodes.values():
		if is_instance_valid(marker):
			if marker is CanvasItem:
				marker.visible = false
				marker.modulate.a = 0.0
			marker.queue_free()
	preview_nodes.clear()
