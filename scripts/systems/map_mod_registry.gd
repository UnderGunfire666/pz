class_name MapModRegistry
extends RefCounted

## Resolves only static content packages. It has no save-game ownership and
## does not instantiate maps, keeping mod discovery separate from simulation.
static func resolve_load_order(manifests: Array) -> Dictionary:
	var issues: Array[String] = []
	var by_id: Dictionary = {}
	for manifest in manifests:
		if manifest == null or manifest.id.strip_edges().is_empty():
			issues.append("Mod manifest has a missing stable ID.")
			continue
		if by_id.has(manifest.id):
			issues.append("Mod manifest ID is duplicated: %s." % manifest.id)
			continue
		if manifest.map_paths.is_empty():
			issues.append("Mod %s does not provide any map resources." % manifest.id)
		by_id[manifest.id] = manifest
	var pending: Array = []
	for manifest in manifests:
		if manifest != null and by_id.get(manifest.id) == manifest:
			var missing := false
			for dependency in manifest.dependencies:
				if not by_id.has(dependency):
					issues.append("Mod %s requires missing dependency %s." % [manifest.id, dependency])
					missing = true
			if not missing:
				pending.append(manifest)
	var ordered: Array = []
	var loaded: Dictionary = {}
	while not pending.is_empty():
		var progressed := false
		for manifest in pending.duplicate():
			var ready := true
			for dependency in manifest.dependencies:
				if not loaded.has(dependency):
					ready = false
					break
			if ready:
				ordered.append(manifest)
				loaded[manifest.id] = true
				pending.erase(manifest)
				progressed = true
		if not progressed:
			var cycle_ids: PackedStringArray = []
			for manifest in pending:
				cycle_ids.append(manifest.id)
			issues.append("Mod dependency cycle: %s." % ", ".join(cycle_ids))
			break
	return {"order": ordered, "issues": issues}
