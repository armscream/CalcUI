//* Docking, in the style of Dear ImGui.
//* A drop is planned before it is applied, and the plan holds the exact
//* rects the drop would produce, so the preview shows the result and not
//* a guess.

package GUI

//* == drop types ==
//*   - Split: the container becomes a split and the panel is one of its
//*     slices. The container keeps its own type and contents, so
//*     nothing inside it changes shape.
//*   - Tabs: the panel becomes a tab of the container. The tab strip is
//*     drawn, so the panel that was already there stays reachable.
//*   - Swap: the panel and the container exchange their slots.

//* The height of a tab strip, in pixels.
TAB_BAR_HEIGHT :: 24
//* The padding around the text of a tab, in pixels.
TAB_PADDING :: 10
//* How far from the edge of a container a drop still counts as "on that
//* edge", as a fraction of the container's size.
DOCK_EDGE_FRACTION :: 0.25
//* The smallest edge band, in pixels.
DOCK_EDGE_MIN :: 24
//* How far the pointer has to travel, in pixels, before a press on a
//* title bar becomes a drag.
DRAG_THRESHOLD :: 4

//* == Helpers ==

split_direction :: proc(w: ^Widget) -> Split_Direction {
	#partial switch d in w.data {
	case Split_Data:
		return d.direction
	}
	return .Horizontal
}

//* The tab of a tab host that is showing. A tab container keeps its
//* own tab, so it is asked as well.
tabs_active :: proc(w: ^Widget) -> int {
	#partial switch d in w.data {
	case Tabs_Data:
		return d.active
	case Tab_Container_Data:
		return d.active
	}
	return 0
}

is_tab_child :: proc(g: ^GUI, id: Widget_ID) -> bool {
	w := Widget_Get(g, id)
	if w == nil || w.parent == INVALID_WIDGET_ID { return false }
	p := Widget_Get(g, w.parent)
	return p != nil && (p.type == .Tabs || p.type == .TabContainer)
}

//* True when the widget is a tab of a dock tab host. A tab is not a
//* container of its own: a drop on a tab is a drop on the host that
//* holds it. Without this the panel would be put in a new host inside
//* the old one, and the tab would be in two strips at once.
is_tab_of_host :: proc(g: ^GUI, id: Widget_ID) -> bool {
	w := Widget_Get(g, id)
	if w == nil || w.parent == INVALID_WIDGET_ID { return false }
	p := Widget_Get(g, w.parent)
	return p != nil && p.type == .Tabs
}

//* True when the widget is a tab that is not showing. A hidden tab
//* keeps no geometry, so it is neither drawn nor hit.
is_hidden_tab :: proc(g: ^GUI, id: Widget_ID) -> bool {
	w := Widget_Get(g, id)
	if w == nil || w.parent == INVALID_WIDGET_ID { return false }
	p := Widget_Get(g, w.parent)
	if p == nil || (p.type != .Tabs && p.type != .TabContainer) { return false }
	active := tabs_active(p)
	index := 0
	child := p.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil { break }
		if child == id { return index != active }
		index += 1
		child = c.next_sibling
	}
	return false
}

tab_bar_rect :: proc(w: ^Widget) -> Rect {
	return Rect{x = w.rect.x, y = w.rect.y, w = w.rect.w, h = TAB_BAR_HEIGHT}
}

tabs_content_rect :: proc(w: ^Widget) -> Rect {
	r := w.rect
	r.y += TAB_BAR_HEIGHT
	r.h -= TAB_BAR_HEIGHT
	if r.h < 0 { r.h = 0 }
	return r
}

tab_button_width :: proc(g: ^GUI, w: ^Widget) -> f32 {
	label := w.name
	if label == "" { label = "Tab" }
	size := Font_Measure(g, Font_Of(g, w), label)
	return size.x + TAB_PADDING * 2
}

//* The buttons of a tab host's strip, in child order. The strip runs
//* out of room when the tabs do not fit, so the caller clips them.
tab_button_rects :: proc(g: ^GUI, host: ^Widget, out: ^[MAX_TABS]Rect) -> int {
	bar := tab_bar_rect(host)
	x := bar.x
	n := 0
	child := host.first_child
	for child != INVALID_WIDGET_ID && n < MAX_TABS {
		c := Widget_Get(g, child)
		if c == nil { break }
		out[n] = Rect{x = x, y = bar.y, w = tab_button_width(g, c), h = bar.h}
		x += out[n].w
		n += 1
		child = c.next_sibling
	}
	return n
}

tab_strip_width :: proc(g: ^GUI, host: ^Widget) -> f32 {
	total := f32(0)
	child := host.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil { break }
		total += tab_button_width(g, c)
		child = c.next_sibling
	}
	return total
}

//* == Zones ==

//* Which part of a container the pointer is over. The edges split the
//* container, the middle merges the panel into it as a tab.
dock_zone :: proc(container: Rect, p: Vec2) -> Dock_Zone {
	if !rect_contains(container, p.x, p.y) { return .None }

	w := max(container.w, 1)
	h := max(container.h, 1)
	dl := (p.x - container.x) / w
	dr := (container.x + container.w - p.x) / w
	dt := (p.y - container.y) / h
	db := (container.y + container.h - p.y) / h

	//* The closest edge wins, so a corner resolves to one direction
	//* instead of two.
	if dl <= dr && dl <= dt && dl <= db {
		if dl * w <= max(DOCK_EDGE_MIN, w * DOCK_EDGE_FRACTION) { return .Left }
	}
	if dr <= dl && dr <= dt && dr <= db {
		if dr * w <= max(DOCK_EDGE_MIN, w * DOCK_EDGE_FRACTION) { return .Right }
	}
	if dt <= dl && dt <= dr && dt <= db {
		if dt * h <= max(DOCK_EDGE_MIN, h * DOCK_EDGE_FRACTION) { return .Top }
	}
	if db <= dl && db <= dr && db <= dt {
		if db * h <= max(DOCK_EDGE_MIN, h * DOCK_EDGE_FRACTION) { return .Bottom }
	}
	return .Center
}

//* The part of a container the drop zones are measured on. The strip
//* of a tab host is always a tab drop, so the zones are the content
//* below it.
dock_zone_container :: proc(g: ^GUI, container: Widget_ID) -> Rect {
	w := Widget_Get(g, container)
	if w == nil { return {} }
	if w.type == .Tabs { return tabs_content_rect(w) }
	return w.rect
}

dock_zone_for :: proc(g: ^GUI, container: Widget_ID, p: Vec2) -> Dock_Zone {
	w := Widget_Get(g, container)
	if w == nil { return .None }
	if w.type == .Tabs {
		bar := tab_bar_rect(w)
		if rect_contains(w.rect, p.x, p.y) && rect_contains(bar, p.x, p.y) {
			return .Center
		}
	}
	return dock_zone(dock_zone_container(g, container), p)
}

//* The rects a container offers: the four edges split it, the middle
//* merges a panel into it.
dock_zone_rects :: proc(container: Rect, out: ^[5]Rect) -> int {
	ew := container.w * DOCK_EDGE_FRACTION
	eh := container.h * DOCK_EDGE_FRACTION
	out[0] = Rect{x = container.x, y = container.y, w = container.w, h = eh}
	out[1] = Rect{x = container.x, y = container.y + container.h - eh, w = container.w, h = eh}
	out[2] = Rect{x = container.x, y = container.y, w = ew, h = container.h}
	out[3] = Rect{x = container.x + container.w - ew, y = container.y, w = ew, h = container.h}
	out[4] = Rect{
		x = container.x + ew,
		y = container.y + eh,
		w = container.w - ew * 2,
		h = container.h - eh * 2,
	}
	return 5
}

dock_zone_index :: proc(zone: Dock_Zone) -> int {
	#partial switch zone {
	case .Top:    return 0
	case .Bottom: return 1
	case .Left:   return 2
	case .Right:  return 3
	case .Center: return 4
	case .None:   return -1
	}
	return -1
}

dock_zone_rect :: proc(container: Rect, zone: Dock_Zone) -> Rect {
	rects: [5]Rect
	dock_zone_rects(container, &rects)
	i := dock_zone_index(zone)
	if i < 0 { return {} }
	return rects[i]
}

//* == Empty space ==
//* A container can have space that none of its children uses: an empty
//* container has all of it, and a container whose children do not fill
//* it has the rest. A panel dropped into that space takes it.

//* The most pieces the free space of a container is cut into. Every
//* child can cut a piece into four, so the number of pieces grows fast
//* and the pieces that do not fit are left out.
MAX_FREE_PIECES :: 8

//* Cuts `cut` out of `r`, leaving up to four pieces. The pieces are put
//* in `out` at `start_at`, and their number is returned. Pieces that do
//* not fit are left out, so the space that is reported stays free space.
subtract_rect :: proc(r, cut: Rect, out: ^[MAX_FREE_PIECES]Rect, start_at: int) -> int {
	start := start_at
	at := start
	limit := len(out)
	x0 := max(r.x, cut.x)
	y0 := max(r.y, cut.y)
	x1 := min(r.x + r.w, cut.x + cut.w)
	y1 := min(r.y + r.h, cut.y + cut.h)
	if x1 <= x0 || y1 <= y0 {
		if at < limit {
			out[at] = r
			at += 1
		}
		return at - start
	}

	if y0 > r.y && at < limit {
		out[at] = Rect{x = r.x, y = r.y, w = r.w, h = y0 - r.y}
		at += 1
	}
	if y1 < r.y + r.h && at < limit {
		out[at] = Rect{x = r.x, y = y1, w = r.w, h = r.y + r.h - y1}
		at += 1
	}
	if x0 > r.x && at < limit {
		out[at] = Rect{x = r.x, y = y0, w = x0 - r.x, h = y1 - y0}
		at += 1
	}
	if x1 < r.x + r.w && at < limit {
		out[at] = Rect{x = x1, y = y0, w = r.x + r.w - x1, h = y1 - y0}
		at += 1
	}
	return at - start
}

//* The space in a container that none of its children uses. The pieces
//* are returned with the largest one first.
container_free_space :: proc(g: ^GUI, id: Widget_ID) -> (rects: [MAX_FREE_PIECES]Rect, count: int) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.rect.w <= 0 || w.rect.h <= 0 { return }

	//* Start with the whole container and cut the children out of it.
	//* The strip of a tab host is not part of it: the strip holds the
	//* tabs, so a panel dropped on it is a tab and not a fill.
	base := w.rect
	if w.type == .Tabs { base = tabs_content_rect(w) }
	if base.w <= 0 || base.h <= 0 { return }

	pieces: [MAX_FREE_PIECES]Rect
	pieces[0] = base
	n := 1

	child := w.first_child
	for child != INVALID_WIDGET_ID && n > 0 {
		c := Widget_Get(g, child)
		if c == nil { break }
		next: [MAX_FREE_PIECES]Rect
		m := 0
		for i in 0 ..< n {
			m += subtract_rect(pieces[i], c.rect, &next, m)
		}
		pieces = next
		n = m
		//* The largest piece first: the pieces that do not fit are
		//* the ones that are cut off, so the big ones are kept.
		sort_pieces_by_size(&pieces, n)
		child = c.next_sibling
	}

	//* Drop the slivers a layout can leave behind, largest piece first.
	kept: [MAX_FREE_PIECES]Rect
	count = 0
	for i in 0 ..< n {
		if pieces[i].w < 1 || pieces[i].h < 1 { continue }
		if count >= MAX_FREE_PIECES { continue }
		area := pieces[i].w * pieces[i].h
		at := count
		for at > 0 && area > kept[at-1].w * kept[at-1].h {
			at -= 1
		}
		for j := count; j > at; j -= 1 {
			kept[j] = kept[j-1]
		}
		kept[at] = pieces[i]
		count += 1
	}
	rects = kept
	return rects, count
}

sort_pieces_by_size :: proc(pieces: ^[MAX_FREE_PIECES]Rect, n: int) {
	for i in 1 ..< n {
		p := pieces[i]
		area := p.w * p.h
		at := i
		for at > 0 && area > pieces[at-1].w * pieces[at-1].h {
			pieces[at] = pieces[at-1]
			at -= 1
		}
		pieces[at] = p
	}
}

//* An empty box or split has all of its space free: a panel dropped
//* into it takes that space, as long as it fits. A panel is not empty
//* space: it is a window, and a drop on it splits it or makes a tab.
plan_fill_empty :: proc(g: ^GUI, plan: ^Dock_Plan, panel, container: Widget_ID) -> bool {
	p := Widget_Get(g, panel)
	c := Widget_Get(g, container)
	if p == nil || c == nil { return false }
	if c.type == .Panel || c.type == .Tabs { return false }
	if c.first_child != INVALID_WIDGET_ID { return false }
	if c.rect.w < p.min_size.x || c.rect.h < p.min_size.y { return false }

	plan.kind = .Fill
	plan.container = container
	plan.preview = c.rect
	return true
}

//* Plans a panel that takes the empty space of a container. It only
//* works when the panel fits in that space, when the container has
//* children that leave a gap, and when the pointer is in that gap: a
//* drop on a panel is a tab, not a fill.
plan_fill :: proc(g: ^GUI, plan: ^Dock_Plan, panel, container: Widget_ID, p: Vec2) -> bool {
	pw := Widget_Get(g, panel)
	c := Widget_Get(g, container)
	if pw == nil || c == nil { return false }
	if c.first_child == INVALID_WIDGET_ID { return false }

	space, count := container_free_space(g, container)
	if count == 0 { return false }

	room := Rect{}
	for i in 0 ..< count {
		if rect_contains(space[i], p.x, p.y) {
			room = space[i]
			break
		}
	}
	if room.w <= 0 || room.h <= 0 { return false }

	if room.w < pw.min_size.x || room.h < pw.min_size.y { return false }

	plan.kind = .Fill
	plan.container = container
	plan.preview = room
	return true
}

//* == Planning ==

//* Works out what dropping `panel` on `container` would do. `p` is
//* where the pointer is, in the space of the container. The plan is
//* what the preview draws and what the drop applies.
dock_plan :: proc(
	g: ^GUI,
	panel, container: Widget_ID,
	zone: Dock_Zone,
	swap: bool,
	p: Vec2,
) -> Dock_Plan {
	plan := Dock_Plan{}
	pw := Widget_Get(g, panel)
	c := Widget_Get(g, container)
	if pw == nil || c == nil { return plan }
	if panel == container { return plan }
	//* A panel cannot be dropped into itself or into anything below it.
	if is_descendant(g, panel, container) { return plan }

	if plan_fill(g, &plan, panel, container, p) { return plan }

	//* The root is the dockspace itself: it cannot host a split or a
	//* tab, but it can hold a panel in its empty space.
	if container == g.root { return plan }

	switch zone {
	case .Left, .Right, .Top, .Bottom:
		plan_split(g, &plan, panel, container, zone)
	case .Center:
		if swap {
			if !plan_swap(g, &plan, panel, container) {
				//* A swap needs two panels that share a parent. When
				//* they do not, the drop falls back to a tab.
				plan = Dock_Plan{}
				plan_tabs(g, &plan, panel, container)
			}
		} else {
			plan_tabs(g, &plan, panel, container)
		}
	case .None:
		return plan
	}
	return plan
}

//* Plans a split drop: the container becomes a split along the axis
//* the zone names, and the panel joins it.
plan_split :: proc(g: ^GUI, plan: ^Dock_Plan, panel, container: Widget_ID, zone: Dock_Zone) {
	c := Widget_Get(g, container)
	p := Widget_Get(g, panel)
	if c == nil || p == nil { return }

	axis := Split_Direction.Vertical
	front := false
	#partial switch zone {
	case .Left:   axis = .Horizontal; front = true
	case .Right:  axis = .Horizontal
	case .Top:    axis = .Vertical;   front = true
	case .Bottom: axis = .Vertical
	case: return
	}

	plan.kind = .Split
	plan.axis = axis
	plan.container = container

	//* An empty container has all of its space free: the panel takes
	//* it, instead of sharing it with a container that holds nothing.
	if plan_fill_empty(g, plan, panel, container) { return }

	//* The children the container already has, without the panel: the
	//* panel is about to move.
	count := 0
	child := c.first_child
	for child != INVALID_WIDGET_ID && count < MAX_DOCK_SLOTS - 1 {
		ch := Widget_Get(g, child)
		if ch == nil { break }
		if child != panel {
			plan.children[count] = child
			plan.weights[count] = ch.weight
			count += 1
		}
		child = ch.next_sibling
	}

	if c.type == .Split && split_direction(c) == axis {
		//* The container already splits along that axis: the panel
		//* becomes one more slice of it.
		plan.create_split = false
		if front {
			for i := count; i > 0; i -= 1 {
				plan.children[i] = plan.children[i-1]
				plan.weights[i] = plan.weights[i-1]
			}
			plan.children[0] = panel
			plan.weights[0] = p.weight
			plan.panel_index = 0
		} else {
			plan.children[count] = panel
			plan.weights[count] = p.weight
			plan.panel_index = count
		}
		count += 1
	} else {
		//* The container is replaced by a new split that holds the
		//* container and the panel. The container keeps its own type
		//* and contents, so nothing inside it is rearranged.
		plan.create_split = true
		container_weight := f32(1)
		if c.weight == 0 { container_weight = 0 }
		if front {
			plan.children[0] = panel
			plan.weights[0] = p.weight
			plan.children[1] = container
			plan.weights[1] = container_weight
			plan.panel_index = 0
		} else {
			plan.children[0] = container
			plan.weights[0] = container_weight
			plan.children[1] = panel
			plan.weights[1] = p.weight
			plan.panel_index = 1
		}
		count = 2
	}
	plan.count = count

	plan_split_rects(g, plan, c.rect)
}

//* Fills in the rects the split's children would occupy. The maths is
//* the same as layout_split, so the preview is the result.
plan_split_rects :: proc(g: ^GUI, plan: ^Dock_Plan, rect: Rect) {
	horizontal := plan.axis == .Horizontal

	total_weight := f32(0)
	total_min := f32(0)
	for i in 0 ..< plan.count {
		ch := Widget_Get(g, plan.children[i])
		if ch == nil { continue }
		total_weight += plan.weights[i]
		total_min += horizontal ? ch.min_size.x : ch.min_size.y
	}
	if total_weight <= 0 { total_weight = 1 }
	available := (horizontal ? rect.w : rect.h) - total_min
	if available < 0 { available = 0 }

	offset := horizontal ? rect.x : rect.y
	for i in 0 ..< plan.count {
		ch := Widget_Get(g, plan.children[i])
		if ch == nil { continue }
		min_size := horizontal ? ch.min_size.x : ch.min_size.y
		size := min_size + available * (plan.weights[i] / total_weight)
		slot := Rect{x = rect.x, y = rect.y, w = rect.w, h = rect.h}
		if horizontal {
			slot = Rect{x = offset, y = rect.y, w = size, h = rect.h}
		} else {
			slot = Rect{x = rect.x, y = offset, w = rect.w, h = size}
		}
		offset += size
		if i == plan.panel_index {
			plan.preview = slot
		} else if plan.other_count < MAX_DOCK_SLOTS {
			plan.others[plan.other_count] = slot
			plan.other_count += 1
		}
	}
}

//* Plans a tab drop: the panel becomes a tab of the target. A target
//* that is already a tab host simply gains a tab; anything else is
//* replaced by a host whose first tab is the target itself.
plan_tabs :: proc(g: ^GUI, plan: ^Dock_Plan, panel, container: Widget_ID) {
	c := Widget_Get(g, container)
	p := Widget_Get(g, panel)
	if c == nil || p == nil { return }

	plan.kind = .Tabs
	plan.container = container

	if plan_fill_empty(g, plan, panel, container) { return }

	if c.type == .Tabs {
		plan.create_tabs = false
		plan.tab_host = container
		plan.tab_bar = tab_bar_rect(c)
		plan.preview = tabs_content_rect(c)

		n := tab_button_rects(g, c, &plan.tab_buttons)
		plan.tab_button_count = n
		child := c.first_child
		for child != INVALID_WIDGET_ID && plan.tab_widget_count < MAX_TABS {
			ch := Widget_Get(g, child)
			if ch == nil { break }
			plan.tab_widgets[plan.tab_widget_count] = child
			plan.tab_widget_count += 1
			child = ch.next_sibling
		}

		//* The panel joins the end of the list, unless it is already
		//* a tab, in which case it keeps its place.
		already := false
		index := 0
		child = c.first_child
		for child != INVALID_WIDGET_ID {
			ch := Widget_Get(g, child)
			if ch == nil { break }
			if child == panel {
				already = true
				break
			}
			index += 1
			child = ch.next_sibling
		}
		if already {
			plan.tab_index = index
			if index < plan.tab_button_count {
				plan.tab_button = plan.tab_buttons[index]
			}
			return
		}

		plan.tab_index = plan.tab_widget_count
		if plan.tab_widget_count < MAX_TABS {
			width := tab_button_width(g, p)
			plan.tab_widgets[plan.tab_widget_count] = panel
			plan.tab_widget_count += 1
			plan.tab_buttons[plan.tab_button_count] = Rect{
				x = plan.tab_bar.x + tab_strip_width(g, c),
				y = plan.tab_bar.y,
				w = width,
				h = plan.tab_bar.h,
			}
			plan.tab_button = plan.tab_buttons[plan.tab_button_count]
			plan.tab_button_count += 1
		}
		return
	}

	//* The container becomes the first tab of a new host, which sits
	//* where the container was.
	plan.create_tabs = true
	plan.tab_host = container
	plan.tab_index = 1
	plan.tab_bar = Rect{x = c.rect.x, y = c.rect.y, w = c.rect.w, h = TAB_BAR_HEIGHT}
	first_width := tab_button_width(g, c)
	plan.tab_widgets[0] = container
	plan.tab_widget_count = 1
	plan.tab_buttons[0] = Rect{x = plan.tab_bar.x, y = plan.tab_bar.y, w = first_width, h = plan.tab_bar.h}
	plan.tab_widgets[1] = panel
	plan.tab_widget_count = 2
	plan.tab_buttons[1] = Rect{
		x = plan.tab_bar.x + first_width,
		y = plan.tab_bar.y,
		w = tab_button_width(g, p),
		h = plan.tab_bar.h,
	}
	plan.tab_button = plan.tab_buttons[1]
	plan.tab_button_count = 2
	plan.preview = Rect{
		x = c.rect.x,
		y = c.rect.y + TAB_BAR_HEIGHT,
		w = c.rect.w,
		h = c.rect.h - TAB_BAR_HEIGHT,
	}
	if plan.preview.h < 0 { plan.preview.h = 0 }
}

//* Plans a swap: the panel takes the target's slot and the target
//* takes the panel's. Only panels that share a parent can swap.
plan_swap :: proc(g: ^GUI, plan: ^Dock_Plan, panel, container: Widget_ID) -> bool {
	p := Widget_Get(g, panel)
	c := Widget_Get(g, container)
	if p == nil || c == nil { return false }
	if p.parent == INVALID_WIDGET_ID || p.parent != c.parent { return false }

	plan.kind = .Swap
	plan.container = container
	plan.swap_panel_parent = p.parent
	plan.swap_panel_index = Widget_Index_Of(g, p.parent, panel)
	plan.swap_host_parent = c.parent
	plan.swap_host_index = Widget_Index_Of(g, c.parent, container)

	plan.preview = c.rect
	if plan.other_count < MAX_DOCK_SLOTS {
		plan.others[plan.other_count] = p.rect
		plan.other_count += 1
	}
	return true
}

//* == Applying ==

//* Takes a widget out of a plan. A plan that names a widget that does
//* not exist any more cannot be applied, so the names of the widgets
//* that are gone are cleared.
dock_plan_forget :: proc(plan: ^Dock_Plan, id: Widget_ID) {
	if plan == nil { return }
	if plan.container == id { plan.container = INVALID_WIDGET_ID }
	if plan.tab_host == id { plan.tab_host = INVALID_WIDGET_ID }
	if plan.swap_panel_parent == id { plan.swap_panel_parent = INVALID_WIDGET_ID }
	if plan.swap_host_parent == id { plan.swap_host_parent = INVALID_WIDGET_ID }
	for &child in plan.children {
		if child == id { child = INVALID_WIDGET_ID }
	}
	for &tab in plan.tab_widgets {
		if tab == id { tab = INVALID_WIDGET_ID }
	}
}

Dock :: proc(g: ^GUI, panel, container: Widget_ID, zone: Dock_Zone) {
	dock_swap := false
	dock_with(g, panel, container, zone, dock_swap)
}

//* Docks `panel` into `container` at `zone`, optionally swapping the two
//* panels instead of making them tabs.
dock_with :: proc(g: ^GUI, panel, container: Widget_ID, zone: Dock_Zone, swap: bool) -> Dock_Plan {
	//* Without a pointer the drop is taken to be in the middle of the
	//* container.
	p := Vec2{}
	if c := Widget_Get(g, container); c != nil {
		p = Vec2{c.rect.x + c.rect.w * 0.5, c.rect.y + c.rect.h * 0.5}
	}
	plan := dock_plan(g, panel, container, zone, swap, p)
	dock_apply(g, panel, plan)
	return plan
}

dock_apply :: proc(g: ^GUI, panel: Widget_ID, plan: Dock_Plan) {
	switch plan.kind {
	case .Split:
		apply_split(g, panel, plan)
	case .Tabs:
		apply_tabs(g, panel, plan)
	case .Swap:
		apply_swap(g, panel, plan)
	case .Fill:
		apply_fill(g, panel, plan)
	case .None:
		return
	}
	invalidate_all(g, Dirty_Flags{.Measure, .Arrange, .Visual, .Hit})
}

apply_fill :: proc(g: ^GUI, panel: Widget_ID, plan: Dock_Plan) {
	container := plan.container
	c := Widget_Get(g, container)
	p := Widget_Get(g, panel)
	if c == nil || p == nil { return }
	space := plan.preview

	Widget_Detach(g, panel)

	//* A panel places its children where they are told to, so the
	//* panel can be put exactly in the empty space. A box or a split
	//* shares its space out among its children, and a child with a
	//* weight of its own takes all that is left over.
	if c.type == .Panel {
		//* The offsets are the edges of the space, measured from the
		//* corner of the container.
		p.anchors = Anchor{0, 0, 0, 0}
		p.offsets = Offset{
			space.x - c.rect.x,
			space.y - c.rect.y,
			space.x + space.w - c.rect.x,
			space.y + space.h - c.rect.y,
		}
		invalidate(g, p.id, Dirty_Flags{.Arrange, .Hit})
	}
	Widget_Attach(g, container, panel)
}

apply_split :: proc(g: ^GUI, panel: Widget_ID, plan: Dock_Plan) {
	container := plan.container
	c := Widget_Get(g, container)
	p := Widget_Get(g, panel)
	if c == nil || p == nil { return }

	if !plan.create_split {
		Widget_Insert_At(g, container, panel, plan.panel_index)
		p.weight = plan.weights[plan.panel_index]
		invalidate(g, p.id, Dirty_Flags{.Arrange})
		return
	}

	parent := c.parent
	anchors := c.anchors
	offsets := c.offsets
	min_size := c.min_size
	weight := c.weight
	grow_h := c.grow_h
	grow_v := c.grow_v
	separation := c.separation
	name := c.name

	//* The panel leaves its old slot first, so the place the container
	//* held is still known afterwards.
	Widget_Detach(g, panel)

	index := Widget_Index_Of(g, parent, container)

	split_id := New_Widget(g, .Split, INVALID_WIDGET_ID, Widget_Opts{name = name})
	split := Widget_Get(g, split_id)
	//* The split takes the container's place: the same layout, but no
	//* style of its own, so the panels keep theirs.
	split.anchors = anchors
	split.offsets = offsets
	split.min_size = min_size
	split.base_min_size = min_size
	split.weight = weight
	split.grow_h = grow_h
	split.grow_v = grow_v
	split.separation = separation
	split.data = Split_Data{direction = plan.axis}
	invalidate(g, split_id, DIRTY_ALL)

	if plan.panel_index == 0 {
		Widget_Attach(g, split_id, panel)
		Widget_Attach(g, split_id, container)
	} else {
		Widget_Attach(g, split_id, container)
		Widget_Attach(g, split_id, panel)
	}
	p.weight = plan.weights[plan.panel_index]
	c.weight = plan.weights[plan.panel_index == 0 ? 1 : 0]
	invalidate(g, p.id, Dirty_Flags{.Arrange})
	invalidate(g, c.id, Dirty_Flags{.Arrange})

	if parent != INVALID_WIDGET_ID {
		Widget_Insert_At(g, parent, split_id, index)
	}
}

apply_tabs :: proc(g: ^GUI, panel: Widget_ID, plan: Dock_Plan) {
	container := plan.container
	c := Widget_Get(g, container)
	p := Widget_Get(g, panel)
	if c == nil || p == nil { return }

	if !plan.create_tabs {
		Widget_Insert_At(g, container, panel, plan.tab_index)
		set_active_tab(g, container, panel)
		return
	}

	parent := c.parent
	anchors := c.anchors
	offsets := c.offsets
	min_size := c.min_size
	weight := c.weight
	grow_h := c.grow_h
	grow_v := c.grow_v
	separation := c.separation
	name := c.name

	Widget_Detach(g, panel)
	index := Widget_Index_Of(g, parent, container)

	host_id := New_Widget(g, .Tabs, INVALID_WIDGET_ID, Widget_Opts{name = name})
	host := Widget_Get(g, host_id)
	host.anchors = anchors
	host.offsets = offsets
	host.min_size = min_size
	host.base_min_size = min_size
	host.weight = weight
	host.grow_h = grow_h
	host.grow_v = grow_v
	host.separation = separation
	invalidate(g, host_id, DIRTY_ALL)

	Widget_Attach(g, host_id, container)
	Widget_Attach(g, host_id, panel)
	if parent != INVALID_WIDGET_ID {
		Widget_Insert_At(g, parent, host_id, index)
	}
	set_active_tab(g, host_id, panel)
}

apply_swap :: proc(g: ^GUI, panel: Widget_ID, plan: Dock_Plan) {
	container := plan.container
	Widget_Detach(g, panel)
	Widget_Detach(g, container)
	Widget_Insert_At(g, plan.swap_panel_parent, container, plan.swap_panel_index)
	Widget_Insert_At(g, plan.swap_host_parent, panel, plan.swap_host_index)
}

set_active_tab :: proc(g: ^GUI, tabs, tab: Widget_ID) {
	w := Widget_Get(g, tabs)
	if w == nil { return }
	if w.type != .Tabs { return }

	index := 0
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil { break }
		if child == tab {
			w.data = Tabs_Data{active = index}
			//* Another tab is showing now: the one that was showing
			//* keeps no geometry, and the one that is showing now
			//* takes the place.
			invalidate(g, w.id, Dirty_Flags{.Measure, .Arrange, .Visual, .Hit})
			return
		}
		index += 1
		child = c.next_sibling
	}
}

//* == Finding the target ==

//* Containers that can take a dropped widget. A plain panel only does
//* when it is draggable: that makes it a window, the way a draggable
//* panel is a window in Dear ImGui. A panel that is only a box for
//* other widgets is left alone.
is_drop_container :: proc(w: ^Widget) -> bool {
	#partial switch w.type {
	case .Split, .Tabs, .VBox, .HBox:
		return true
	case .Panel:
		return w.draggable
	}
	return false
}

//* Finds the deepest container under the pointer that could take the
//* dragged widget. The dragged widget and its subtree are ignored.
find_drop_target :: proc(g: ^GUI, dragged: Widget_ID, p: Vec2) -> Widget_ID {
	return drop_target_in(g, dragged, g.root, p)
}

drop_target_in :: proc(g: ^GUI, dragged, id: Widget_ID, p: Vec2) -> Widget_ID {
	w := Widget_Get(g, id)
	if w == nil { return INVALID_WIDGET_ID }
	if !(.Visible in w.state) { return INVALID_WIDGET_ID }
	if id == dragged || is_descendant(g, dragged, id) { return INVALID_WIDGET_ID }
	//* A tab is not a container: the host that holds it is the one that
	//* takes the drop.
	if is_tab_of_host(g, id) { return INVALID_WIDGET_ID }

	// Children first: the deepest container wins.
	found := INVALID_WIDGET_ID
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil { break }
		if hit := drop_target_in(g, dragged, child, p); hit != INVALID_WIDGET_ID {
			found = hit
		}
		child = c.next_sibling
	}
	if found != INVALID_WIDGET_ID { return found }

	if rect_contains(w.rect, p.x, p.y) && (is_drop_container(w) || id == g.root) {
		return id
	}
	return INVALID_WIDGET_ID
}

//* Finds the widget that would take the dragged panel as a tab: the
//* deepest leaf container under the pointer.
find_tab_host :: proc(g: ^GUI, dragged: Widget_ID, p: Vec2) -> Widget_ID {
	return tab_host_in(g, dragged, g.root, p)
}

tab_host_in :: proc(g: ^GUI, dragged, id: Widget_ID, p: Vec2) -> Widget_ID {
	w := Widget_Get(g, id)
	if w == nil { return INVALID_WIDGET_ID }
	if !(.Visible in w.state) { return INVALID_WIDGET_ID }
	if id == dragged || is_descendant(g, dragged, id) { return INVALID_WIDGET_ID }
	//* A tab is not a host: the host that holds it takes the panel as
	//* one more of its tabs.
	if is_tab_of_host(g, id) { return INVALID_WIDGET_ID }

	found := INVALID_WIDGET_ID
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil { break }
		if hit := tab_host_in(g, dragged, child, p); hit != INVALID_WIDGET_ID {
			found = hit
		}
		child = c.next_sibling
	}
	if found != INVALID_WIDGET_ID { return found }

	if rect_contains(w.rect, p.x, p.y) {
		//* A tab host always takes tabs. A plain panel only does when
		//* it is draggable, which makes it a window.
		if w.type == .Tabs { return id }
		if w.type == .Panel && w.draggable { return id }
	}
	return INVALID_WIDGET_ID
}

//* Finds the tab host whose strip the pointer is over.
find_tab_strip :: proc(g: ^GUI, id: Widget_ID, p: Vec2) -> Widget_ID {
	w := Widget_Get(g, id)
	if w == nil { return INVALID_WIDGET_ID }
	if !(.Visible in w.state) { return INVALID_WIDGET_ID }

	found := INVALID_WIDGET_ID
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil { break }
		if hit := find_tab_strip(g, child, p); hit != INVALID_WIDGET_ID {
			found = hit
		}
		child = c.next_sibling
	}
	if found != INVALID_WIDGET_ID { return found }

	if w.type == .Tabs && rect_contains(tab_bar_rect(w), p.x, p.y) { return id }
	return INVALID_WIDGET_ID
}

//* The tab under a point on the screen: the host whose strip it is
//* over and the tab whose button it is over. The floating panels are
//* on top of the tree, so they are looked at first.
tab_at :: proc(g: ^GUI, global: Vec2) -> (host, tab: Widget_ID, button: Rect) {
	for i := len(g.floats) - 1; i >= 0; i -= 1 {
		f := g.floats[i]
		local := Vec2{global.x - f.pos.x, global.y - f.pos.y}
		host, tab, button = tab_at_in(g, f.widget, local)
		if tab != INVALID_WIDGET_ID { return }
	}
	return tab_at_in(g, g.root, main_window_pos(g, global))
}

//* The tab under a point in the space of a widget's subtree.
tab_at_in :: proc(g: ^GUI, id: Widget_ID, p: Vec2) -> (host, tab: Widget_ID, button: Rect) {
	host = find_tab_strip(g, id, p)
	if host == INVALID_WIDGET_ID { return }
	w := Widget_Get(g, host)
	if w == nil { return }

	rects: [MAX_TABS]Rect
	n := tab_button_rects(g, w, &rects)
	child := w.first_child
	for i in 0 ..< n {
		if rect_contains(rects[i], p.x, p.y) {
			return host, child, rects[i]
		}
		c := Widget_Get(g, child)
		if c == nil { break }
		child = c.next_sibling
	}
	return host, INVALID_WIDGET_ID, {}
}
