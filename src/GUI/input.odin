package GUI

//* The height of a draggable widget's title bar.
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

Handle_Events :: proc(g: ^GUI) {
	for ev in g.events {
		#partial switch e in ev {
		case Mouse_Move_Event:
			g.pointer = e.pos
			g.global_pointer = e.global
			g.pointer_known = true
			if g.resize.active {
				resize_update(g, e.global)
			} else if g.drag.armed {
				drag_update(g, e.global)
			} else if g.slider_active != INVALID_WIDGET_ID {
				//* The slider under the pointer follows it.
				slider_move_to(g, g.slider_active, e.pos)
			} else {
				hot, _ := hit_test_top(g, e.global)
				g.hot = hot
			}
			//* The widget under the pointer is told that it moved.
			fire_pointer(g, g.hot, Pointer_Event {
				kind = .Move,
				pos = e.pos,
				global = e.global,
			})
		case Mouse_Down_Event:
			g.pointer = e.pos
			g.global_pointer = e.global
			g.pointer_known = true
			//* A floating panel sits on top of the tree, so it is
			//* looked at first.
			hot, local := hit_test_top(g, e.global)
			g.hot = hot
			//* Any click takes the focus away from a text field: the
			//* caret and the selection both disappear.
			focus_clear(g)
			g.active = g.hot
			g.lmb_down = true
			g.lmb_pressed = true
			//* The widget under the pointer is told that the button
			//* went down on it.
			fire_pointer(g, g.hot, Pointer_Event {
				kind = .Down,
				pos = e.pos,
				global = e.global,
				button = e.button,
				clicks = e.clicks,
			})
			//* A slider takes the pointer: it follows it until the
			//* button is let go.
			if is_slider(Widget_Get(g, g.hot)) {
				g.slider_active = g.hot
				slider_move_to(g, g.hot, e.pos)
				break
			}
			//* A tab button switches tabs, and dragging it moves the
			//* panel it stands for.
			if host, tab, button := tab_at(g, e.global); tab != INVALID_WIDGET_ID {
				set_active_tab(g, host, tab)
				if !drag_start_tab(g, tab, e.pos, button, e.global) {
					g.active = INVALID_WIDGET_ID
				}
				break
			}
			//* An edge of a panel is a grip: pulling on it resizes the panel.
			if id, edges := find_resize_grip(g, e.global); id != INVALID_WIDGET_ID {
				resize_begin(g, id, edges, e.global)
				break
			}
			if drag_start(g, g.hot, e.pos, e.global) {
				// The drag owns the mouse until it ends.
				break
			}
			focus_click(g, g.hot, local, e.clicks)
		case Mouse_Up_Event:
			g.pointer = e.pos
			g.global_pointer = e.global
			g.pointer_known = true
			g.lmb_down = false
			g.lmb_released = true
			g.slider_active = INVALID_WIDGET_ID
			if g.resize.active {
				//* The resize owns the mouse until it ends.
				resize_end(g)
			} else if g.drag.active {
				drag_end(g, e.global)
			} else {
				if g.drag.armed {
					//* The pointer never travelled far enough: this
					//* was a click, not a drag.
					drag_cancel(g)
				}
				up, _ := hit_test_top(g, e.global)
				//* The widget under the pointer is told that the
				//* button came up over it.
				fire_pointer(g, up, Pointer_Event {
					kind = .Up,
					pos = e.pos,
					global = e.global,
					button = e.button,
				})
				if g.active != INVALID_WIDGET_ID && g.active == up {
					// Pointer capture: the click fires on whatever was
					// pressed, even if the pointer moved off it.
					fire_click(g, g.active)
				}
			}
			g.active = INVALID_WIDGET_ID
		case Wheel_Event:
			//* The wheel turns over the widget under the pointer.
			if g.pointer_known {
				hot, _ := hit_test_top(g, g.global_pointer)
				fire_pointer(g, hot, Pointer_Event {
					kind = .Wheel,
					pos = g.pointer,
					global = g.global_pointer,
					amount = e.amount,
				})
			}
		case Key_Down_Event:
			g.mods = e.mods
			if e.key == .Escape {
				if g.resize.active {
					resize_cancel(g)
					break
				}
				if g.drag.armed {
					drag_cancel(g)
					break
				}
				g.quit_requested = true
				break
			}
			//* The tab key moves the focus from one widget to the next one.
			if e.key == .Tab {
				next := focus_next(g, g.focused, !(.Shift in e.mods))
				if next != INVALID_WIDGET_ID { focus_set(g, next) }
				break
			}
			//* The arrow keys move the focus too, unless the widget
			//* that has it uses them itself.
			if direction := arrow_direction(e.key); direction >= 0 {
				if !uses_arrow_keys(g, g.focused) {
					next := focus_neighbour(g, g.focused, direction)
					if next != INVALID_WIDGET_ID { focus_set(g, next) }
				}
				fire_key(g, g.focused, e)
				break
			}
			fire_key(g, g.focused, e)
		case Key_Up_Event:
			g.mods = e.mods
		case Text_Input_Event:
			fire_text(g, g.focused, e.text)
			//* The producer of the event allocated the string, the core
			//* owns it and frees it here.
			delete(e.text)
		case Ime_Editing_Event:
			g.ime_text = e.text
		case Resized_Event:
			g.viewport = Rect{x = 0, y = 0, w = e.size.x, h = e.size.y}
			//* The window is a different size now, so every widget is
			//* placed again.
			invalidate_all(g, Dirty_Flags{.Arrange, .Hit})
			if g.backend.resize != nil {
				g.backend.resize(g.backend.ctx, i32(e.size.x), i32(e.size.y))
			}
		case Quit_Event:
			g.quit_requested = true
		}
	}
	clear(&g.events)
}

fire_click :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if !(.Enabled in w.state) { return }

	//* A widget that came after the first ones has its own hooks.
	if kind := widget_kind(g, w); kind.click != nil {
		kind.click(g, id, w)
		signal_pressed(g, id)
		return
	}

	#partial switch d in w.data {
	case Button_Data:
		if d.on_click != nil { d.on_click(g, id) }
	}
	signal_pressed(g, id)
}

//* Tells a widget what the pointer did to it. The place of the pointer
//* is given in the window of the GUI and in the widget itself, so a
//* widget does not have to work out where the pointer is in it.
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

//* The item of a list under the pointer, and the picking of it.
item_list_click :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	style := resolved_style(g, w)
	content := content_rect_with(w.rect, style.box.content_margin)
	index := int((g.pointer.y - content.y) / ITEM_LIST_ROW)
	if index < 0 { return }
	item_list_select(g, id, index)
}

//* The item of a tree under the pointer, and the picking of it.
tree_click :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	style := resolved_style(g, w)
	content := content_rect_with(w.rect, style.box.content_margin)
	index := int((g.pointer.y - content.y) / TREE_ROW)
	if index < 0 { return }
	tree_select_item(g, id, index)
}

//* True when the widget is a slider, so that the pointer can move it.
is_slider :: proc(w: ^Widget) -> bool {
	if w == nil { return false }
	#partial switch d in w.data {
	case Slider_Data:
		return true
	}
	return false
}

//* Moves a slider to the place of the pointer.
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

//* The direction an arrow key points at: left, top, right, bottom. The
//* number is -1 when the key is not an arrow key.
arrow_direction :: proc(key: Key) -> int {
	#partial switch key {
	case .Left:  return 0
	case .Up:    return 1
	case .Right: return 2
	case .Down:  return 3
	}
	return -1
}

//* True when the widget uses the arrow keys itself, so that they do not
//* move the focus.
uses_arrow_keys :: proc(g: ^GUI, id: Widget_ID) -> bool {
	w := Widget_Get(g, id)
	if w == nil { return false }
	//* A class can say that it uses the arrow keys itself.
	if kind := widget_kind(g, w); kind.uses_arrow_keys { return true }
	#partial switch d in w.data {
	case Text_Input_Data:
		return true
	}
	return false
}

//* == Dragging ==
header_rect :: proc(w: ^Widget) -> Rect {
	return Rect{x = w.rect.x, y = w.rect.y, w = w.rect.w, h = HEADER_HEIGHT}
}

//* Starts a drag when the pointer is on a draggable widget's header.
//* Returns true when the drag took over the mouse.
drag_start :: proc(g: ^GUI, id: Widget_ID, p: Vec2, global: Vec2) -> bool {
	w := Widget_Get(g, id)
	if w == nil { return false }
	if !w.draggable { return false }
	//* A panel that lives in a tab strip is dragged by its tab.
	if is_tab_child(g, id) { return false }
	if !rect_contains(header_rect(w), p.x, p.y) { return false }
	return begin_drag(g, id, p, Vec2{p.x - w.rect.x, p.y - w.rect.y}, global)
}

//* Starts a drag from a tab button. The button is the handle, so the
//* ghost hangs from where the tab was.
drag_start_tab :: proc(g: ^GUI, tab: Widget_ID, p: Vec2, button: Rect, global: Vec2) -> bool {
	w := Widget_Get(g, tab)
	if w == nil { return false }
	if !w.draggable { return false }
	if !begin_drag(g, tab, p, Vec2{p.x - button.x, p.y - button.y}, global) { return false }
	//* A tab that is not showing has no size of its own, so it borrows
	//* the size of the host it lives in.
	if g.drag.size.x <= 0 || g.drag.size.y <= 0 {
		if host := Widget_Get(g, w.parent); host != nil {
			g.drag.size = Vec2{host.rect.w, max(host.rect.h - TAB_BAR_HEIGHT, 0)}
		}
	}
	return true
}

//* Arms a drag. The drag itself begins when the pointer moves.
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

//* Moves the drag along with the pointer and works out where the panel would land.
drag_update :: proc(g: ^GUI, global: Vec2) {
	if !g.drag.armed { return }
	g.drag.pos = global

	if !g.drag.active {
		dx := global.x - g.drag.origin.x
		dy := global.y - g.drag.origin.y
		if dx * dx + dy * dy < DRAG_THRESHOLD * DRAG_THRESHOLD { return }
		g.drag.active = true
		//* The panel has left its place in the tree, so the tree is
		//* laid out again without it.
		invalidate(g, g.drag.widget, Dirty_Flags{.Arrange, .Hit})
	}

	local := main_window_pos(g, global)

	if g.drag.float_index >= 0 {
		//* The panel is a window of its own: it follows the pointer.
		f := &g.floats[g.drag.float_index]
		f.pos = Vec2{global.x - g.drag.grab.x, global.y - g.drag.grab.y}
	} else {
		//* The ghost follows the pointer. It keeps the size the panel
		//* had when the drag started, because the panel has left the
		//* layout.
		g.drag.ghost = Rect{
			x = local.x - g.drag.grab.x,
			y = local.y - g.drag.grab.y,
			w = g.drag.size.x,
			h = g.drag.size.y,
		}
	}

	drag_refresh(g, global)
}

//* Works out where the panel would land if the pointer were here.
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
		//* The middle of a container merges the panel into the tab
		//* host under the pointer.
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

//* Drops the dragged widget into its target.
drag_end :: proc(g: ^GUI, global: Vec2) {
	if g.drag.active {
		//* The plan is worked out again, so the drop uses the place
		//* the button came up at.
		drag_refresh(g, global)

		if g.drag.plan.kind != .None {
			if g.drag.float_index >= 0 {
				//* The panel goes back into the tree.
				unfloat_panel(g, g.drag.float_index)
				g.drag.float_index = FLOAT_NONE
			}
			dock_apply(g, g.drag.widget, g.drag.plan)
		} else if g.drag.float_index < 0 && outside_main_window(g, global) {
			//* Dropped outside of the window: the panel floats and
			//* gets a window of its own.
			pos := Vec2{global.x - g.drag.grab.x, global.y - g.drag.grab.y}
			Make_Float_Panel(g, g.drag.widget, pos, g.drag.size)
		}
		//* The widget was moved, so the program is told how far it went.
		delta := Vec2{global.x - g.drag.origin.x, global.y - g.drag.origin.y}
		signal_dragged(g, g.drag.widget, delta)
	}
	drag_cancel(g)
}

drag_cancel :: proc(g: ^GUI) {
	//* The panel goes back into the place it was taken from: it had no
	//* geometry while it was being dragged, so it is laid out again.
	if g.drag.widget != INVALID_WIDGET_ID {
		invalidate(g, g.drag.widget, Dirty_Flags{.Arrange, .Hit})
	}
	g.drag = drag_state_none()
}

//* The drag that is not running. The index of the floating panel is
//* FLOAT_NONE, so that a drag that is not running does not point at
//* the first floating panel.
drag_state_none :: proc() -> Drag_State {
	return Drag_State{float_index = FLOAT_NONE}
}

//* True when `node` is inside `ancestor`'s subtree.
is_descendant :: proc(g: ^GUI, ancestor, node: Widget_ID) -> bool {
	w := Widget_Get(g, node)
	for w != nil {
		if w.parent == ancestor { return true }
		if w.parent == INVALID_WIDGET_ID { return false }
		w = Widget_Get(g, w.parent)
	}
	return false
}
