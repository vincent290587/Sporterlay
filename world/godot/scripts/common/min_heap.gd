class_name MinHeap
extends RefCounted
## Binary min-heap of (key, int value), for priority flood and A*.

var keys := PackedFloat32Array()
var vals := PackedInt32Array()


func is_empty() -> bool:
	return vals.is_empty()


func push(key: float, val: int) -> void:
	keys.append(key)
	vals.append(val)
	var i := vals.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if keys[p] <= key:
			break
		keys[i] = keys[p]
		vals[i] = vals[p]
		i = p
	keys[i] = key
	vals[i] = val


func top_key() -> float:
	return keys[0]


## Removes and returns the value with the smallest key.
func pop() -> int:
	var out := vals[0]
	var last := vals.size() - 1
	var key := keys[last]
	var val := vals[last]
	keys.resize(last)
	vals.resize(last)
	if last == 0:
		return out
	var i := 0
	while true:
		var c := i * 2 + 1
		if c >= last:
			break
		if c + 1 < last and keys[c + 1] < keys[c]:
			c += 1
		if keys[c] >= key:
			break
		keys[i] = keys[c]
		vals[i] = vals[c]
		i = c
	keys[i] = key
	vals[i] = val
	return out
