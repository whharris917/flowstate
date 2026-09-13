class_name SimHistorian
## Process historian: every tag, every scan. The single source of truth
## for anything displayed to a human.
##
## Tags may be registered mid-run (the player just installed the
## instrument) and retired (it was removed — history kept, growth
## stopped). A tag's series aligns with the shared time axis via its
## start index.
##
## Each tag's samples live in a Series object of their own (2026-09-13):
## a packed array fetched out of a dictionary is a copy, so appending
## to it and writing it back copied the whole series every scan, for
## every tag — 700 copies a tick, each growing with the session, and
## the tick grew with them until frames carrying it stuttered. Inside
## its own object the array is appended in place.

class Series extends RefCounted:
	var values: PackedFloat64Array = PackedFloat64Array()

	func push(value: float) -> void:
		values.append(value)

	func cut(count: int) -> void:
		values = values.slice(count)


var time: PackedFloat64Array = PackedFloat64Array()
var data: Dictionary = {}       # String -> Series
var _starts: Dictionary = {}    # String -> int
var _readers: Dictionary = {}   # String -> Callable () -> float

## One sample a second of sim time (director, 2026-09-13: "the
## historian need only sample tags once per second"; it sampled every
## 50 ms scan before, and its 970 reads were a third of the scan). A
## real plant historian records slower still. The first scan samples,
## then every second.
var sample_interval_s: float = 1.0
var _next_sample_t: float = -INF

## Oldest samples are trimmed beyond this (2 h at one a second).
var max_samples: int = 7200
const _TRIM_CHUNK := 600


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
	data[tag] = Series.new()


func retire(tag: String) -> void:
	if not _readers.has(tag):
		push_error("tag '%s' is not active" % tag)
		return
	_readers.erase(tag)


func start_index(tag: String) -> int:
	return int(_starts.get(tag, 0))


func sample(t: float) -> void:
	if t < _next_sample_t:
		return
	_next_sample_t = (t if _next_sample_t == -INF else _next_sample_t) + sample_interval_s
	time.append(t)
	for tag: String in _readers:
		(data[tag] as Series).push(float((_readers[tag] as Callable).call()))
	if time.size() > max_samples + _TRIM_CHUNK:
		var drop := time.size() - max_samples
		time = time.slice(drop)
		for tag: String in data:
			var start := int(_starts[tag])
			var series_obj := data[tag] as Series
			var cut := clampi(drop - start, 0, series_obj.values.size())
			if cut > 0:
				series_obj.cut(cut)
			_starts[tag] = maxi(0, start - drop)


## The tag's samples. A shared buffer, not a copy, until someone
## writes to their reference.
func series(tag: String) -> PackedFloat64Array:
	if not data.has(tag):
		return PackedFloat64Array()
	return (data[tag] as Series).values


## Value at a global sample index, or NAN where the tag did not exist.
func value_at(tag: String, index: int) -> float:
	var local := index - start_index(tag)
	if not data.has(tag):
		return NAN
	var values: PackedFloat64Array = (data[tag] as Series).values
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
