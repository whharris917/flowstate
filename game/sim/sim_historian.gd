class_name SimHistorian
## Process historian: every tag, every scan. The single source of truth
## for anything displayed to a human.
##
## Tags may be registered mid-run (the player just installed the
## instrument) and retired (it was removed — history kept, growth
## stopped). A tag's series aligns with the shared time axis via its
## start index.

var time: PackedFloat64Array = PackedFloat64Array()
var data: Dictionary = {}       # String -> PackedFloat64Array
var _starts: Dictionary = {}    # String -> int
var _readers: Dictionary = {}   # String -> Callable () -> float

## Oldest samples are trimmed beyond this (~1 h at 20 Hz).
var max_samples: int = 72000
const _TRIM_CHUNK := 2000


func tags() -> Array:
	return data.keys()


func active_tags() -> Array:
	return _readers.keys()


func sample_count() -> int:
	return time.size()


func register(tag: String, read: Callable) -> void:
	if _readers.has(tag):
		push_error("duplicate tag '%s'" % tag)
		return
	if data.has(tag):
		# A retired tag coming back: equipment removed and a new record
		# placed under the same name (X then B, 2026-09-05). The old
		# record's series goes with it; this is a new series from now.
		data.erase(tag)
		_starts.erase(tag)
	_readers[tag] = read
	_starts[tag] = time.size()
	data[tag] = PackedFloat64Array()


func retire(tag: String) -> void:
	if not _readers.has(tag):
		push_error("tag '%s' is not active" % tag)
		return
	_readers.erase(tag)


func start_index(tag: String) -> int:
	return int(_starts.get(tag, 0))


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
			var start := int(_starts[tag])
			var cut := clampi(drop - start, 0, (data[tag] as PackedFloat64Array).size())
			if cut > 0:
				data[tag] = (data[tag] as PackedFloat64Array).slice(cut)
			_starts[tag] = maxi(0, start - drop)


func series(tag: String) -> PackedFloat64Array:
	return data.get(tag, PackedFloat64Array())


## Value at a global sample index, or NAN where the tag did not exist.
func value_at(tag: String, index: int) -> float:
	var local := index - start_index(tag)
	var values: PackedFloat64Array = data.get(tag, PackedFloat64Array())
	if local >= 0 and local < values.size():
		return values[local]
	return NAN


func to_csv_text() -> String:
	var tag_list := tags()
	var lines: Array[String] = ["time_s," + ",".join(tag_list)]
	for i in time.size():
		var row: Array[String] = ["%.6f" % time[i]]
		for tag: String in tag_list:
			var value := value_at(tag, i)
			row.append("" if is_nan(value) else "%.6f" % value)
		lines.append(",".join(row))
	return "\n".join(lines) + "\n"
