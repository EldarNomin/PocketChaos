extends Control
## Short intro shown on first launch; replayable from the settings panel.

const Settings = preload("res://scripts/settings.gd")

var game: Node3D
var page := 0
var title_label: Label
var text_label: Label
var page_label: Label
var back_button: Button
var next_button: Button

const PAGES := [
	{"title": "Дворовые пенальти", "text": "Дуэль на двоих: один бьёт, второй защищает ворота. Пять раундов, каждый бьёт и защищает по разу. Гол — одно очко; при равенстве — дополнительные пары. Оба удара раунда идут на одинаковой площадке."},
	{"title": "Бьющий", "text": "Мышь — прицел. Удерживай ЛКМ — сила растёт, отпусти — удар. Q и E — подкрутка влево и вправо. ПКМ сбрасывает замах. Зелёная точка показывает прицел без учёта подкрутки и предметов."},
	{"title": "Вратарь", "text": "A и D — движение вдоль ворот. Мышь — руки рядом с телом. ЛКМ — короткая ловля с паузой на повтор. Space вместе с A или D — один рывок на попытку."},
	{"title": "Площадка", "text": "Перед раундами 2–5 каждый ставит один предмет: щит для отскока или вентилятор с боковым ветром. Свои предметы можно заменять. Предмет, поставленный против друга, действует и против тебя."},
	{"title": "Онлайн и тренировка", "text": "«Онлайн» — создать комнату или подключиться к IP друга. R — готовность и реванш. В тренировке: 1 / 2 — смена роли, R — повтор попытки, B — площадка. Esc — меню."},
]

func _ready() -> void:
	game = get_parent()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.78)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 0)
	panel.add_theme_stylebox_override("panel", game.panel_style())
	centre.add_child(panel)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	panel.add_child(stack)
	title_label = game.label("", 27)
	stack.add_child(title_label)
	text_label = game.label("", 18)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.custom_minimum_size = Vector2(580, 150)
	stack.add_child(text_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	stack.add_child(row)
	page_label = game.label("", 16)
	var page_box := VBoxContainer.new()
	page_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_box.add_child(page_label)
	page_box.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(page_box)
	back_button = game.button("Назад", step_back)
	row.add_child(back_button)
	next_button = game.button("Далее", step_next)
	row.add_child(next_button)
	hide()

func show_intro() -> void:
	page = 0
	refresh()
	show()

func close() -> void:
	hide()
	game.settings.tutorial_seen = true
	Settings.save_config(game.settings)

func step_back() -> void:
	page = maxi(0, page - 1)
	refresh()

func step_next() -> void:
	if page >= PAGES.size() - 1:
		close()
		return
	page += 1
	refresh()

func refresh() -> void:
	title_label.text = PAGES[page].title
	text_label.text = PAGES[page].text
	page_label.text = "Страница %d из %d" % [page + 1, PAGES.size()]
	back_button.disabled = page == 0
	next_button.text = "Начать" if page == PAGES.size() - 1 else "Далее"
