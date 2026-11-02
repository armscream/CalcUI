package GUI

import "core:log"
import "core:strings"
import virt "core:mem/virtual"

widget_get :: proc(g: ^GUI, id: Widget_ID) -> ^Widget {
	idx := int(id) - 1
	if idx < 0 || idx >= len(g.widgets) { return nil }
	return g.widgets[idx]
}

//* Creates a widget. Everything is in `opts`; afterwards a widget is
//* mutated by writing to the struct returned by widget_get.
widget :: proc(g: ^GUI, type: Widget_Type, parent: Widget_ID, opts: Widget_Opts = {}) -> Widget_ID {
	w, err := virt.new(&g.arena, Widget)
	if err != nil {
		log.panicf("widget allocation failed: %v", err)
	}
	//* Arena memory is not zeroed, so start from a clean slate.
	w^ = Widget{}

	w.id = Widget_ID(len(g.widgets) + 1)
	w.type = type
	w.name = opts.name
	w.parent = INVALID_WIDGET_ID
	w.first_child = INVALID_WIDGET_ID
	w.last_child = INVALID_WIDGET_ID
	w.prev_sibling = INVALID_WIDGET_ID
	w.next_sibling = INVALID_WIDGET_ID

	w.anchors = anchor_of(opts.preset, opts.anchors)
	w.offsets = opts.offsets
	w.min_size = opts.min_size
	w.weight = opts.weight
	if w.weight == 0 && !opts.fixed { w.weight = 1 }
	w.separation = opts.separation
	if w.separation == 0 { w.separation = 4 }
	w.draggable = opts.draggable
	//* A widget that has to grow past its minimum size grows right and
	//* down, like Godot's default grow direction.
	w.grow_h = .End
	w.grow_v = .End
	w.style = opts.style
	w.use_theme = opts.use_theme
	w.variation = opts.variation
	w.state = Widget_State{.Visible, .Enabled}
	if opts.hidden { w.state -= Widget_State{.Visible} }

	#partial switch type {
	case .Button:
		w.data = Button_Data{text = opts.text, on_click = opts.on_click}
	case .Label:
		w.data = Label_Data{text = opts.text}
	case .Split:
		w.data = Split_Data{direction = opts.split}
	case .Tabs:
		w.data = Tabs_Data{active = 0}
	case .TextInput:
		//* The buffer is owned by the widget so it can be edited in
		//* place without leaking the old string.
		w.data = Text_Input_Data{text = strings.clone(opts.text)}
	case:
		w.data = None_Data{}
	}

	append(&g.widgets, w)
	if parent != INVALID_WIDGET_ID {
		widget_attach(g, parent, w.id)
	}
	g.layout_dirty = true
	return w.id
}

//* Unlinks a widget from its parent and siblings. The widget keeps its
//* identity, so every reference to it stays valid — this is the core
//* primitive behind docking.
widget_detach :: proc(g: ^GUI, child: Widget_ID) {
	w := widget_get(g, child)
	if w == nil { return }

	if w.parent != INVALID_WIDGET_ID {
		if p := widget_get(g, w.parent); p != nil {
			if p.first_child == child { p.first_child = w.next_sibling }
			if p.last_child == child { p.last_child = w.prev_sibling }
		}
	}
	if w.prev_sibling != INVALID_WIDGET_ID {
		if s := widget_get(g, w.prev_sibling); s != nil { s.next_sibling = w.next_sibling }
	}
	if w.next_sibling != INVALID_WIDGET_ID {
		if s := widget_get(g, w.next_sibling); s != nil { s.prev_sibling = w.prev_sibling }
	}

	w.parent = INVALID_WIDGET_ID
	w.prev_sibling = INVALID_WIDGET_ID
	w.next_sibling = INVALID_WIDGET_ID
	//* A panel that changes place starts out with the size the layout
	//* gives it: the size it was pulled to belonged to the old place.
	w.manual_w = false
	w.manual_h = false
	g.layout_dirty = true
}

//* Moves a widget under a new parent, preserving its identity.
widget_attach :: proc(g: ^GUI, parent, child: Widget_ID) {
	if parent == INVALID_WIDGET_ID { return }
	widget_detach(g, child)

	w := widget_get(g, child)
	p := widget_get(g, parent)
	if w == nil || p == nil { return }

	w.parent = parent
	w.prev_sibling = p.last_child
	w.next_sibling = INVALID_WIDGET_ID
	if p.last_child != INVALID_WIDGET_ID {
		if s := widget_get(g, p.last_child); s != nil { s.next_sibling = child }
	} else {
		p.first_child = child
	}
	p.last_child = child
	g.layout_dirty = true
}

//* Moves a widget under a new parent at a given place in the child
//* list. Docking uses this to put a panel in front of the others.
widget_insert_at :: proc(g: ^GUI, parent, child: Widget_ID, index: int) {
	if parent == INVALID_WIDGET_ID { return }
	widget_detach(g, child)

	w := widget_get(g, child)
	p := widget_get(g, parent)
	if w == nil || p == nil { return }
	at := index
	if at < 0 { at = 0 }

	//* The child that currently sits at `at`.
	prev := INVALID_WIDGET_ID
	next := p.first_child
	i := 0
	for next != INVALID_WIDGET_ID && i < at {
		c := widget_get(g, next)
		if c == nil { break }
		prev = next
		next = c.next_sibling
		i += 1
	}

	w.parent = parent
	w.prev_sibling = prev
	w.next_sibling = next
	if prev != INVALID_WIDGET_ID {
		if s := widget_get(g, prev); s != nil { s.next_sibling = child }
	} else {
		p.first_child = child
	}
	if next != INVALID_WIDGET_ID {
		if s := widget_get(g, next); s != nil { s.prev_sibling = child }
	} else {
		p.last_child = child
	}
	g.layout_dirty = true
}

//* The place a child holds in its parent's child list, or -1.
widget_index_of :: proc(g: ^GUI, parent, child: Widget_ID) -> int {
	p := widget_get(g, parent)
	if p == nil { return -1 }
	index := 0
	cur := p.first_child
	for cur != INVALID_WIDGET_ID {
		if cur == child { return index }
		c := widget_get(g, cur)
		if c == nil { break }
		cur = c.next_sibling
		index += 1
	}
	return -1
}

//* Number of children of a widget.
widget_child_count :: proc(g: ^GUI, id: Widget_ID) -> int {
	w := widget_get(g, id)
	if w == nil { return 0 }
	count := 0
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := widget_get(g, child)
		if c == nil { break }
		count += 1
		child = c.next_sibling
	}
	return count
}

//* Allocates a texture id for the backend's texture table.
alloc_texture :: proc(g: ^GUI) -> Texture_ID {
	tex := g.next_texture
	g.next_texture += 1
	return tex
}
