class_name TrendScreenView
extends HmiScreenView
## A placeable trend screen (Tier 5, 2026-09-11): a framed screen on
## two posts showing up to four historian tags. The pens are picked in
## the right-click CONFIGURE tab; the record remembers them.

var record: SimTrendScreen
var trend: TrendScreenPanel


func setup_trend(record_: SimTrendScreen, plant: Plant) -> void:
	record = record_
	trend = TrendScreenPanel.new()
	trend.setup(record_, plant)
	setup(trend, record_.comp_name.to_upper().replace("_", "-"), Vector2i(1024, 640), 1.2, "")


func describe() -> String:
	var pens := record.pens()
	return "%s — trend screen, last %d min from the historian\n%s\nright-click → CONFIGURE picks the pens" % [
		record.comp_name, int(record.window_s / 60.0),
		", ".join(pens) if pens.size() > 0 else "no pens configured"]


func use() -> void:
	pass
