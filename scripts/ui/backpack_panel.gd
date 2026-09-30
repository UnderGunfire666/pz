class_name BackpackPanel
extends VBoxContainer

var game: MVPGameRoot
var presentation := InventoryPresentation.new()
var trees: Array[InventoryItemTree] = []
var tab_bars: Array[VBoxContainer] = []
var sorter: Array[OptionButton] = []
var directions: Array[Button] = []
var headers: Array[Label] = []
var endpoints: Array = [[], []]
var info: Label
var last_signature := ""
var rebuilding := false
var menu: PopupMenu
var context: Dictionary = {}
var quantity_dialog: ConfirmationDialog
var quantity: SpinBox
var pending_split: Dictionary = {}
var hover_panel: PanelContainer
var hover_label: Label
var hover_key := ""
var hover_age := 0.0
var hover_data: Dictionary = {}
var hover_side := 0

func _ready() -> void:
	presentation.load_preferences()
	info = Label.new()
	add_child(info)
	var columns := HBoxContainer.new()
	add_child(columns)
	for side in range(2):
		var shell := HBoxContainer.new()
		shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		columns.add_child(shell)
		var pane := VBoxContainer.new()
		pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		shell.add_child(pane)
		var tabs := VBoxContainer.new()
		tabs.custom_minimum_size.x = 100
		tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
		shell.add_child(tabs)
		tab_bars.append(tabs)
		var sort_row := HBoxContainer.new()
		pane.add_child(sort_row)
		var sort := OptionButton.new()
		for key in InventoryPresentation.SORTS: sort.add_item(String(key).capitalize())
		sort.select(InventoryPresentation.SORTS.find(presentation.sides[side]["sort"]))
		sort.focus_mode = Control.FOCUS_NONE
		sorter.append(sort)
		sort_row.add_child(sort)
		sort.item_selected.connect(func(index: int) -> void:
			presentation.sides[side]["sort"] = InventoryPresentation.SORTS[index]
			changed())
		var direction := Button.new()
		direction.focus_mode = Control.FOCUS_NONE
		sort_row.add_child(direction)
		directions.append(direction)
		direction.pressed.connect(func() -> void:
			presentation.sides[side]["descending"] = not presentation.sides[side]["descending"]
			changed())
		var header := Label.new()
		header.custom_minimum_size = Vector2(385, 64)
		header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pane.add_child(header)
		headers.append(header)
		var tree := InventoryItemTree.new()
		tree.panel = self
		tree.side = side
		tree.columns = 4
		tree.hide_root = true
		tree.allow_rmb_select = true
		tree.column_titles_visible = true
		for index in range(4): tree.set_column_title(index, ["Item", "Qty", "kg", "cm³"][index])
		tree.set_column_expand(0, true)
		for index in range(1, 4):
			tree.set_column_expand(index, false)
			tree.set_column_custom_minimum_width(index, [0, 35, 65, 70][index])
		tree.custom_minimum_size = Vector2(300, 265)
		tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pane.add_child(tree)
		trees.append(tree)
		tree.item_activated.connect(func() -> void: default_action(side))
		tree.item_mouse_selected.connect(func(position: Vector2, button: int) -> void:
			if button == MOUSE_BUTTON_RIGHT: open_context(side, tree.global_position + position))
		tree.item_collapsed.connect(func(item: TreeItem) -> void:
			if rebuilding: return
			var data: Dictionary = item.get_metadata(0)
			if data.has("key"):
				presentation.sides[side]["expanded"][data["key"]] = not item.collapsed
				presentation.save_preferences())
		var buttons := HBoxContainer.new()
		pane.add_child(buttons)
		_button(buttons, "Transfer selected", func() -> void:
			var data := selected(side)
			if not data.is_empty(): game.interactions.request_units(data.get("transfer_ids", data["ids"]), presentation.destination(game, 1 - side)))
		_button(buttons, "Transfer all", func() -> void:
			var ids: Array = []
			for source in presentation.sources(game, side):
				for stack: ItemStack in game.inventory.contents(source):
					for unit in stack.units: ids.append(unit["uid"])
			game.interactions.request_units(ids, presentation.destination(game, 1 - side)))
	menu = PopupMenu.new()
	add_child(menu)
	menu.id_pressed.connect(_context_action)
	quantity_dialog = ConfirmationDialog.new()
	quantity_dialog.title = "Split quantity"
	quantity_dialog.ok_button_text = "Confirm"
	quantity_dialog.cancel_button_text = "Cancel"
	add_child(quantity_dialog)
	quantity = SpinBox.new()
	quantity.min_value = 1
	quantity.step = 1
	quantity.custom_minimum_size = Vector2(240, 40)
	quantity_dialog.add_child(quantity)
	quantity_dialog.confirmed.connect(_confirm_quantity)
	quantity_dialog.canceled.connect(func() -> void: pending_split = {})
	hover_panel = PanelContainer.new()
	hover_panel.set_as_top_level(true)
	hover_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hover_panel)
	hover_label = Label.new()
	hover_label.custom_minimum_size = Vector2(340, 0)
	hover_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_panel.add_child(hover_label)
	hover_panel.hide()
	visibility_changed.connect(func() -> void:
		hover_panel.hide()
		hover_key = ""
		hover_age = 0)

func _button(parent: Node, title: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)

func _select_container(side: int, id: String) -> void:
	presentation.sides[side]["selected"] = id
	changed()

func _rebuild_tabs(side: int) -> void:
	var bar := tab_bars[side]
	for child in bar.get_children():
		bar.remove_child(child)
		child.queue_free()
	for entry in endpoints[side]:
		var button := Button.new()
		var full_name: String = entry["name"]
		button.text = String(entry.get("short_name", full_name))
		button.tooltip_text = full_name
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.custom_minimum_size = Vector2(100, 30)
		button.focus_mode = Control.FOCUS_NONE
		button.disabled = entry["id"] == presentation.sides[side]["selected"]
		button.pressed.connect(_select_container.bind(side, String(entry["id"])))
		bar.add_child(button)

func changed() -> void:
	presentation.save_preferences()
	last_signature = ""
	if game != null: refresh(game)

func refresh(p_game: MVPGameRoot) -> void:
	game = p_game
	var inv := game.inventory
	info.text = "Carry %.2f kg · penalty %.1f · hard %.1f · warmth %.1f | Tab close · double-click / right-click" % [inv.current_weight(), inv.penalty_limit, inv.absolute_limit, game.player_state.clothing.total_warmth()]
	info.modulate = Color(1, 0.35, 0.3) if inv.current_weight() >= inv.absolute_limit * 0.9 else (Color(1, 0.75, 0.3) if inv.current_weight() > inv.penalty_limit else Color.WHITE)
	var signature := str(inv.revision) + str(inv.use_context)
	for side in range(2):
		endpoints[side] = presentation.containers(game, side)
		signature += str(endpoints[side]) + str(presentation.sides[side])
	if signature == last_signature: return
	last_signature = signature
	rebuilding = true
	for side in range(2): _rebuild(side)
	rebuilding = false

func _rebuild(side: int) -> void:
	_rebuild_tabs(side)
	directions[side].text = "Descending ↓" if presentation.sides[side]["descending"] else "Ascending ↑"
	var tree := trees[side]
	tree.clear()
	var root := tree.create_item()
	var groups := presentation.groups(game, side)
	var volume := 0.0
	for group in groups:
		volume += group["volume"]
		var row := tree.create_item(root)
		row.set_text(0, group["name"])
		row.set_text(1, str(group["ids"].size()))
		row.set_text(2, "%.3f" % group["weight"])
		row.set_text(3, "%.1f" % group["volume"])
		if group["ids"].size() == 1:
			var entry: Dictionary = group["entries"][0]
			var single_data: Dictionary = group.duplicate(true)
			single_data["individual"] = true
			single_data["source"] = entry["source"]
			row.set_metadata(0, single_data)
			continue
		row.set_metadata(0, group)
		row.collapsed = not presentation.sides[side]["expanded"].get(group["key"], false)
		for entry: Dictionary in group["entries"]:
			var detail := tree.create_item(row)
			var found := game.inventory.find_unit(entry["uid"])
			var unit: Dictionary = found["unit"]
			var flavor := String(unit["flavor"])
			detail.set_text(0, "%s [%s] · %s · %s" % [
				flavor if not flavor.is_empty() else entry["name"], String(entry["uid"]).left(6),
				InventoryPresentation.acquisition_label(unit), source_name(entry["source"])])
			detail.set_text(1, "1")
			detail.set_text(2, "%.3f" % entry["weight"])
			detail.set_text(3, "%.1f" % entry["volume"])
			detail.set_metadata(0, {"ids": [entry["uid"]], "source": entry["source"], "individual": true})
	var destination := presentation.destination(game, side)
	headers[side].text = "Used %.1f cm³ · capacity unlimited" % volume
	if presentation.sides[side]["selected"] == "worn_clothing":
		headers[side].text = "Worn clothing · %d item(s)" % groups.reduce(
			func(total: int, group: Dictionary) -> int: return total + group["ids"].size(), 0)
	elif game.inventory.world.has(destination):
		var cap: float = game.inventory.world[destination].capacity
		headers[side].text = "%.1f / %s cm³" % [volume, "%.0f" % cap if is_finite(cap) else "unlimited"]
	else:
		var found := game.inventory.find_unit(destination)
		if not found.is_empty():
			headers[side].text = "%.1f / %.1f cm³ · reduction %d%% · durability %d" % [volume, found["stack"].definition.capacity(),
				found["stack"].definition.weight_reduction * 100, found["unit"]["durability"]]
	if destination in InventoryGrid.CLOTHING_SLOTS:
		headers[side].text = "Empty clothing slot" if game.inventory.contents(destination).is_empty() else clothing_summary(game.inventory.contents(destination)[0])

func selected(side: int) -> Dictionary:
	var row := trees[side].get_selected()
	return row.get_metadata(0) if row != null else {}

func default_action(side: int) -> void:
	var data := selected(side)
	if data.is_empty(): return
	var uid: String = data["ids"][0]
	var found := game.inventory.find_unit(uid)
	if found.is_empty(): return
	var tags: Array = found["stack"].definition.tags
	if "food" in tags or "water" in tags: game.interactions.request_use(uid)
	elif "backpack" in tags:
		if found["owner"] == "equipment": game.interactions.request_unequip()
		else: game.interactions.request_equip(uid)
	elif "clothing" in tags: game.interactions.request_wear(uid) if found["owner"] not in InventoryGrid.CLOTHING_SLOTS else game.interactions.request_remove_clothing(found["owner"])
	elif "weapon" in tags: game.interactions.request_pickup(uid)

func open_context(side: int, position: Vector2) -> void:
	var data := selected(side)
	if data.is_empty(): return
	context = {"side": side, "data": data}
	var uid: String = data["ids"][0]
	var found := game.inventory.find_unit(uid)
	if found.is_empty(): return
	var tags: Array = found["stack"].definition.tags
	menu.clear()
	var free_reason := "" if game.inventory.has_free_hand() else "requires an empty hand"
	_menu_entry(0, "Use / resume", "" if ("food" in tags or "water" in tags) else "not usable")
	_menu_entry(1, "Pick up", "" if not found["owner"] in InventoryGrid.HANDS else "already held")
	_menu_entry(2, "Equip backpack", free_reason if "backpack" in tags and found["unit"]["durability"] > 0 else "requires an undamaged backpack")
	_menu_entry(3, "Unequip backpack", free_reason if found["owner"] == "equipment" else "not equipped")
	_menu_entry(4, "Transfer", game.interactions.operation_reason(uid, presentation.destination(game, 1 - side)))
	_menu_entry(5, "Drop at feet", game.interactions.operation_reason(uid, "ground", not found["owner"] in InventoryGrid.HANDS))
	_menu_entry(6, "Split stack", "" if data["ids"].size() > 1 else "only one item")
	_menu_entry(7, "Open container", "" if found["stack"].definition.capacity() > 0 and game.inventory.carried(uid) else "not a carried container")
	_menu_entry(10, "Wear", "" if "clothing" in tags and found["owner"] not in InventoryGrid.CLOTHING_SLOTS else "not unworn clothing")
	_menu_entry(11, "Remove clothing", "" if found["owner"] in InventoryGrid.CLOTHING_SLOTS else "not currently worn")
	_menu_entry(12, "Switch %s" % ("off" if found["unit"].get("switched_on", false) else "on"),
		"" if found["stack"].definition.switchable and found["owner"] in InventoryGrid.HANDS else "switchable equipment must be held")
	context["repair_regions"] = found["stack"].definition.clothing_regions.duplicate()
	for index in range(context["repair_regions"].size()):
		var region: String = context["repair_regions"][index]
		_menu_entry(100 + index, "Repair %s" % region, game.interactions.repair_reason(uid, region))
	menu.position = Vector2i(position)
	menu.popup()

func _menu_entry(id: int, title: String, reason: String) -> void:
	menu.add_item(title if reason.is_empty() else "%s — %s" % [title, reason], id)
	menu.set_item_disabled(menu.item_count - 1, not reason.is_empty())

func _context_action(id: int) -> void:
	if context.is_empty(): return
	var data: Dictionary = context["data"]
	var side: int = context["side"]
	var uid: String = data["ids"][0]
	match id:
		0: game.interactions.request_use(uid)
		1: game.interactions.request_pickup(uid)
		2: game.interactions.request_equip(uid)
		3: game.interactions.request_unequip()
		4: game.interactions.request_units(data.get("transfer_ids", data["ids"]), presentation.destination(game, 1 - side))
		5: game.interactions.request_units(data.get("transfer_ids", data["ids"]), "ground", false)
		6: ask_quantity(data["ids"], side, "")
		7:
			presentation.sides[0]["selected"] = presentation.container_tab_for(game, uid)
			changed()
		10: game.interactions.request_wear(uid)
		11:
			var found := game.inventory.find_unit(uid)
			if not found.is_empty(): game.interactions.request_remove_clothing(found["owner"])
		12:
			if game.inventory.toggle_switchable(uid): game.show_notification("Equipment switched.")
		_: 
			if id >= 100 and id - 100 < context.get("repair_regions", []).size():
				game.interactions.request_repair(uid, context["repair_regions"][id - 100])

func accepts_drag(data: Variant) -> bool:
	if game == null or not data is Dictionary or not data.get("inventory_drag", false): return false
	if game.inventory.has_free_hand(): return true
	for uid in data.get("ids", []):
		var found := game.inventory.find_unit(uid)
		if found.is_empty() or not found["owner"] in InventoryGrid.HANDS: return false
	return true

func drop_payload(data: Dictionary, destination: String) -> void:
	var ids: Array = data.get("transfer_ids", data["ids"])
	var held_drop := destination == "ground"
	for uid in ids:
		var found := game.inventory.find_unit(uid)
		if found.is_empty() or not found["owner"] in InventoryGrid.HANDS: held_drop = false
	if data.get("split", false) and ids.size() > 1:
		ask_quantity(ids, data["side"], destination, not held_drop)
	else:
		game.interactions.request_units(ids, destination, not held_drop)

func ask_quantity(ids: Array, side: int, destination: String, require_free: bool = true) -> void:
	pending_split = {"ids": ids.duplicate(), "side": side, "destination": destination, "require_free": require_free}
	quantity.max_value = ids.size() if not destination.is_empty() else ids.size() - 1
	quantity.value = maxi(1, ids.size() / 2)
	quantity_dialog.popup_centered()
	quantity.get_line_edit().grab_focus()
	quantity.get_line_edit().select_all()

func _confirm_quantity() -> void:
	if pending_split.is_empty(): return
	var count := clampi(int(quantity.value), 1, pending_split["ids"].size())
	if String(pending_split["destination"]).is_empty():
		presentation.split(pending_split["side"], pending_split["ids"], count)
		changed()
	else: game.interactions.request_units(pending_split["ids"].slice(0, count), pending_split["destination"], pending_split.get("require_free", true))
	pending_split = {}

func source_name(id: String) -> String:
	return game.inventory.world[id].display_name if game.inventory.world.has(id) else id.capitalize()

func _process(delta: float) -> void:
	if game == null or not is_visible_in_tree(): return
	var found_data: Dictionary = {}
	var key := ""
	for side in range(2):
		var tree := trees[side]
		if not tree.get_global_rect().has_point(get_global_mouse_position()): continue
		var row := tree.get_item_at_position(tree.get_local_mouse_position())
		if row == null: continue
		found_data = row.get_metadata(0)
		hover_side = side
		key = str(side) + str(found_data.get("ids", [])) + str(found_data.get("individual", false))
	if key != hover_key:
		hover_key = key
		hover_age = 0
		hover_panel.hide()
		hover_data = found_data
	if key.is_empty():
		hover_panel.hide()
		return
	hover_age += delta
	if hover_age < 1.0: return
	hover_label.text = tooltip_text(hover_data)
	hover_panel.reset_size()
	hover_panel.show()
	var bounds := get_viewport_rect().size
	var desired := get_global_mouse_position() + Vector2(18, 16)
	hover_panel.global_position = desired.clamp(Vector2.ZERO, (bounds - hover_panel.size - Vector2(8, 8)).max(Vector2.ZERO))

func tooltip_text(data: Dictionary) -> String:
	var ids: Array = data.get("ids", [])
	if ids.is_empty(): return ""
	if not data.get("individual", false):
		var weight := 0.0
		var volume := 0.0
		var sources := {}
		for uid in ids:
			var found := game.inventory.find_unit(uid)
			if found.is_empty(): continue
			var single := ItemStack.from_unit(found["stack"].definition, found["unit"])
			weight += game.inventory.effective_weight(single)
			volume += single.total_volume()
			var source := source_name(found["owner"])
			sources[source] = int(sources.get(source, 0)) + 1
		return "%d items · %.3f kg · %.1f cm³\nSources: %s" % [ids.size(), weight, volume, str(sources)]
	var found := game.inventory.find_unit(ids[0])
	if found.is_empty(): return ""
	var stack: ItemStack = found["stack"]
	var unit: Dictionary = found["unit"]
	var single := ItemStack.from_unit(stack.definition, unit)
	var text := "%s · %s\nID: %s\nAcquired: %s\nL × W × H: %s cm\n%s · %.3f kg · %.1f cm³\nSource: %s" % [
		stack.definition.display_name, unit["flavor"], ids[0], InventoryPresentation.acquisition_label(unit),
		stack.unit_dimensions(unit), InventoryPresentation.category(stack.definition), game.inventory.effective_weight(single),
		single.total_volume(), source_name(found["owner"])]
	if stack.definition.capacity() > 0:
		text += "\nCapacity %.1f / %.1f cm³\nContents %.3f kg · durability %d\nReduction %d%% (equipped backpack only)" % [
			single.used_volume(), stack.definition.capacity(), single.total_weight() - stack.definition.unit_weight,
			unit["durability"], stack.definition.weight_reduction * 100]
	if not stack.definition.clothing_slot.is_empty():
		text += "\n" + clothing_summary(stack)
	if stack.definition.switchable:
		text += "\nSwitch: %s" % ("ON" if unit.get("switched_on", false) else "OFF")
	if stack.definition.hunger_restore != 0.0 or stack.definition.thirst_restore != 0.0 or stack.definition.happiness_effect != 0.0:
		text += "\nEffects: hunger %+.0f · thirst %+.0f · happiness %+.0f" % [stack.definition.hunger_restore,
			stack.definition.thirst_restore, stack.definition.happiness_effect]
	if not stack.definition.medical_action.is_empty(): text += "\nTreatment: %s" % stack.definition.medical_action.capitalize().replace("_", " ")
	if not stack.definition.weapon_attack_type.is_empty():
		text += "\nAttack: %s · damage %d" % [stack.definition.weapon_attack_type, stack.definition.weapon_damage]
	return text

func clothing_summary(stack: ItemStack) -> String:
	if stack == null or stack.definition.clothing_slot.is_empty(): return ""
	var unit: Dictionary = stack.units[0]
	var lines: Array[String] = ["Worn slot: %s" % stack.definition.clothing_slot.capitalize()]
	for region in stack.definition.clothing_regions:
		lines.append("%s · protection %.0f%% · warmth %.1f · durability %.1f/%.1f" % [region,
			float(stack.definition.clothing_protection.get(region, 0)), float(stack.definition.clothing_warmth.get(region, 0)),
			float(unit["clothing_durability"].get(region, 0)), float(stack.definition.clothing_max_durability.get(region, 0))])
	return "\n".join(lines)
