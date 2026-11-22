extends RefCounted
## Stage S17.1: the keyboard inside a popup or a sheet. While one is open, Tab and Shift+Tab
## go through its controls in the order it is built (top to bottom, left to right) and round
## again, never out to the board behind; opening one takes the keyboard into it (to the card
## itself, so no control wears the ring until Tab is pressed), and closing it gives the
## keyboard back to whatever had it. tests/focus_check.gd walks every popup and sheet.

const Contrast := preload("res://scripts/contrast.gd")


## True for a control the keyboard can be on now.
static func reachable(control: Control) -> bool:
	if control.focus_mode != Control.FOCUS_ALL or not control.is_visible_in_tree() or control.size.x <= 0.0:
		return false
	if control is BaseButton and (control as BaseButton).disabled:
		return false
	if control is LineEdit and not (control as LineEdit).editable:
		return false
	return true


## The controls under `root` the keyboard can reach, in the order the screen is built.
static func order(root: Node) -> Array:
	var out := []
	for child in root.get_children():
		if child is Control:
			if not (child as Control).visible:
				continue
			if reachable(child as Control):
				out.append(child)
		out.append_array(order(child))
	return out


## Moves the keyboard to the next (`by` 1) or the one before (`by` -1) under `root`, round
## from the last to the first; from outside them, to the first or the last. Returns it.
static func step(root: Control, by: int) -> Control:
	var list := order(root)
	if list.is_empty():
		return null
	var at := list.find(root.get_viewport().gui_get_focus_owner())
	var next: Control = list[posmod(at + by, list.size())] if at >= 0 else (list[0] if by > 0 else list[-1])
	next.grab_focus()
	return next


## Handles Tab and Shift+Tab for `root` (a card that is open): true when the event was one.
static func kept_inside(root: Control, event: InputEvent) -> bool:
	var by := 0
	if event.is_action_pressed("ui_focus_prev", true):  # Shift+Tab also matches "next": asked first
		by = -1
	elif event.is_action_pressed("ui_focus_next", true):
		by = 1
	if by == 0:
		return false
	step(root, by)
	root.get_viewport().set_input_as_handled()
	return true


## Takes the keyboard into `card` as it opens, and returns what had it (or null).
static func enter(card: Control) -> Control:
	var before := card.get_viewport().gui_get_focus_owner()
	if before != null and (before == card or card.is_ancestor_of(before)):
		before = null
	card.focus_mode = Control.FOCUS_ALL
	card.grab_focus()
	return before


## Gives the keyboard back to `before` as a card closes, if it is still there to take it.
static func leave(card: Control, before: Control) -> void:
	var now := card.get_viewport().gui_get_focus_owner() if card.is_inside_tree() else null
	if now != null and now != card and not card.is_ancestor_of(now):
		return  # the keyboard has already gone elsewhere
	if before != null and is_instance_valid(before) and before.is_inside_tree() and before.is_visible_in_tree() and before.focus_mode != Control.FOCUS_NONE:
		before.grab_focus()
	elif now != null:
		now.release_focus()


## True when `control`, holding the keyboard, shows it: a ring of at least 2 px in a colour 3
## to 1 against the ground round it (the theme's "focus" box), or its own drawing (`focus_drawn`).
static func ringed(control: Control) -> bool:
	if control.has_meta("focus_drawn"):
		return true
	if not control.has_theme_stylebox("focus"):
		return false
	var box := control.get_theme_stylebox("focus") as StyleBoxFlat
	if box == null or box.border_width_left < 2 or box.border_width_top < 2 or box.border_color.a < 0.99:
		return false
	var under := Contrast.ground(control.get_parent() as Control) if control.get_parent() is Control else Contrast.paper_darkest()
	return Contrast.ratio(box.border_color, under) >= Contrast.LARGE
