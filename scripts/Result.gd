extends Control

signal back_to_hub
signal continue_run


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	var result := GameState.last_result
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 32
	root.offset_top = 28
	root.offset_right = -32
	root.offset_bottom = -28
	root.add_theme_constant_override("separation", 12)
	add_child(root)

	var title := Label.new()
	title.text = "探索結算"
	root.add_child(title)

	var summary := Label.new()
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.text = "結束原因：%s\n探索時間：%s\n進入危險期：%s\n取得資源：%d\n取得礦點：%d\n共鳴提升：%.1f%%\n世界復原提升：%.1f%%\n永久共鳴：%.1f%%\n世界復原：%.1f%%" % [
		result.get("reason", "未知"),
		_format_time(result.get("elapsed", 0.0)),
		"是" if result.get("entered_danger", false) else "否",
		result.get("resources", 0),
		result.get("mine_points", result.get("mine_events", 0) * 5),
		result.get("resonance_gained", 0.0),
		result.get("restoration_gained", 0.0),
		GameState.blue_resonance,
		GameState.blue_restoration
	]
	root.add_child(summary)

	var event_label := Label.new()
	event_label.text = "事件：資源 %d / 礦點 %d / 怪物 %d / 記憶 %d / 迴避 %d / 技能 %d" % [
		result.get("resource_events", 0),
		result.get("mine_events", 0),
		result.get("monster_events", 0),
		result.get("memory_events", 0),
		result.get("skipped_events", 0),
		result.get("skill_uses", 0)
	]
	root.add_child(event_label)

	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "觀察重點：是否想調整模組再進一次？迴避是否能讓玩家感覺自己主動閃過了不想接觸的事件？"
	root.add_child(hint)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	root.add_child(row)

	if result.get("reason", "") == "提前撤退":
		var continue_button := Button.new()
		continue_button.text = "繼續探索"
		continue_button.pressed.connect(func(): continue_run.emit())
		row.add_child(continue_button)

	var hub := Button.new()
	hub.text = "回據點調整"
	hub.pressed.connect(func(): back_to_hub.emit())
	row.add_child(hub)

	_apply_font_size(root)


func _format_time(value: float) -> String:
	var total := int(value)
	return "%02d:%02d" % [total / 60, total % 60]


func _apply_font_size(node: Node) -> void:
	if node is Control:
		node.add_theme_font_size_override("font_size", 25)
	for child in node.get_children():
		_apply_font_size(child)
