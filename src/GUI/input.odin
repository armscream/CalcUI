//* == Keyboard and Pointer input ==
//* The events come in one by one, and every one of them is given to the
//* widget it belongs to. The widget that is pressed takes the pointer
//* until the button is let go, and the widget that has the focus takes
//* the keys.

package GUI

HEADER_HEIGHT :: 24

hit_test_top :: proc(g: ^GUI, global: Vec2) -> (id: Widget_ID, local: Vec2) {
	for i := len(g.floats) - 1; i >= 0; i -= 1 {
		f := g.floats[i]
		local = Vec2{global.x - f.pos.x, global.y - f.pos.y}
		if !rect_contains(Rect{x = 0, y = 0, w = f.size.x, h = f.size.y}, local.x, local.y) {
			continue
		}
		id = hit_test(g, f.widget, local)
		if id != INVALID_WIDGET_ID { return id, local }
	}
	local = main_window_pos(g, global)
	return hit_test(g, g.root, local), local
}

pointer_chain :: proc(g: ^GUI, global: Vec2) -> (chain: [dynamic]Widget_ID, local: Vec2) {
	for i := len(g.floats) - 1; i >= 0; i -= 1 {
		f := g.floats[i]
		local = Vec2{global.x - f.pos.x, global.y - f.pos.y}
		if !rect_contains(Rect{x = 0, y = 0, w = f.size.x, h = f.size.y}, local.x, local.y) {
			continue
		}
		hits_that_take_the_mouse(g, f.widget, local, &chain)
		if len(chain) > 0 { return chain, local }
	}
	local = main_window_pos(g, global)
	hits_that_take_the_mouse(g, g.root, local, &chain)
	return chain, local
}

chain_target :: proc(chain: ^[dynamic]Widget_ID) -> Widget_ID {
	if len(chain^) == 0 { return INVALID_WIDGET_ID }
	return chain^[0]
}

Event_Handled :: proc(g: ^GUI) {
	if g == nil { return }
	g.event_handled = true
}

Event_Is_Handled :: proc(g: ^GUI) -> bool {
	if g == nil { return false }
	return g.event_handled
}

Handle_Events :: proc(g: ^GUI) {
	events := g.events
	g.events = [dynamic]Event{}
	defer delete(events)
	old_hot := g.hot
	old_active := g.active
	old_focused := g.focused
	g.lmb_pressed = false
	g.lmb_released = false
	defer widget_states_sync(g, old_hot, old_active, old_focused, g.hot, g.active, g.focused)
	for ev in events {
		#partial switch e in ev {
		case Mouse_Move_Event:
			handle_mouse_move(g, e)
		case Mouse_Down_Event:
			handle_mouse_down(g, e)
		case Mouse_Up_Event:
			handle_mouse_up(g, e)
		case Wheel_Event:
			handle_wheel(g, e)
		case Key_Down_Event:
			handle_key_down(g, e)
		case Key_Up_Event:
			g.mods = e.mods
		case Text_Input_Event:
			fire_text(g, g.focused, e.text)
			delete(e.text)
		case Ime_Editing_Event:
			text_input_ime_editing(g, e.text, e.start, e.length)
			delete(e.text)
		case Resized_Event:
			g.viewport = Rect{x = 0, y = 0, w = e.size.x, h = e.size.y}
			invalidate_all(g, Dirty_Flags{.Arrange, .Hit})
			if g.backend.resize != nil {
				g.backend.resize(
					g.backend.ctx,
					i32(e.size.x * g.scale),
					i32(e.size.y * g.scale),
				)
			}
		case Quit_Event:
			g.quit_requested = true
		}
	}
}

handle_mouse_move :: proc(g: ^GUI, e: Mouse_Move_Event) {
	g.pointer = e.pos
	g.global_pointer = e.global
	g.pointer_known = true

	if g.resize.active {
		resize_update(g, e.global)
	} else if g.drag.armed {
		drag_update(g, e.global)
	} else if g.slider_active != INVALID_WIDGET_ID {
		slider_move_to(g, g.slider_active, e.pos)
	}

	chain, _ := pointer_chain(g, e.global)
	defer delete(chain)
	g.hot = chain_target(&chain)

	if g.active != INVALID_WIDGET_ID {
		fire_pointer(g, g.active, Pointer_Event {
			kind = .Move,
			pos = e.pos,
			global = e.global,
		})
		return
	}
	fire_pointer_chain(g, &chain, Pointer_Event {
		kind = .Move,
		pos = e.pos,
		global = e.global,
	})
}

handle_mouse_down :: proc(g: ^GUI, e: Mouse_Down_Event) {
	g.pointer = e.pos
	g.global_pointer = e.global
	g.pointer_known = true

	//* A click outside the menu that is open closes it, and the click
	//* goes to the widget under it. The place of the click is the place
	//* on the screen, so a click in a floating panel is judged against
	//* the window it belongs to.
	popup_close_outside(g, e.global)

	chain, local := pointer_chain(g, e.global)
	defer delete(chain)
	hot := chain_target(&chain)
	g.hot = hot

	if e.button == .Left { focus_clear(g) }

	g.lmb_down = true
	g.lmb_pressed = true

	g.active = INVALID_WIDGET_ID
	if e.button == .Left { g.active = hot }

	fire_pointer_chain(g, &chain, Pointer_Event {
		kind = .Down,
		pos = e.pos,
		global = e.global,
		button = e.button,
		clicks = e.clicks,
	})

	if is_slider(Widget_Get(g, hot)) {
		g.slider_active = hot
		slider_move_to(g, hot, e.pos)
		return
	}

	if host, tab, button := tab_at(g, e.global); tab != INVALID_WIDGET_ID {
		set_active_tab(g, host, tab)
		if !drag_start_tab(g, tab, e.pos, button, e.global) {
			g.active = INVALID_WIDGET_ID
		}
		return
	}
	if id, edges := find_resize_grip(g, e.global); id != INVALID_WIDGET_ID {
		resize_begin(g, id, edges, e.global)
		return
	}
	if drag_start(g, hot, e.pos, e.global) {
		return
	}
	focus_click(g, hot, local, e.clicks)
}

handle_mouse_up :: proc(g: ^GUI, e: Mouse_Up_Event) {
	g.pointer = e.pos
	g.global_pointer = e.global
	g.pointer_known = true
	g.lmb_down = false
	g.lmb_released = true
	g.slider_active = INVALID_WIDGET_ID

	if g.resize.active {
		resize_end(g)
		g.active = INVALID_WIDGET_ID
		return
	}
	if g.drag.active {
		drag_end(g, e.global)
		g.active = INVALID_WIDGET_ID
		return
	}
	if g.drag.armed {
		drag_cancel(g)
	}

	chain, _ := pointer_chain(g, e.global)
	defer delete(chain)
	up := chain_target(&chain)
	g.hot = up

	if g.active != INVALID_WIDGET_ID {
		fire_pointer(g, g.active, Pointer_Event {
			kind = .Up,
			pos = e.pos,
			global = e.global,
			button = e.button,
		})
	} else {
		fire_pointer_chain(g, &chain, Pointer_Event {
			kind = .Up,
			pos = e.pos,
			global = e.global,
			button = e.button,
		})
	}

	if g.active != INVALID_WIDGET_ID && g.active == up {
		fire_click(g, g.active)
	}
	g.active = INVALID_WIDGET_ID
}

handle_wheel :: proc(g: ^GUI, e: Wheel_Event) {
	if !g.pointer_known { return }
	chain, _ := wheel_chain(g, g.global_pointer)
	defer delete(chain)
	g.hot = wheel_hot(g, &chain)
	fire_pointer_chain(g, &chain, Pointer_Event {
		kind = .Wheel,
		pos = g.pointer,
		global = g.global_pointer,
		amount = e.amount,
	})
}

wheel_hot :: proc(g: ^GUI, chain: ^[dynamic]Widget_ID) -> Widget_ID {
	for id in chain^ {
		w := Widget_Get(g, id)
		if w == nil { continue }
		if w.mouse_filter == .Ignore { continue }
		return id
	}
	return INVALID_WIDGET_ID
}

handle_key_down :: proc(g: ^GUI, e: Key_Down_Event) {
	g.mods = e.mods
	g.event_handled = false

	if e.key == .Escape {
		if g.resize.active {
			resize_cancel(g)
			return
		}
		if g.drag.armed {
			drag_cancel(g)
			return
		}
		if popup_close_top(g) { return }
		fire_key(g, g.focused, e)
		if g.event_handled { return }
		g.quit_requested = true
		return
	}

	if e.key == .Tab {
		fire_key(g, g.focused, e)
		if g.event_handled { return }
		next := focus_next(g, g.focused, !(.Shift in e.mods))
		if next != INVALID_WIDGET_ID { focus_set(g, next) }
		return
	}

	if shortcut_fire(g, e.key, e.mods) {
		Event_Handled(g)
		return
	}

	if direction := arrow_direction(e.key); direction >= 0 {
		focused := g.focused
		fire_key(g, focused, e)
		if g.event_handled { return }
		if !uses_arrow_keys(g, focused) {
			next := focus_neighbour(g, focused, direction)
			if next != INVALID_WIDGET_ID { focus_set(g, next) }
		}
		return
	}

	fire_key(g, g.focused, e)
}

fire_pointer_chain :: proc(g: ^GUI, chain: ^[dynamic]Widget_ID, e: Pointer_Event) {
	g.event_handled = false
	for id in chain^ {
		if g.event_handled { return }
		fire_pointer(g, id, e)
	}
}

Widget_Capture_Pointer :: proc(g: ^GUI, id: Widget_ID) -> bool {
	if g == nil { return false }
	w := Widget_Get(g, id)
	if w == nil { return false }
	if !(.Enabled in w.state) { return false }
	g.active = id
	return true
}

Widget_Release_Pointer :: proc(g: ^GUI) {
	if g == nil { return }
	g.active = INVALID_WIDGET_ID
	g.slider_active = INVALID_WIDGET_ID
}

Pointer_Captured :: proc(g: ^GUI) -> Widget_ID {
	if g == nil { return INVALID_WIDGET_ID }
	return g.active
}

fire_click :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if !(.Enabled in w.state) { return }

	pressed := w.signals.on_pressed

	if kind := widget_kind(g, w); kind.click != nil {
		kind.click(g, id, w)
		if pressed != nil { pressed(g, id) }
		return
	}

	#partial switch d in w.data {
	case Button_Data:
		if d.on_click != nil { d.on_click(g, id) }
	}
	if pressed != nil { pressed(g, id) }
}

fire_pointer :: proc(g: ^GUI, id: Widget_ID, e: Pointer_Event) {
	if g == nil || id == INVALID_WIDGET_ID { return }
	w := Widget_Get(g, id)
	if w == nil { return }
	if !(.Enabled in w.state) { return }
	kind := widget_kind(g, w)
	if kind.pointer == nil { return }
	event := e
	event.local = Vec2{e.pos.x - w.rect.x, e.pos.y - w.rect.y}
	kind.pointer(g, id, w, event)
}

item_list_click :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	style := resolved_style(g, w)
	content := content_rect_with(w.rect, style.box.content_margin)
	index := int((g.pointer.y - content.y) / ITEM_LIST_ROW)
	if index < 0 { return }
	item_list_select(g, id, index)
}

tree_click :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	d := tree_data(g, id)
	if d == nil { return }
	content := tree_content(g, w)
	tree_scroll_clamp(d, content.h)
	//* The row under the pointer is the one that is scrolled to that
	//* place.
	offset := g.pointer.y - content.y + d.scroll
	if offset < 0 { return }
	index := int(offset / f32(TREE_ROW))
	if index >= len(d.items) { return }
	tree_select_item(g, id, index)
}

is_slider :: proc(w: ^Widget) -> bool {
	if w == nil { return false }
	#partial switch d in w.data {
	case Slider_Data:
		return true
	}
	return false
}

slider_move_to :: proc(g: ^GUI, id: Widget_ID, p: Vec2) {
	w := Widget_Get(g, id)
	if w == nil { return }
	style := resolved_style(g, w)
	content := content_rect_with(w.rect, style.box.content_margin)
	#partial switch d in w.data {
	case Slider_Data:
		span := d.max - d.min
		if span <= 0 { return }
		factor := f32(0)
		if w.type == .VSlider {
			if content.h <= 0 { return }
			factor = 1 - (p.y - content.y) / content.h
		} else {
			if content.w <= 0 { return }
			factor = (p.x - content.x) / content.w
		}
		slider_set_value(g, id, d.min + clamp(factor, 0, 1) * span)
	}
}

arrow_direction :: proc(key: Key) -> int {
	#partial switch key {
	case .Left:  return 0
	case .Up:    return 1
	case .Right: return 2
	case .Down:  return 3
	}
	return -1
}

uses_arrow_keys :: proc(g: ^GUI, id: Widget_ID) -> bool {
	w := Widget_Get(g, id)
	if w == nil { return false }
	if kind := widget_kind(g, w); kind.uses_arrow_keys { return true }
	#partial switch d in w.data {
	case Text_Box_Data:
		return true
	}
	return false
}

header_rect :: proc(w: ^Widget) -> Rect {
	return Rect{x = w.rect.x, y = w.rect.y, w = w.rect.w, h = HEADER_HEIGHT}
}

drag_start :: proc(g: ^GUI, id: Widget_ID, p: Vec2, global: Vec2) -> bool {
	w := Widget_Get(g, id)
	if w == nil { return false }
	if !w.draggable { return false }
	if is_tab_child(g, id) { return false }
	if !rect_contains(header_rect(w), p.x, p.y) { return false }
	return begin_drag(g, id, p, Vec2{p.x - w.rect.x, p.y - w.rect.y}, global)
}

drag_start_tab :: proc(g: ^GUI, tab: Widget_ID, p: Vec2, button: Rect, global: Vec2) -> bool {
	w := Widget_Get(g, tab)
	if w == nil { return false }
	if !w.draggable { return false }
	if !begin_drag(g, tab, p, Vec2{p.x - button.x, p.y - button.y}, global) { return false }
	if g.drag.size.x <= 0 || g.drag.size.y <= 0 {
		if host := Widget_Get(g, w.parent); host != nil {
			g.drag.size = Vec2{host.rect.w, max(host.rect.h - TAB_BAR_HEIGHT, 0)}
		}
	}
	return true
}

begin_drag :: proc(g: ^GUI, id: Widget_ID, p: Vec2, grab: Vec2, global: Vec2) -> bool {
	w := Widget_Get(g, id)
	if w == nil { return false }

	g.drag.armed = true
	g.drag.active = false
	g.drag.origin = global
	g.drag.widget = id
	g.drag.pos = global
	g.drag.grab = grab
	g.drag.ghost = w.rect
	g.drag.size = Vec2{w.rect.w, w.rect.h}
	g.drag.slot = w.rect
	g.drag.target = INVALID_WIDGET_ID
	g.drag.tab_host = INVALID_WIDGET_ID
	g.drag.zone = .None
	g.drag.kind = .None
	g.drag.swap = false
	g.drag.float_index = float_of(g, id)
	g.drag.plan = Dock_Plan{}
	return true
}

drag_update :: proc(g: ^GUI, global: Vec2) {
	if !g.drag.armed { return }
	g.drag.pos = global

	if !g.drag.active {
		dx := global.x - g.drag.origin.x
		dy := global.y - g.drag.origin.y
		if dx * dx + dy * dy < DRAG_THRESHOLD * DRAG_THRESHOLD { return }
		g.drag.active = true
		invalidate(g, g.drag.widget, Dirty_Flags{.Arrange, .Hit})
	}

	local := main_window_pos(g, global)

	if g.drag.float_index >= 0 {
		f := &g.floats[g.drag.float_index]
		f.pos = Vec2{global.x - g.drag.grab.x, global.y - g.drag.grab.y}
	} else {
		g.drag.ghost = Rect{
			x = local.x - g.drag.grab.x,
			y = local.y - g.drag.grab.y,
			w = g.drag.size.x,
			h = g.drag.size.y,
		}
	}

	drag_refresh(g, global)
}

drag_refresh :: proc(g: ^GUI, global: Vec2) {
	local := main_window_pos(g, global)
	g.drag.target = find_drop_target(g, g.drag.widget, local)
	g.drag.tab_host = find_tab_host(g, g.drag.widget, local)

	container := g.drag.target
	zone := Dock_Zone.None
	if container != INVALID_WIDGET_ID {
		zone = dock_zone_for(g, container, local)
	}
	if zone == .Center {
		if g.drag.tab_host != INVALID_WIDGET_ID {
			container = g.drag.tab_host
		} else {
			zone = .None
		}
	}

	g.drag.zone = zone
	g.drag.swap = .Ctrl in g.mods
	g.drag.plan = dock_plan(g, g.drag.widget, container, zone, g.drag.swap, local)
	g.drag.kind = g.drag.plan.kind
}

drag_end :: proc(g: ^GUI, global: Vec2) {
	if g.drag.active {
		drag_refresh(g, global)

		if g.drag.plan.kind != .None {
			if g.drag.float_index >= 0 {
				unfloat_panel(g, g.drag.float_index)
				g.drag.float_index = FLOAT_NONE
			}
			dock_apply(g, g.drag.widget, g.drag.plan)
		} else if g.drag.float_index < 0 && outside_main_window(g, global) {
			pos := Vec2{global.x - g.drag.grab.x, global.y - g.drag.grab.y}
			Make_Float_Panel(g, g.drag.widget, pos, g.drag.size)
		}
		delta := Vec2{global.x - g.drag.origin.x, global.y - g.drag.origin.y}
		signal_dragged(g, g.drag.widget, delta)
	}
	drag_cancel(g)
}

drag_cancel :: proc(g: ^GUI) {
	if g.drag.widget != INVALID_WIDGET_ID {
		invalidate(g, g.drag.widget, Dirty_Flags{.Arrange, .Hit})
	}
	g.drag = drag_state_none()
}

drag_state_none :: proc() -> Drag_State {
	return Drag_State{float_index = FLOAT_NONE}
}

is_descendant :: proc(g: ^GUI, ancestor, node: Widget_ID) -> bool {
	w := Widget_Get(g, node)
	for w != nil {
		if w.parent == ancestor { return true }
		if w.parent == INVALID_WIDGET_ID { return false }
		w = Widget_Get(g, w.parent)
	}
	return false
}
