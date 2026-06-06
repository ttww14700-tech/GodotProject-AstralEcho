extends Node

const SAVE_PATH := "user://astral_echo_save.json"

const MODULES := {
	"gather": {
		"name": "採集型",
		"description": "提高資源點與礦點傾向，適合穩定累積素材。",
		"weights": {"resource": 1.55, "mine": 1.74, "monster": 1.2, "memory": 0.95}
	},
	"combat": {
		"name": "戰鬥型",
		"description": "提高怪物與危險事件傾向，適合測試戰鬥收益。",
		"weights": {"resource": 0.9, "mine": 0.9, "monster": 2.2, "memory": 0.95}
	},
	"explore": {
		"name": "探索型",
		"description": "提高記憶碎片與線索傾向，適合推進世界復原。",
		"weights": {"resource": 1.0, "mine": 0.9, "monster": 1.15, "memory": 1.7}
	},
	"danger": {
		"name": "危險期型",
		"description": "提高後段高風險收益，適合撐進低濃度階段。",
		"weights": {"resource": 0.9, "mine": 1.0, "monster": 1.8, "memory": 1.2}
	}
}

var selected_module := "gather"
var blue_concentration := 100.0
var blue_resonance := 0.0
var blue_restoration := 0.0
var blue_mine_points := 0
var blue_resources := 0
var total_runs := 0
var play_history: Array = []
var last_result := {}
var resume_run_data := {}
var last_result_settled := true


func _ready() -> void:
	load_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		save_game()


func get_selected_module_data() -> Dictionary:
	return MODULES.get(selected_module, MODULES["gather"])


func get_generation_expectation() -> Dictionary:
	var weights: Dictionary = get_selected_module_data()["weights"]
	return {
		"資源": _tier(weights.get("resource", 1.0)),
		"礦點": _tier(weights.get("mine", 1.0)),
		"怪物": _tier(weights.get("monster", 1.0)),
		"記憶": _tier(weights.get("memory", 1.0)),
		"危險": "高" if selected_module == "danger" else "中"
	}


func set_last_result(result: Dictionary, settled: bool) -> void:
	last_result = result
	last_result_settled = settled


func update_blue_concentration_from_result(result: Dictionary) -> void:
	blue_concentration = clampf(result.get("concentration", blue_concentration), 0.0, 100.0)
	save_game()


func apply_run_result(result: Dictionary) -> void:
	total_runs += 1
	blue_concentration = clampf(result.get("concentration", blue_concentration), 0.0, 100.0)
	blue_resonance = clampf(blue_resonance + result.get("resonance_gained", 0.0), 0.0, 100.0)
	blue_restoration = clampf(blue_restoration + result.get("restoration_gained", 0.0), 0.0, 100.0)
	blue_mine_points += int(result.get("mine_points", result.get("mine_events", 0) * 5))
	blue_resources += int(result.get("resources", 0))
	play_history.append({
		"run_index": total_runs,
		"settled_at_unix": Time.get_unix_time_from_system(),
		"result": result.duplicate(true)
	})
	last_result_settled = true
	save_game()


func settle_last_result() -> void:
	if last_result.is_empty() or last_result_settled:
		return
	apply_run_result(last_result)


func prepare_resume_from_last_result() -> void:
	resume_run_data = last_result.duplicate(true)
	last_result = {}
	last_result_settled = true


func consume_resume_run_data() -> Dictionary:
	var data := resume_run_data.duplicate(true)
	resume_run_data = {}
	return data


func reset_progress() -> void:
	selected_module = "gather"
	blue_concentration = 100.0
	blue_resonance = 0.0
	blue_restoration = 0.0
	blue_mine_points = 0
	blue_resources = 0
	total_runs = 0
	play_history = []
	last_result = {}
	resume_run_data = {}
	last_result_settled = true
	save_game()


func can_restore_blue_gem() -> bool:
	return blue_concentration < 80.0 and blue_mine_points >= 10


func restore_blue_gem() -> bool:
	if not can_restore_blue_gem():
		return false
	blue_mine_points -= 10
	blue_concentration = minf(blue_concentration + 20.0, 100.0)
	save_game()
	return true


func save_game() -> void:
	var save_data := {
		"selected_module": selected_module,
		"blue_concentration": blue_concentration,
		"blue_resonance": blue_resonance,
		"blue_restoration": blue_restoration,
		"blue_mine_points": blue_mine_points,
		"blue_resources": blue_resources,
		"total_runs": total_runs,
		"play_history": play_history,
		"last_result": last_result,
		"resume_run_data": resume_run_data,
		"last_result_settled": last_result_settled
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("無法寫入存檔：%s" % FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(save_data, "\t"))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("無法讀取存檔：%s" % FileAccess.get_open_error())
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_warning("存檔格式無效，已忽略。")
		return
	selected_module = parsed.get("selected_module", selected_module)
	blue_concentration = clampf(float(parsed.get("blue_concentration", blue_concentration)), 0.0, 100.0)
	blue_resonance = float(parsed.get("blue_resonance", blue_resonance))
	blue_restoration = float(parsed.get("blue_restoration", blue_restoration))
	blue_mine_points = int(parsed.get("blue_mine_points", blue_mine_points))
	blue_resources = int(parsed.get("blue_resources", blue_resources))
	total_runs = int(parsed.get("total_runs", total_runs))
	play_history = parsed.get("play_history", play_history)
	last_result = parsed.get("last_result", last_result)
	resume_run_data = parsed.get("resume_run_data", resume_run_data)
	last_result_settled = bool(parsed.get("last_result_settled", last_result_settled))


func _tier(value: float) -> String:
	if value >= 1.35:
		return "高"
	if value <= 0.92:
		return "低"
	return "中"
