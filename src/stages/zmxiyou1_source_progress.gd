class_name Zmxiyou1SourceProgress
extends Resource

## Small persistence boundary for source-era global rewards. A save system can
## serialize this Resource without coupling enemy code to storage or UI.

signal merit_changed(value: int)

const M24_DAILY_LIMIT := 1
const M24_MERIT_REWARD := 50

@export var merit := 0
@export var m24_reward_date := ""
@export var m24_reward_times := 0


func grant_m24_daily_reward(date_key := "") -> int:
	var current_date := date_key
	if current_date.is_empty():
		current_date = Time.get_date_string_from_system()
	if m24_reward_date != current_date:
		m24_reward_date = current_date
		m24_reward_times = 0
	if m24_reward_times >= M24_DAILY_LIMIT:
		return 0
	merit += M24_MERIT_REWARD
	m24_reward_times += 1
	merit_changed.emit(merit)
	return M24_MERIT_REWARD
