class_name SimHistorian
## Process historian: every tag, every scan. The single source of truth
## for anything displayed to a human. Displays read historized samples
## (trends) or live sim state (faceplates); they never compute, smooth,
## or invent data.

var time: PackedFloat64Array = PackedFloat64Array()
var data: Dictionary = {}       # String -> PackedFloat64Array
var _readers: Dictionary = {}   # String -> Callable () -> float

## Oldest samples are trimmed beyond this (~1 h at 20 Hz). In-game
## trending needs a window, not eternity; the Python kernel remains the
## unbounded reference.
var max_samples: int = 72000
const _TRIM_CHUNK := 2000


func tags() -> Array:
	return _readers.keys()


func sample_count() -> int:
	return time.size()


func register(tag: String, read: Callable) -> void:
	if _readers.has(tag):
		push_error("duplicate tag '%s'" % tag)
		return
	if time.size() > 0:
		push_error("register all tags before sampling begins")
		return
	_readers[tag] = read
	data[tag] = PackedFloat64Array()


func sample(t: float) -> void:
	time.append(t)
	for tag: String in _readers:
		var series_arr: PackedFloat64Array = data[tag]
		series_arr.append(float((_readers[tag] as Callable).call()))
		data[tag] = series_arr
	if time.size() > max_samples + _TRIM_CHUNK:
		var drop := time.size() - max_samples
		time = time.slice(drop)
		for tag: String in data:
			data[tag] = (data[tag] as PackedFloat64Array).slice(drop)


func series(tag: String) -> PackedFloat64Array:
	return data.get(tag, PackedFloat64Array())


func to_csv_text() -> String:
	var tag_list := tags()
	var lines: Array[String] = ["time_s," + ",".join(tag_list)]
	for i in time.size():
		var row: Array[String] = ["%.6f" % time[i]]
		for tag: String in tag_list:
			row.append("%.6f" % (data[tag] as PackedFloat64Array)[i])
		lines.append(",".join(row))
	return "\n".join(lines) + "\n"
