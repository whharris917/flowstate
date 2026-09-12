class_name SimLibrary
## The equipment library: what each unit operation is, what goes in and
## out of it, and the equations that relate them.
##
## The honesty rule that governs the historian governs this too: a page
## is never allowed to describe a machine that does not exist.
##
##   * Prose, equations, parameters and assumptions come from
##     SimLibraryData, which is hand-authored under the director's
##     editorial review. It is not generated from the Python specs
##     and need not match them.
##   * The PORT TABLE is not written down anywhere. It is read off a
##     real constructed component here, from the same add_input and
##     add_output calls the simulation uses, so a page cannot list a
##     nozzle the equipment does not have or miss one it does.
##   * Anything the page data cannot explain is shown as
##     undocumented rather than quietly omitted.

## Reading order for the index: process first, then the separation
## train, then the utilities that feed them, then the control tier —
## roughly the order material moves through a plant.
const TIER_ORDER: Array[String] = ["process", "separation", "utility", "control"]


## Every placeable type that has a page, grouped by tier and in build
## menu order within each tier.
static func type_ids() -> Array[String]:
	var by_tier := {}
	for tier: String in TIER_ORDER:
		by_tier[tier] = [] as Array[String]
	var extra: Array[String] = []
	for group: Array[Dictionary] in [
			PlantFactory.CATALOG, PlantFactory.CATALOG_SEPARATION,
			PlantFactory.CATALOG_INSTRUMENTS, PlantFactory.CATALOG_CONTROL,
			PlantFactory.CATALOG_UTILITIES]:
		for entry: Dictionary in group:
			var type_id := str(entry["type"])
			var tier := tier_of(type_id)
			var bucket: Array[String] = by_tier.get(tier, extra)
			if not bucket.has(type_id):
				bucket.append(type_id)
	var ids: Array[String] = []
	for tier: String in TIER_ORDER:
		ids.append_array(by_tier[tier] as Array[String])
	ids.append_array(extra)
	return ids


## What the build menu calls this configuration. Six gauges share one
## model and one page; the player still needs to tell them apart.
static func label_of(type_id: String) -> String:
	for group: Array[Dictionary] in [
			PlantFactory.CATALOG, PlantFactory.CATALOG_SEPARATION,
			PlantFactory.CATALOG_INSTRUMENTS, PlantFactory.CATALOG_CONTROL,
			PlantFactory.CATALOG_UTILITIES]:
		for entry: Dictionary in group:
			if str(entry["type"]) == type_id:
				return str(entry["label"])
	return title_of(type_id)


static func title_of(type_id: String) -> String:
	var page: Dictionary = SimLibraryData.PAGES.get(type_id, {})
	return str(page.get("title", type_id.capitalize()))


static func tier_of(type_id: String) -> String:
	var page: Dictionary = SimLibraryData.PAGES.get(type_id, {})
	return str(page.get("tier", "undocumented"))


## Build a throwaway record of this type so its real ports can be read.
## Constructing one is also a standing check that every documented
## machine can still be built.
static func _sample(type_id: String) -> SimComponent:
	if not has_record(type_id):
		return null
	var scratch := Simulation.new(0.05)
	return PlantFactory.make_record(scratch, type_id, "sample", {})


## Some placeable things are enclosures rather than simulated records:
## a cabinet holds modules, and the modules are what tick. Their page
## declares no ports, which is the signal that there is nothing to
## construct and nothing to introspect.
static func has_record(type_id: String) -> bool:
	var page: Dictionary = SimLibraryData.PAGES.get(type_id, {})
	return not (page.get("ports", {}) as Dictionary).is_empty()


## The real I/O of a real component, merged with the authored meaning
## of each port. Returns rows of {name, direction, kind_label, meaning}.
static func port_rows(type_id: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var record := _sample(type_id)
	if record == null:
		return rows
	var page: Dictionary = SimLibraryData.PAGES.get(type_id, {})
	var meanings: Dictionary = page.get("ports", {})
	for direction: String in ["in", "out"]:
		var ports: Dictionary = record.inputs if direction == "in" else record.outputs
		for port_name: String in ports:
			var port: SimPort = ports[port_name]
			rows.append({
				"name": port_name,
				"direction": direction,
				"kind_label": SimTypes.kind_label(port.kind),
				"spec": port.spec,
				"meaning": _meaning(meanings, port_name),
			})
	return rows


## A numbered port beyond what the page spelled out — a feeder's
## way 17 — takes the first way's meaning with its own number.
static func _meaning(meanings: Dictionary, port_name: String) -> String:
	if meanings.has(port_name):
		return str(meanings[port_name])
	var numbered := RegEx.create_from_string("^([a-z_]+?)(\\d+)$")
	var hit := numbered.search(port_name)
	if hit != null and meanings.has(hit.get_string(1) + "1"):
		return str(meanings[hit.get_string(1) + "1"]).replace(" 1:", " %s:" % hit.get_string(2))
	return ""


## Historian tags this equipment contributes beyond its ports — the
## wear counters and totals a trend page can pull up.
static func observable_names(type_id: String) -> Array[String]:
	var names: Array[String] = []
	var record := _sample(type_id)
	if record == null:
		return names
	for obs_name: String in record.observables:
		names.append(obs_name)
	names.sort()
	return names


static func summary_of(type_id: String) -> String:
	var page: Dictionary = SimLibraryData.PAGES.get(type_id, {})
	return str(page.get("summary", "No page has been written for this "
		+ "equipment yet. Its ports below are read from the real record, "
		+ "so they are accurate even though the description is missing."))


## [[formula, meaning], ...]
static func equations_of(type_id: String) -> Array:
	var page: Dictionary = SimLibraryData.PAGES.get(type_id, {})
	return page.get("equations", [])


## [[name, units, default, meaning], ...]
static func params_of(type_id: String) -> Array:
	var page: Dictionary = SimLibraryData.PAGES.get(type_id, {})
	return page.get("params", [])


static func assumptions_of(type_id: String) -> Array:
	var page: Dictionary = SimLibraryData.PAGES.get(type_id, {})
	return page.get("assumptions", [])


## The species table, for the page that explains what the plant handles.
static func species_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for i in SimSpecies.COUNT:
		rows.append({
			"label": SimSpecies.label_of(i),
			"cp": SimSpecies.cp_of(i),
			"boil_c": SimSpecies.boil_of(i),
			"sol_20": SimSpecies.SOL_G_PER_L_20[i],
			"sol_slope": SimSpecies.SOL_SLOPE_G_PER_L_K[i],
		})
	return rows
