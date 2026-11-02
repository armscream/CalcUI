package GUI

//* The height of a draggable widget's title bar.
HEADER_HEIGHT :: 24

//* Topmost visible widget under the pointer. Children are visited in
//* reverse order so the last child draws on top and wins the hit.
hit_test :: proc(g: ^GUI, id: Widget_ID, p: Vec2) -> Widget_ID {
	w := widget_get(g, id)
	if w == nil { return INVALID_WIDGET_ID }
	if !(.Visible in w.state) { return INVALID_WIDGET_ID }
	if !rect_contains(w.rect, p.x, p.y) { return INVALID_WIDGET_ID }

	child := w.last_child
	for child != INVALID_WIDGET_ID {
		c := widget_get(g, child)
		if c == nil { break }
		hit := hit_test(g, child, p)
		if hit != INVALID_WIDGET_ID { return hit }
		child = c.prev_sibling
	}
	return id
}

//* The widget under a point on the screen, and the point in the window
//* that widget lives in. A floating panel is a window of its own and
//* sits on top of the tree, so it is looked at first.
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

handle_events :: proc(g: ^GUI) {
	for ev in g.events {
		#partial switch e in ev {
		case Mouse_Move_Event:
			g.pointer = e.pos
			g.global_pointer = e.global
			if g.resize.active {
				resize_update(g, e.global)
			} else if g.drag.armed {
				drag_update(g, e.global)
			} else {
				hot, _ := hit_test_top(g, e.global)
				g.hot = hot
			}
		case Mouse_Down_Event:
			g.pointer = e.pos
			g.global_pointer = e.global
			//* A floating panel sits on top of the tree, so it is
			//* looked at first.
			hot, local := hit_test_top(g, e.global)
			g.hot = hot
			//* Any click takes the focus away from a text field: the
			//* caret and the selection both disappear.
			if g.focused != INVALID_WIDGET_ID {
				text_input_blur(g, g.focused)
				g.focused = INVALID_WIDGET_ID
			}
			g.active = g.hot
			g.lmb_down = true
			g.lmb_pressed = true
			//* A tab button switches tabs, and dragging it moves the
			//* panel it stands for.
			if host, tab, button := tab_at(g, e.global); tab != INVALID_WIDGET_ID {
				set_active_tab(g, host, tab)
				if !drag_start_tab(g, tab, e.pos, button, e.global) {
					g.active = INVALID_WIDGET_ID
				}
				break
			}
			//* An edge of a panel is a grip: pulling on it resizes the
			//* panel.
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
			g.lmb_down = false
			g.lmb_released = true
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
				if g.active != INVALID_WIDGET_ID && g.active == up {
					// Pointer capture: the click fires on whatever was
					// pressed, even if the pointer moved off it.
					fire_click(g, g.active)
				}
			}
			g.active = INVALID_WIDGET_ID
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
			g.layout_dirty = true
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
	w := widget_get(g, id)
	if w == nil { return }
	if !(.Enabled in w.state) { return }
	#partial switch d in w.data {
	case Button_Data:
		if d.on_click != nil { d.on_click(g, id) }
	}
}

//* == Dragging ==
//* A drag starts on a draggable widget's title bar. The drag is armed
//* by the press and begins once the pointer has travelled far enough,
//* so a click on a title bar stays a click. While it runs, the widget
//* follows the pointer as a floating ghost and the tree shows where it
//* would land.

header_rect :: proc(w: ^Widget) -> Rect {
	return Rect{x = w.rect.x, y = w.rect.y, w = w.rect.w, h = HEADER_HEIGHT}
}

//* Starts a drag when the pointer is on a draggable widget's header.
//* Returns true when the drag took over the mouse.
drag_start :: proc(g: ^GUI, id: Widget_ID, p: Vec2, global: Vec2) -> bool {
	w := widget_get(g, id)
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
	w := widget_get(g, tab)
	if w == nil { return false }
	if !w.draggable { return false }
	if !begin_drag(g, tab, p, Vec2{p.x - button.x, p.y - button.y}, global) { return false }
	//* A tab that is not showing has no size of its own, so it borrows
	//* the size of the host it lives in.
	if g.drag.size.x <= 0 || g.drag.size.y <= 0 {
		if host := widget_get(g, w.parent); host != nil {
			g.drag.size = Vec2{host.rect.w, max(host.rect.h - TAB_BAR_HEIGHT, 0)}
		}
	}
	return true
}

//* Arms a drag. The drag itself begins when the pointer moves.
begin_drag :: proc(g: ^GUI, id: Widget_ID, p: Vec2, grab: Vec2, global: Vec2) -> bool {
	w := widget_get(g, id)
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

//* Moves the drag along with the pointer and works out where the
//* panel would land.
drag_update :: proc(g: ^GUI, global: Vec2) {
	if !g.drag.armed { return }
	g.drag.pos = global

	if !g.drag.active {
		dx := global.x - g.drag.origin.x
		dy := global.y - g.drag.origin.y
		if dx * dx + dy * dy < DRAG_THRESHOLD * DRAG_THRESHOLD { return }
		g.drag.active = true
		g.layout_dirty = true
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
			float_panel(g, g.drag.widget, pos, g.drag.size)
		}
	}
	drag_cancel(g)
}

drag_cancel :: proc(g: ^GUI) {
	g.drag = Drag_State{}
	g.layout_dirty = true
}

//* True when `node` is inside `ancestor`'s subtree.
is_descendant :: proc(g: ^GUI, ancestor, node: Widget_ID) -> bool {
	w := widget_get(g, node)
	for w != nil {
		if w.parent == ancestor { return true }
		if w.parent == INVALID_WIDGET_ID { return false }
		w = widget_get(g, w.parent)
	}
	return false
}
