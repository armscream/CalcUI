package GUI

TOAST_DURATION :: 3.0

toast_colour :: proc(kind: Toast_Kind) -> Colour {
	#partial switch kind {
	case .Info:
		return RGBA(0.16, 0.42, 0.78, 1)
	case .Success:
		return RGBA(0.14, 0.52, 0.28, 1)
	case .Warning:
		return RGBA(0.80, 0.56, 0.10, 1)
	case .Error:
		return RGBA(0.72, 0.20, 0.20, 1)
	}
	return RGBA(0.16, 0.42, 0.78, 1)
}

toast_ink :: proc(kind: Toast_Kind) -> Colour {
	#partial switch kind {
	case .Warning:
		return RGBA(0.10, 0.09, 0.06, 1)
	}
	return RGBA(0.98, 0.98, 0.99, 1)
}

Toast_Opts :: struct {
	Base_Opts: Base_Opts,
	text:      string,
	kind:      Toast_Kind,
	duration:  f32,
}

Make_Toast :: proc(g: ^GUI, parent: Widget_ID, opts: Toast_Opts) -> Widget_ID {
	kind_register(g, .Toast, toast_kind())
	base := base_widget_opts(opts.Base_Opts)
	no_offsets := Offset{}
	if base.preset == .Fill && opts.Base_Opts.offsets == no_offsets {
		base.preset = .Bottom_Right
		base.offsets = Offset {
			left   = -336,
			top    = -64,
			right  = -16,
			bottom = -16,
		}
	}
	id := New_Widget(g, .Toast, parent, base)
	w := Widget_Get(g, id)
	duration := opts.duration
	if duration <= 0 {duration = TOAST_DURATION}
	w.data = Toast_Data {
		text      = opts.text,
		kind      = opts.kind,
		duration  = duration,
		remaining = duration,
	}
	w.focus_mode = .None
	w.mouse_filter = .Ignore
	w.state -= Widget_State{.Visible}
	return id
}

//* Shows a toast for the requested duration, or the default duration.
Toast_Show :: proc(g: ^GUI, id: Widget_ID, text: string, kind: Toast_Kind, duration: f32) {
	w := Widget_Get(g, id)
	if w == nil {return}
	time := duration
	if time <= 0 {time = TOAST_DURATION}
	#partial switch &d in w.data {
	case Toast_Data:
		d.text = text
		d.kind = kind
		d.duration = time
		d.remaining = time
	}
	w.state += Widget_State{.Visible}
	invalidate(g, id, Dirty_Flags{.Visual, .Hit})
}

Toast_Is_Visible :: proc(g: ^GUI, id: Widget_ID) -> bool {
	w := Widget_Get(g, id)
	if w == nil {return false}
	return .Visible in w.state
}

toast_kind :: proc() -> Widget_Kind {
	return Widget_Kind {
		draw = draw_toast,
		update = update_toast,
		click = click_toast,
		style = Style{box = StyleBox{content_margin = {10, 8, 10, 8}}},
		theme_name = "Toast",
	}
}

toast_data :: proc(g: ^GUI, id: Widget_ID) -> ^Toast_Data {
	w := Widget_Get(g, id)
	if w == nil {return nil}
	#partial switch &d in w.data {
	case Toast_Data:
		return &d
	}
	return nil
}

update_toast :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, dt: f32) {
	if !(.Visible in w.state) {return}
	#partial switch &d in w.data {
	case Toast_Data:
		d.remaining -= dt
		if d.remaining <= 0 {
			d.remaining = 0
			w.state -= Widget_State{.Visible}
		}
	}
}

click_toast :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {}

draw_toast :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	if !(.Visible in w.state) {return}
	style := resolved_style(g, w)
	#partial switch d in w.data {
	case Toast_Data:
		draw_rect(g, w.rect, toast_colour(d.kind), 6)
		draw_text(g, style.text, d.text, content, toast_ink(d.kind))
	}
}