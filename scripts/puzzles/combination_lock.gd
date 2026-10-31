class_name CombinationLock
extends RefCounted
## Rules for a dial combination lock: each dial shows 0-9 and wraps around.
## Pure logic with no UI, so it can be tested headlessly.

signal changed

var code: Array[int] = []
var digits: Array[int] = []
var attempts: int = 0


func _init(lock_code: Array[int] = [0, 0, 0]) -> void:
	code = lock_code.duplicate()
	digits.resize(code.size())
	digits.fill(0)


func dial_count() -> int:
	return code.size()


## Turn one dial by `steps` (negative turns it down). Wraps 9 -> 0 and 0 -> 9.
func rotate(index: int, steps: int) -> void:
	if index < 0 or index >= digits.size():
		return
	digits[index] = posmod(digits[index] + steps, 10)
	changed.emit()


func is_open() -> bool:
	return digits == code


## Counts an attempt and returns whether the dials match the code.
func try_open() -> bool:
	attempts += 1
	return is_open()
