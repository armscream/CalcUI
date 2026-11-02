package GUI

//* == The theme ==
//* A theme holds the look of every kind of widget: a style for each
//* type, a style for each state a widget can be in, and named
//* variations of a type. A widget that takes the theme starts from the
//* style of its type and puts its own style on top of it.
//
//* A style is sparse: the fields in its `set` are the ones it changes.
//* When `set` is empty the fields that are set are worked out from
//* their values, so a style only has to name what it changes.

//* The fields of a style that are set. A style that has no set of its
//* own says which fields it changes by their values.
style_fields_of :: proc(s: ^Style) -> bit_set[Style_Field] {
	if s.set != (bit_set[Style_Field]{}) { return s.set }
	fields: bit_set[Style_Field]
	if s.bg != (Colour{}) { fields += bit_set[Style_Field]{.BG} }
	if s.border != (Colour{}) { fields += bit_set[Style_Field]{.Border} }
	if s.border_width != 0 { fields += bit_set[Style_Field]{.Border_Width} }
	if s.padding != ([4]f32{}) { fields += bit_set[Style_Field]{.Padding} }
	if text_fields_of(&s.text) != (bit_set[Text_Field]{}) { fields += bit_set[Style_Field]{.Text} }
	return fields
}

//* The fields of a text style that are set.
text_fields_of :: proc(ts: ^Text_Style) -> bit_set[Text_Field] {
	if ts.set != (bit_set[Text_Field]{}) { return ts.set }
	fields: bit_set[Text_Field]
	if ts.family != INVALID_FONT_FAMILY_ID { fields += bit_set[Text_Field]{.Family} }
	if ts.size != 0 { fields += bit_set[Text_Field]{.Size} }
	if ts.colour.a != 0 { fields += bit_set[Text_Field]{.Colour} }
	if ts.hover_colour.a != 0 { fields += bit_set[Text_Field]{.Hover_Colour} }
	if ts.pressed_colour.a != 0 { fields += bit_set[Text_Field]{.Pressed_Colour} }
	if ts.disabled_colour.a != 0 { fields += bit_set[Text_Field]{.Disabled_Colour} }
	if ts.focus_colour.a != 0 { fields += bit_set[Text_Field]{.Focus_Colour} }
	if ts.align != .Left { fields += bit_set[Text_Field]{.Align} }
	if ts.valign != .Top { fields += bit_set[Text_Field]{.VAlign} }
	if ts.wrap != .Off { fields += bit_set[Text_Field]{.Wrap} }
	if ts.spacing != 0 { fields += bit_set[Text_Field]{.Spacing} }
	if ts.transform != .None { fields += bit_set[Text_Field]{.Transform} }
	if ts.overrun != .None { fields += bit_set[Text_Field]{.Overrun} }
	if ts.clip { fields += bit_set[Text_Field]{.Clip} }
	if ts.outline_colour.a != 0 { fields += bit_set[Text_Field]{.Outline_Colour} }
	if ts.outline_size != 0 { fields += bit_set[Text_Field]{.Outline_Size} }
	if ts.shadow_colour.a != 0 { fields += bit_set[Text_Field]{.Shadow_Colour} }
	if ts.shadow_offset != (Vec2{}) { fields += bit_set[Text_Field]{.Shadow_Offset} }
	return fields
}

//* Puts `over` on top of `base`: the fields that are set in `over` are
//* taken from it, and the rest are left alone. The fields that were
//* applied are returned.
apply_style :: proc(base: ^Style, over: ^Style) -> bit_set[Style_Field] {
	applied: bit_set[Style_Field]
	fields := style_fields_of(over)
	if .BG in fields {
		base.bg = over.bg
		applied += bit_set[Style_Field]{.BG}
	}
	if .Border in fields {
		base.border = over.border
		applied += bit_set[Style_Field]{.Border}
	}
	if .Border_Width in fields {
		base.border_width = over.border_width
		applied += bit_set[Style_Field]{.Border_Width}
	}
	if .Padding in fields {
		base.padding = over.padding
		applied += bit_set[Style_Field]{.Padding}
	}
	if .Text in fields {
		apply_text_style(&base.text, &over.text)
		applied += bit_set[Style_Field]{.Text}
	}
	return applied
}

//* Puts `over` on top of `base`.
apply_text_style :: proc(base: ^Text_Style, over: ^Text_Style) {
	fields := text_fields_of(over)
	if .Family in fields { base.family = over.family }
	if .Size in fields { base.size = over.size }
	if .Colour in fields { base.colour = over.colour }
	if .Hover_Colour in fields { base.hover_colour = over.hover_colour }
	if .Pressed_Colour in fields { base.pressed_colour = over.pressed_colour }
	if .Disabled_Colour in fields { base.disabled_colour = over.disabled_colour }
	if .Focus_Colour in fields { base.focus_colour = over.focus_colour }
	if .Align in fields { base.align = over.align }
	if .VAlign in fields { base.valign = over.valign }
	if .Wrap in fields { base.wrap = over.wrap }
	if .Spacing in fields { base.spacing = over.spacing }
	if .Transform in fields { base.transform = over.transform }
	if .Overrun in fields { base.overrun = over.overrun }
	if .Clip in fields { base.clip = over.clip }
	if .Outline_Colour in fields { base.outline_colour = over.outline_colour }
	if .Outline_Size in fields { base.outline_size = over.outline_size }
	if .Shadow_Colour in fields { base.shadow_colour = over.shadow_colour }
	if .Shadow_Offset in fields { base.shadow_offset = over.shadow_offset }
}

//* == Resolution ==

//* The style of a widget: the theme's style for its type, with the
//* widget's own style on top of it. Only a widget that takes the
//* theme gets the theme's style; the others keep the GUI's own.
resolved_style :: proc(g: ^GUI, w: ^Widget) -> Style {
	base := g.default_style
	if g.theme != nil && w.use_theme {
		base = theme_style(g, w)
	}
	apply_style(&base, &w.style)
	return base
}

//* The theme's style for a widget: the style of its type, with the
//* style of its variation on top of it. The theme's own typeface and
//* size are the base of them all.
theme_style :: proc(g: ^GUI, w: ^Widget) -> Style {
	base := Style{}
	if g.theme == nil { return base }
	if s, ok := g.theme.types[w.type]; ok { base = s }
	if w.variation != "" {
		if v, ok := g.theme.variations[w.variation]; ok {
			apply_style(&base, &v.style)
		}
	}
	if base.text.family == INVALID_FONT_FAMILY_ID { base.text.family = g.theme.family }
	if base.text.size == 0 { base.text.size = g.theme.size }
	return base
}

//* The theme's style for a state of a widget. A variation has its own
//* states, and they take the place of the ones of the type.
theme_state_style :: proc(g: ^GUI, w: ^Widget, state: Style_State) -> (Style, bool) {
	if g.theme == nil || !w.use_theme { return {}, false }
	if w.variation != "" {
		if v, found := g.theme.variations[w.variation]; found {
			if s, has := state_style_of(v.states, state); has { return s, true }
		}
	}
	if states, found := g.theme.states[w.type]; found {
		if s, has := state_style_of(states, state); has { return s, true }
	}
	return {}, false
}

//* The style of one state.
state_style_of :: proc(states: State_Styles, state: Style_State) -> (Style, bool) {
	switch state {
	case .Hovered:  return states.hover, true
	case .Pressed:  return states.pressed, true
	case .Disabled: return states.disabled, true
	case .Focused:  return states.focus, true
	case .Normal:   return {}, false
	}
	return {}, false
}

//* The state a widget is in, for the theme's sake.
widget_style_state :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) -> Style_State {
	if !(.Enabled in w.state) { return .Disabled }
	if g.active == id { return .Pressed }
	if g.hot == id { return .Hovered }
	if g.focused == id { return .Focused }
	return .Normal
}

//* The style of a widget in the state it is in: its own style with the
//* theme's entry for that state on top.
resolved_state_style :: proc(g: ^GUI, w: ^Widget, state: Style_State) -> (Style, bit_set[Style_Field]) {
	s := resolved_style(g, w)
	applied: bit_set[Style_Field]
	if st, ok := theme_state_style(g, w, state); ok {
		applied = apply_style(&s, &st)
	}
	return s, applied
}

//* The background of a widget, in the state it is in. A theme that has
//* a background for the state wins; without one the background is
//* brightened under the pointer and darkened while it is pressed.
resolved_bg :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) -> Colour {
	state := widget_style_state(g, id, w)
	s, applied := resolved_state_style(g, w, state)
	bg := s.bg
	#partial switch state {
	case .Pressed:
		if .BG in applied { return bg }
		return scale_colour(bg, 0.75)
	case .Hovered:
		if .BG in applied { return bg }
		return scale_colour(bg, 1.3)
	}
	return bg
}

//* The colour of the text of a widget, in the state it is in.
resolved_text_colour :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) -> Colour {
	state := widget_style_state(g, id, w)
	s, _ := resolved_state_style(g, w, state)
	c := s.text.colour
	#partial switch state {
	case .Disabled:
		if s.text.disabled_colour.a > 0 { return s.text.disabled_colour }
		return scale_colour(c, 0.5)
	case .Pressed:
		if s.text.pressed_colour.a > 0 { return s.text.pressed_colour }
	case .Hovered:
		if s.text.hover_colour.a > 0 { return s.text.hover_colour }
	}
	//* The focus of a widget has its own colour, but a widget that is
	//* not enabled does not get it.
	if g.focused == id && (.Enabled in w.state) && s.text.focus_colour.a > 0 {
		return s.text.focus_colour
	}
	return c
}

//* == Making a theme ==

//* A theme with nothing in it.
theme_make :: proc() -> ^Theme {
	t := new(Theme)
	t.types = make(map[Widget_Type]Style)
	t.states = make(map[Widget_Type]State_Styles)
	t.variations = make(map[string]Variation)
	return t
}

//* The style of a widget type.
theme_set_type :: proc(t: ^Theme, widget_type: Widget_Type, style: Style) {
	t.types[widget_type] = style
}

//* The style of a state of a widget type.
theme_set_state :: proc(t: ^Theme, widget_type: Widget_Type, state: Style_State, style: Style) {
	states := t.states[widget_type]
	switch state {
	case .Hovered:  states.hover = style
	case .Pressed:  states.pressed = style
	case .Disabled: states.disabled = style
	case .Focused:  states.focus = style
	case .Normal:   return
	}
	t.states[widget_type] = states
}

//* A named variation of a widget type. Its style is applied over the
//* style of the type it varies from.
theme_add_variation :: proc(t: ^Theme, name: string, widget_type: Widget_Type, style: Style) {
	v := t.variations[name]
	v.of = widget_type
	s := style
	apply_style(&v.style, &s)
	t.variations[name] = v
}

//* The style of a state of a named variation.
theme_set_variation_state :: proc(
	t: ^Theme,
	name: string,
	widget_type: Widget_Type,
	state: Style_State,
	style: Style,
) {
	v := t.variations[name]
	v.of = widget_type
	switch state {
	case .Hovered:  v.states.hover = style
	case .Pressed:  v.states.pressed = style
	case .Disabled: v.states.disabled = style
	case .Focused:  v.states.focus = style
	case .Normal:   return
	}
	t.variations[name] = v
}

//* Puts a theme on the GUI. The GUI takes the theme over: the one it
//* replaces is freed, and the theme on the GUI is freed when the GUI
//* shuts down.
gui_set_theme :: proc(g: ^GUI, t: ^Theme) {
	if g.theme != nil && g.theme != t {
		theme_destroy(g.theme)
	}
	g.theme = t
	g.layout_dirty = true
}

//* Frees a theme and everything in it.
theme_destroy :: proc(t: ^Theme) {
	if t == nil { return }
	delete(t.types)
	delete(t.states)
	delete(t.variations)
	free(cast(rawptr) t)
}
