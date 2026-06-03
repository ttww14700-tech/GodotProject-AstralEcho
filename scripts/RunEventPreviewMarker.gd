class_name RunEventPreviewMarker
extends Control

enum MarkerShape {
	SQUARE,
	CIRCLE,
	DIAMOND
}

@export var event_type := "resource"
@export var marker_shape: MarkerShape = MarkerShape.CIRCLE
@export var default_color := Color.WHITE
@export var use_event_color := true
@export var size_multiplier := 1.0
@export var giant_size_multiplier := 1.15
@export var min_marker_size := 1.0

var marker_color := Color.WHITE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker_color = default_color
	queue_redraw()


func configure_from_event(event: Dictionary, layer_marker_size: float) -> void:
	event_type = String(event.get("type", event_type))
	marker_color = _resolve_color(event)

	var resolved_size := layer_marker_size
	if resolved_size <= 0.0:
		resolved_size = size.x if size.x > 0.0 else custom_minimum_size.x
	if resolved_size <= 0.0:
		resolved_size = 24.0

	resolved_size *= size_multiplier
	if bool(event.get("is_giant", false)):
		resolved_size *= giant_size_multiplier
	resolved_size = maxf(resolved_size, min_marker_size)

	custom_minimum_size = Vector2(resolved_size, resolved_size)
	size = Vector2(resolved_size, resolved_size)
	pivot_offset = size * 0.5
	queue_redraw()


func _resolve_color(event: Dictionary) -> Color:
	if use_event_color:
		var event_color = event.get("color", default_color)
		if event_color is Color:
			return event_color
	return default_color


func _draw() -> void:
	match marker_shape:
		MarkerShape.SQUARE:
			draw_rect(Rect2(Vector2.ZERO, size), marker_color)
		MarkerShape.DIAMOND:
			var center := size * 0.5
			var points := PackedVector2Array([
				Vector2(center.x, 0.0),
				Vector2(size.x, center.y),
				Vector2(center.x, size.y),
				Vector2(0.0, center.y)
			])
			draw_colored_polygon(points, marker_color)
		_:
			draw_circle(size * 0.5, minf(size.x, size.y) * 0.5, marker_color)
