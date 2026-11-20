package Core
style_fields_of :: proc(s: ^Style) -> bit_set[Style_Field] {
	if s.set != (bit_set[Style_Field]{}) {return s.set}
	fields: bit_set[Style_Field]
	if s.box.bg_color != (Colour{}) {fields += bit_set[Style_Field]{.BG}}
	if s.box.border_color != ([4]Colour{}) {fields += bit_set[Style_Field]{.Border}}
	if s.box.border_width != ([4]f32{}) {fields += bit_set[Style_Field]{.Border_Width}}
	if s.box.content_margin != ([4]f32{}) {fields += bit_set[Style_Field]{.Padding}}
	if s.box.corner_radius != ([4]f32{}) {fields += bit_set[Style_Field]{.Corner_Radius}}
	if s.box.expand_margin != ([4]f32{}) {fields += bit_set[Style_Field]{.Expand_Margin}}
	if s.box.backdrop_blur > 0 {fields += bit_set[Style_Field]{.Backdrop_Blur}}
	if s.box.optics.refraction != 0 {fields += bit_set[Style_Field]{.Optics_Refraction}}
	if s.box.optics.dispersion != 0 {fields += bit_set[Style_Field]{.Optics_Dispersion}}
	if s.box.optics.fresnel != 0 {fields += bit_set[Style_Field]{.Optics_Fresnel}}
	if s.box.optics.saturation != 0 {fields += bit_set[Style_Field]{.Optics_Saturation}}
	if s.box.shadow_color != (Colour{}) ||
	   s.box.shadow_size != 0 ||
	   s.box.shadow_offset != (Vec2{}) {
		fields += bit_set[Style_Field]{.Shadow}
	}
	if s.box.shadow_spread != 0 {
		fields += bit_set[Style_Field]{.Shadow_Spread}
	}
	if s.box.shadow_inset {
		fields += bit_set[Style_Field]{.Shadow_Inset}
	}
	if text_fields_of(&s.text) != (bit_set[Text_Field]{}) {fields += bit_set[Style_Field]{.Text}}
	if s.transition.duration > 0 || s.transition.easing != .Linear {
		fields += bit_set[Style_Field]{.Transition}
	}
	return fields
}

//* The fields explicitly set in a text style, or inferred from non-default values.
text_fields_of :: proc(ts: ^Text_Style) -> bit_set[Text_Field] {
	if ts.set != (bit_set[Text_Field]{}) {return ts.set}
	fields: bit_set[Text_Field]
	if ts.family != INVALID_FONT_FAMILY_ID {fields += bit_set[Text_Field]{.Family}}
	if ts.size != 0 {fields += bit_set[Text_Field]{.Size}}
	if ts.colour.a != 0 {fields += bit_set[Text_Field]{.Colour}}
	if ts.hover_colour.a != 0 {fields += bit_set[Text_Field]{.Hover_Colour}}
	if ts.pressed_colour.a != 0 {fields += bit_set[Text_Field]{.Pressed_Colour}}
	if ts.disabled_colour.a != 0 {fields += bit_set[Text_Field]{.Disabled_Colour}}
	if ts.focus_colour.a != 0 {fields += bit_set[Text_Field]{.Focus_Colour}}
	if ts.align != .Left {fields += bit_set[Text_Field]{.Align}}
	if ts.valign != .Top {fields += bit_set[Text_Field]{.VAlign}}
	if ts.wrap != .Off {fields += bit_set[Text_Field]{.Wrap}}
	if ts.spacing != 0 {fields += bit_set[Text_Field]{.Spacing}}
	if ts.transform != .None {fields += bit_set[Text_Field]{.Transform}}
	if ts.overrun != .None {fields += bit_set[Text_Field]{.Overrun}}
	if ts.clip {fields += bit_set[Text_Field]{.Clip}}
	if ts.outline_colour.a != 0 {fields += bit_set[Text_Field]{.Outline_Colour}}
	if ts.outline_size != 0 {fields += bit_set[Text_Field]{.Outline_Size}}
	if ts.shadow_colour.a != 0 {fields += bit_set[Text_Field]{.Shadow_Colour}}
	if ts.shadow_offset != (Vec2{}) {fields += bit_set[Text_Field]{.Shadow_Offset}}
	return fields
}

//* Applies the set fields from `over` to `base` and returns the fields applied.
apply_style :: proc(base: ^Style, over: ^Style) -> bit_set[Style_Field] {
	applied: bit_set[Style_Field]
	fields := style_fields_of(over)
	if .BG in fields {
		base.box.bg_color = over.box.bg_color
		applied += bit_set[Style_Field]{.BG}
	}
	if .Border in fields {
		base.box.border_color = over.box.border_color
		applied += bit_set[Style_Field]{.Border}
	}
	if .Border_Width in fields {
		base.box.border_width = over.box.border_width
		applied += bit_set[Style_Field]{.Border_Width}
	}
	if .Padding in fields {
		base.box.content_margin = over.box.content_margin
		applied += bit_set[Style_Field]{.Padding}
	}
	if .Corner_Radius in fields {
		base.box.corner_radius = over.box.corner_radius
		applied += bit_set[Style_Field]{.Corner_Radius}
	}
	if .Shadow in fields {
		base.box.shadow_color = over.box.shadow_color
		base.box.shadow_size = over.box.shadow_size
		base.box.shadow_offset = over.box.shadow_offset
		applied += bit_set[Style_Field]{.Shadow}
	}
	if .Shadow_Spread in fields {
		base.box.shadow_spread = over.box.shadow_spread
		applied += bit_set[Style_Field]{.Shadow_Spread}
	}
	if .Shadow_Inset in fields {
		base.box.shadow_inset = over.box.shadow_inset
		applied += bit_set[Style_Field]{.Shadow_Inset}
	}
	if .Expand_Margin in fields {
		base.box.expand_margin = over.box.expand_margin
		applied += bit_set[Style_Field]{.Expand_Margin}
	}
	if .Backdrop_Blur in fields {
		base.box.backdrop_blur = over.box.backdrop_blur
		applied += bit_set[Style_Field]{.Backdrop_Blur}
	}
	if .Optics_Refraction in fields {
		base.box.optics.refraction = over.box.optics.refraction
		applied += bit_set[Style_Field]{.Optics_Refraction}
	}
	if .Optics_Dispersion in fields {
		base.box.optics.dispersion = over.box.optics.dispersion
		applied += bit_set[Style_Field]{.Optics_Dispersion}
	}
	if .Optics_Fresnel in fields {
		base.box.optics.fresnel = over.box.optics.fresnel
		applied += bit_set[Style_Field]{.Optics_Fresnel}
	}
	if .Optics_Saturation in fields {
		base.box.optics.saturation = over.box.optics.saturation
		applied += bit_set[Style_Field]{.Optics_Saturation}
	}
	if .Text in fields {
		apply_text_style(&base.text, &over.text)
		applied += bit_set[Style_Field]{.Text}
	}
	if .Transition in fields {
		base.transition = over.transition
		applied += bit_set[Style_Field]{.Transition}
	}
	return applied
}

//* Applies the set text fields from `over` to `base`.
apply_text_style :: proc(base: ^Text_Style, over: ^Text_Style) {
	fields := text_fields_of(over)
	if .Family in fields {base.family = over.family}
	if .Size in fields {base.size = over.size}
	if .Colour in fields {base.colour = over.colour}
	if .Hover_Colour in fields {base.hover_colour = over.hover_colour}
	if .Pressed_Colour in fields {base.pressed_colour = over.pressed_colour}
	if .Disabled_Colour in fields {base.disabled_colour = over.disabled_colour}
	if .Focus_Colour in fields {base.focus_colour = over.focus_colour}
	if .Align in fields {base.align = over.align}
	if .VAlign in fields {base.valign = over.valign}
	if .Wrap in fields {base.wrap = over.wrap}
	if .Spacing in fields {base.spacing = over.spacing}
	if .Transform in fields {base.transform = over.transform}
	if .Overrun in fields {base.overrun = over.overrun}
	if .Clip in fields {base.clip = over.clip}
	if .Outline_Colour in fields {base.outline_colour = over.outline_colour}
	if .Outline_Size in fields {base.outline_size = over.outline_size}
	if .Shadow_Colour in fields {base.shadow_colour = over.shadow_colour}
	if .Shadow_Offset in fields {base.shadow_offset = over.shadow_offset}
}

//* Resolves a widget's style from defaults, class, theme, and local overrides.
//* == The style pool ==
//* The resolved styles of the widgets are interned here, so a widget
//* only keeps the ids of its styles. The chunks give the styles a
//* stable address while the pool grows.

Style_Pool_Intern :: proc(g: ^GUI, style: Style) -> Style_ID {
	if g == nil { return INVALID_STYLE_ID }
	if g.style_pool.ids == nil { g.style_pool.ids = make(map[Style]Style_ID) }
	if id, ok := g.style_pool.ids[style]; ok { return id }

	index := g.style_pool.count
	chunk := index / STYLE_POOL_CHUNK
	if chunk >= len(g.style_pool.chunks) {
		append(&g.style_pool.chunks, make([]Style, STYLE_POOL_CHUNK))
	}
	g.style_pool.chunks[chunk][index % STYLE_POOL_CHUNK] = style
	g.style_pool.count += 1
	id := Style_ID(index + 1)
	g.style_pool.ids[style] = id
	return id
}

Style_Pool_Get :: proc(g: ^GUI, id: Style_ID) -> ^Style {
	if g == nil { return nil }
	index := int(id) - 1
	if index < 0 || index >= g.style_pool.count { return &g.style_pool.empty }
	return &g.style_pool.chunks[index / STYLE_POOL_CHUNK][index % STYLE_POOL_CHUNK]
}

Style_Pool_Destroy :: proc(g: ^GUI) {
	if g == nil { return }
	for chunk in g.style_pool.chunks { delete(chunk) }
	delete(g.style_pool.chunks)
	if g.style_pool.ids != nil { delete(g.style_pool.ids) }
	g.style_pool = {}
}

resolved_style :: proc(g: ^GUI, w: ^Widget) -> ^Style {
	if w == nil {return nil}
	if style_cache_is_good(g, w) {
		return Style_Pool_Get(g, w.style_cache.style)
	}
	base := g.default_style
	if c, ok := class_get(g, w.class); ok {
		apply_style(&base, &c.kind.style)
	}
	if g.theme != nil && w.use_theme {
		themed := theme_style(g, w)
		apply_style(&base, &themed)
	}
	apply_style(&base, &w.style)
	w.style_cache.style = Style_Pool_Intern(g, base)
	w.style_cache.style_of_widget = w.style
	w.style_cache.use_theme = w.use_theme
	w.style_cache.variation = w.variation
	w.style_cache.epoch = g.style_epoch
	w.style_cache.valid = true
	return Style_Pool_Get(g, w.style_cache.style)
}

//* Checks whether the cached style still matches its inputs and theme epoch.
style_cache_is_good :: proc(g: ^GUI, w: ^Widget) -> bool {
	if w == nil {return false}
	c := &w.style_cache
	if !c.valid {return false}
	if c.epoch != g.style_epoch {return false}
	if c.style_of_widget != w.style {return false}
	if c.use_theme != w.use_theme {return false}
	if c.variation != w.variation {return false}
	return true
}

//* Invalidates every widget's resolved style cache.
style_cache_drop :: proc(g: ^GUI) {
	if g == nil {return}
	for w in g.widgets {
		if w == nil {continue}
		w.style_cache.valid = false
	}
}

//* Finds theme entries by widget class first, then by widget type.
theme_entries_for :: proc(g: ^GUI, w: ^Widget) -> (Theme_Type, bool) {
	if g == nil || g.theme == nil || w == nil {return {}, false}
	if c, ok := class_get(g, w.class); ok {
		name := c.name
		if name == "" {name = c.kind.theme_name}
		if name != "" {
			if entries, found := g.theme.classes[name]; found {return entries, true}
		}
	}
	if entries, found := g.theme.types[w.type]; found {return entries, true}
	return {}, false
}

//* Resolves the base theme style, variation overrides, and theme text defaults.
theme_style :: proc(g: ^GUI, w: ^Widget) -> Style {
	base := Style{}
	if g.theme == nil {return base}
	if entries, ok := theme_entries_for(g, w); ok {
		if box, has := entries.styleboxes[THEME_NORMAL]; has {base.box = box}
		base.text = entries.text
		base.transition = entries.transition
	}
	if w.variation != "" {
		if v, ok := g.theme.variations[w.variation]; ok {
			apply_style(&base, &v.style)
		}
	}
	if base.text.family == INVALID_FONT_FAMILY_ID {base.text.family = g.theme.family}
	if base.text.size == 0 {base.text.size = g.theme.size}
	return base
}

//* Resolves a state style, preferring the widget's variation over its class or type.
theme_state_style :: proc(g: ^GUI, w: ^Widget, state: Style_State, out: ^Style) -> (^Style, bool) {
	if g.theme == nil || !w.use_theme {return nil, false}
	if w.variation != "" {
		if v, found := g.theme.variations[w.variation]; found {
			if s, has := state_style_of(&v.states, state); has {
				out^ = s^
				return out, true
			}
		}
	}
	if entries, found := theme_entries_for(g, w); found {
		if s, has := state_style_of(&entries.states, state); has {
			out^ = s^
			return out, true
		}
	}
	return nil, false
}

//* Returns the style assigned to a state, excluding the normal state.
state_style_of :: proc(states: ^State_Styles, state: Style_State) -> (^Style, bool) {
	switch state {
	case .Hovered:
		return &states.hover, true
	case .Pressed:
		return &states.pressed, true
	case .Disabled:
		return &states.disabled, true
	case .Focused:
		return &states.focus, true
	case .Normal:
		return nil, false
	}
	return nil, false
}

//* Determines the widget's visual state from enabled, active, hover, and focus status.
widget_style_state :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) -> Style_State {
	if !(.Enabled in w.state) {return .Disabled}
	if w.interactive {
		if g.active == id {return .Pressed}
		if g.hot == id {return .Hovered}
	}
	if g.focused == id {return .Focused}
	return .Normal
}

//* Resolves the base style with state overrides, fallbacks and the state blend.
resolved_state_style :: proc(
	g: ^GUI,
	w: ^Widget,
	state: Style_State,
) -> (
	^Style,
	bit_set[Style_Field],
) {
	base := resolved_style(g, w)
	if base == nil {return nil, {}}
	target := base^
	applied: bit_set[Style_Field]
	theme_state: Style
	if st, ok := theme_state_style(g, w, state, &theme_state); ok {
		applied = apply_style(&target, st)
	}
	style_state_fallbacks(g, w, state, &target, applied)
	if t := w.style_cache.transition; t != nil {
		style_transition_sync(t, target, state, g.style_epoch)
		t.current = style_transition_current(t)
		return &t.current, applied
	} else if target.transition.duration > 0 {
		t = new(Style_Transition_State)
		style_transition_sync(t, target, state, g.style_epoch)
		w.style_cache.transition = t
		t.current = style_transition_current(t)
		return &t.current, applied
	}
	w.style_cache.state = Style_Pool_Intern(g, target)
	return Style_Pool_Get(g, w.style_cache.state), applied
}

style_state_fallbacks :: proc(
	g: ^GUI,
	w: ^Widget,
	state: Style_State,
	style: ^Style,
	applied: bit_set[Style_Field],
) {
	#partial switch state {
	case .Pressed:
		if .BG not_in applied {style.box.bg_color = Scale_Colour(style.box.bg_color, 0.75)}
	case .Hovered:
		if .BG not_in applied {style.box.bg_color = Scale_Colour(style.box.bg_color, 1.3)}
	}

	c := style.text.colour
	#partial switch state {
	case .Disabled:
		if style.text.disabled_colour.a > 0 {
			c = style.text.disabled_colour
		} else {
			c = Scale_Colour(c, 0.5)
		}
	case .Pressed:
		if style.text.pressed_colour.a > 0 {c = style.text.pressed_colour}
	case .Hovered:
		if style.text.hover_colour.a > 0 {c = style.text.hover_colour}
	}
	if g.focused == w.id && (.Enabled in w.state) && style.text.focus_colour.a > 0 {
		c = style.text.focus_colour
	}
	style.text.colour = c
}

//* Resolves the background colour of the widget's current state.
resolved_bg :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) -> Colour {
	state := widget_style_state(g, id, w)
	s, _ := resolved_state_style(g, w, state)
	if s == nil {return {}}
	return s.box.bg_color
}

//* Resolves the text colour of the widget's current state.
resolved_text_colour :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) -> Colour {
	state := widget_style_state(g, id, w)
	s, _ := resolved_state_style(g, w, state)
	if s == nil {return {}}
	return s.text.colour
}

//* Looks up a named colour, preferring the widget's variation over its class or type.
theme_color :: proc(g: ^GUI, w: ^Widget, name: string) -> Colour {
	if g.theme == nil {return {}}
	if w.variation != "" {
		if v, ok := g.theme.variations[w.variation]; ok {
			if c, has := v.colors[name]; has {return c}
		}
	}
	if entries, ok := theme_entries_for(g, w); ok {
		if c, has := entries.colors[name]; has {return c}
	}
	return {}
}

//* Looks up a named constant, preferring the widget's variation over its class or type.
theme_constant :: proc(g: ^GUI, w: ^Widget, name: string) -> f32 {
	if g.theme == nil {return 0}
	if w.variation != "" {
		if v, ok := g.theme.variations[w.variation]; ok {
			if c, has := v.constants[name]; has {return c}
		}
	}
	if entries, ok := theme_entries_for(g, w); ok {
		if c, has := entries.constants[name]; has {return c}
	}
	return 0
}

//* Looks up a named constant and says whether the theme holds it. A theme
//* that sets a constant to zero means zero, not "not set".
theme_constant_ok :: proc(g: ^GUI, w: ^Widget, name: string) -> (f32, bool) {
	if g.theme == nil {return 0, false}
	if w.variation != "" {
		if v, ok := g.theme.variations[w.variation]; ok {
			if c, has := v.constants[name]; has {return c, true}
		}
	}
	if entries, ok := theme_entries_for(g, w); ok {
		if c, has := entries.constants[name]; has {return c, true}
	}
	return 0, false
}

//* Looks up a named icon in the widget's class or type theme entries.
theme_icon :: proc(g: ^GUI, w: ^Widget, name: string) -> Texture_ID {
	if g.theme == nil {return INVALID_TEXTURE_ID}
	if entries, ok := theme_entries_for(g, w); ok {
		if i, has := entries.icons[name]; has {return i}
	}
	return INVALID_TEXTURE_ID
}

//* Looks up a named font in the widget's class or type theme entries.
theme_font :: proc(g: ^GUI, w: ^Widget, name: string) -> Font_ID {
	if g.theme == nil {return INVALID_FONT_ID}
	if entries, ok := theme_entries_for(g, w); ok {
		if f, has := entries.fonts[name]; has {return f}
	}
	return INVALID_FONT_ID
}

//* Looks up a named font size in the widget's class or type theme entries.
theme_font_size :: proc(g: ^GUI, w: ^Widget, name: string) -> f32 {
	if g.theme == nil {return 0}
	if entries, ok := theme_entries_for(g, w); ok {
		if s, has := entries.font_sizes[name]; has {return s}
	}
	return 0
}

//* THEMES
THEME_NORMAL :: "normal"

//* Creates an empty theme with initialized entry maps.
Theme_Make :: proc() -> ^Theme {
	t := new(Theme)
	t.types = make(map[Widget_Type]Theme_Type)
	t.classes = make(map[string]Theme_Type)
	t.variations = make(map[string]Variation)
	return t
}

//* Returns the entries for a widget type, creating empty maps when absent.
theme_entries_of :: proc(t: ^Theme, widget_type: Widget_Type) -> Theme_Type {
	entries, ok := t.types[widget_type]
	if !ok {
		entries = Theme_Type {
			styleboxes = make(map[string]StyleBox),
			colors     = make(map[string]Colour),
			constants  = make(map[string]f32),
			fonts      = make(map[string]Font_ID),
			font_sizes = make(map[string]f32),
			icons      = make(map[string]Texture_ID),
		}
	}
	return entries
}

//* Stores the entries for a widget type.
theme_put_entries :: proc(t: ^Theme, widget_type: Widget_Type, entries: Theme_Type) {
	t.types[widget_type] = entries
}

//* Returns the entries for a widget class, creating empty maps when absent.
theme_class_entries_of :: proc(t: ^Theme, name: string) -> Theme_Type {
	entries, ok := t.classes[name]
	if !ok {
		entries = Theme_Type {
			styleboxes = make(map[string]StyleBox),
			colors     = make(map[string]Colour),
			constants  = make(map[string]f32),
			fonts      = make(map[string]Font_ID),
			font_sizes = make(map[string]f32),
			icons      = make(map[string]Texture_ID),
		}
	}
	return entries
}

//* Stores the entries for a widget class.
theme_put_class_entries :: proc(t: ^Theme, name: string, entries: Theme_Type) {
	t.classes[name] = entries
}

//* Sets the base style for a named widget class.
Theme_Set_Class :: proc(t: ^Theme, name: string, style: Style) {
	old := Style{}
	if entries, found := t.classes[name]; found {old = theme_entry_style(&entries)}
	entries := theme_class_entries_of(t, name)
	entries.styleboxes[THEME_NORMAL] = style.box
	entries.text = style.text
	entries.transition = style.transition
	theme_put_class_entries(t, name, entries)
	flags := Dirty_Flags{.Visual}
	if style_size_of(old) != style_size_of(style) {flags += Dirty_Flags{.Measure}}
	theme_changed_target(t, Theme_Target{kind = .Class, name = name}, flags)
}

//* Sets a named stylebox for a widget class.
theme_set_class_stylebox :: proc(t: ^Theme, name: string, item: string, box: StyleBox) {
	entries := theme_class_entries_of(t, name)
	old, has := entries.styleboxes[item]
	measured := box.content_margin != (has ? old.content_margin : [4]f32{})
	entries.styleboxes[item] = box
	theme_put_class_entries(t, name, entries)
	flags := Dirty_Flags{.Visual}
	if measured {flags += Dirty_Flags{.Measure}}
	theme_changed_target(t, Theme_Target{kind = .Class, name = name}, flags)
}

//* Sets a named colour for a widget class.
Theme_Set_Class_Color :: proc(t: ^Theme, name: string, item: string, colour: Colour) {
	entries := theme_class_entries_of(t, name)
	entries.colors[item] = colour
	theme_put_class_entries(t, name, entries)
	theme_changed_target(t, Theme_Target{kind = .Class, name = name}, Dirty_Flags{.Visual})
}

//* Sets a named constant for a widget class.
Theme_Set_Class_Constant :: proc(t: ^Theme, name: string, item: string, value: f32) {
	entries := theme_class_entries_of(t, name)
	entries.constants[item] = value
	theme_put_class_entries(t, name, entries)
	theme_changed_target(
		t,
		Theme_Target{kind = .Class, name = name},
		Dirty_Flags{.Measure, .Visual},
	)
}

//* Sets the style override for a widget class state.
Theme_Set_Class_State :: proc(t: ^Theme, name: string, state: Style_State, style: Style) {
	entries := theme_class_entries_of(t, name)
	states := entries.states
	switch state {
	case .Hovered:
		states.hover = style
	case .Pressed:
		states.pressed = style
	case .Disabled:
		states.disabled = style
	case .Focused:
		states.focus = style
	case .Normal:
		return
	}
	entries.states = states
	theme_put_class_entries(t, name, entries)
	theme_changed_target(t, Theme_Target{kind = .Class, name = name}, Dirty_Flags{.Visual})
}

//* Sets the base style for a widget type.
Theme_Set_Type :: proc(t: ^Theme, widget_type: Widget_Type, style: Style) {
	old := Style{}
	if entries, found := t.types[widget_type]; found {old = theme_entry_style(&entries)}
	entries := theme_entries_of(t, widget_type)
	entries.styleboxes[THEME_NORMAL] = style.box
	entries.text = style.text
	entries.transition = style.transition
	theme_put_entries(t, widget_type, entries)
	flags := Dirty_Flags{.Visual}
	if style_size_of(old) != style_size_of(style) {flags += Dirty_Flags{.Measure}}
	theme_changed_target(t, Theme_Target{kind = .Type, widget_type = widget_type}, flags)
}

//* Sets a named stylebox for a widget type.
theme_set_stylebox :: proc(t: ^Theme, widget_type: Widget_Type, name: string, box: StyleBox) {
	entries := theme_entries_of(t, widget_type)
	old, has := entries.styleboxes[name]
	measured := box.content_margin != (has ? old.content_margin : [4]f32{})
	entries.styleboxes[name] = box
	theme_put_entries(t, widget_type, entries)
	flags := Dirty_Flags{.Visual}
	if measured {flags += Dirty_Flags{.Measure}}
	theme_changed_target(t, Theme_Target{kind = .Type, widget_type = widget_type}, flags)
}

//* Sets a named colour for a widget type.
theme_set_color :: proc(t: ^Theme, widget_type: Widget_Type, name: string, colour: Colour) {
	entries := theme_entries_of(t, widget_type)
	entries.colors[name] = colour
	theme_put_entries(t, widget_type, entries)
	theme_changed_target(t, Theme_Target{kind = .Type, widget_type = widget_type}, Dirty_Flags{.Visual})
}

//* Sets a named constant for a widget type.
theme_set_constant :: proc(t: ^Theme, widget_type: Widget_Type, name: string, value: f32) {
	entries := theme_entries_of(t, widget_type)
	entries.constants[name] = value
	theme_put_entries(t, widget_type, entries)
	theme_changed_target(
		t,
		Theme_Target{kind = .Type, widget_type = widget_type},
		Dirty_Flags{.Measure, .Visual},
	)
}

//* Sets a named font for a widget type.
theme_set_font :: proc(t: ^Theme, widget_type: Widget_Type, name: string, font: Font_ID) {
	entries := theme_entries_of(t, widget_type)
	entries.fonts[name] = font
	theme_put_entries(t, widget_type, entries)
	theme_changed_target(
		t,
		Theme_Target{kind = .Type, widget_type = widget_type},
		Dirty_Flags{.Measure, .Visual},
	)
}

//* Sets a named font size for a widget type.
theme_set_font_size :: proc(t: ^Theme, widget_type: Widget_Type, name: string, size: f32) {
	entries := theme_entries_of(t, widget_type)
	entries.font_sizes[name] = size
	theme_put_entries(t, widget_type, entries)
	theme_changed_target(
		t,
		Theme_Target{kind = .Type, widget_type = widget_type},
		Dirty_Flags{.Measure, .Visual},
	)
}

//* Sets a named icon for a widget type.
theme_set_icon :: proc(t: ^Theme, widget_type: Widget_Type, name: string, icon: Texture_ID) {
	entries := theme_entries_of(t, widget_type)
	entries.icons[name] = icon
	theme_put_entries(t, widget_type, entries)
	theme_changed_target(t, Theme_Target{kind = .Type, widget_type = widget_type}, Dirty_Flags{.Visual})
}

//* Retrieves a stylebox by name from a widget type.
Theme_Get_Stylebox :: proc(t: ^Theme, widget_type: Widget_Type, name: string) -> (StyleBox, bool) {
	if t == nil {return StyleBox{}, false}
	entries, found := t.types[widget_type]
	if !found {return StyleBox{}, false}
	box, has := entries.styleboxes[name]
	if !has {return StyleBox{}, false}
	return box, true
}

//* Retrieves a constant by name from a widget type or one of its variations.
Theme_Get_Constant :: proc(t: ^Theme, widget_type: Widget_Type, name: string) -> (f32, bool) {
	if t == nil {return 0, false}
	entries, found := t.types[widget_type]
	if found {
		if value, has := entries.constants[name]; has {return value, true}
	}
	for _, v in t.variations {
		if v.of != widget_type {continue}
		if value, has := v.constants[name]; has {return value, true}
	}
	return 0, false
}

//* Sets the style override for a widget type state.
Theme_Set_State :: proc(t: ^Theme, widget_type: Widget_Type, state: Style_State, style: Style) {
	entries := theme_entries_of(t, widget_type)
	states := entries.states
	switch state {
	case .Hovered:
		states.hover = style
	case .Pressed:
		states.pressed = style
	case .Disabled:
		states.disabled = style
	case .Focused:
		states.focus = style
	case .Normal:
		return
	}
	entries.states = states
	theme_put_entries(t, widget_type, entries)
	theme_changed_target(t, Theme_Target{kind = .Type, widget_type = widget_type}, Dirty_Flags{.Visual})
}

//* Adds a named variation whose style overrides its base widget type.
Theme_Add_Variation :: proc(t: ^Theme, name: string, widget_type: Widget_Type, style: Style) {
	v := theme_variation_of(t, name)
	old := v.style
	v.of = widget_type
	s := style
	apply_style(&v.style, &s)
	t.variations[name] = v
	flags := Dirty_Flags{.Visual}
	if style_size_of(old) != style_size_of(v.style) {flags += Dirty_Flags{.Measure}}
	theme_changed_target(t, Theme_Target{kind = .Variation, name = name}, flags)
}

//* Sets the state style override for a named variation.
Theme_Set_Variation_State :: proc(
	t: ^Theme,
	name: string,
	widget_type: Widget_Type,
	state: Style_State,
	style: Style,
) {
	v := theme_variation_of(t, name)
	v.of = widget_type
	switch state {
	case .Hovered:
		v.states.hover = style
	case .Pressed:
		v.states.pressed = style
	case .Disabled:
		v.states.disabled = style
	case .Focused:
		v.states.focus = style
	case .Normal:
		return
	}
	t.variations[name] = v
	theme_changed_target(t, Theme_Target{kind = .Variation, name = name}, Dirty_Flags{.Visual})
}

//* Sets a named colour on a variation.
theme_set_variation_color :: proc(
	t: ^Theme,
	name: string,
	widget_type: Widget_Type,
	item: string,
	colour: Colour,
) {
	v := theme_variation_of(t, name)
	v.of = widget_type
	if v.colors == nil {v.colors = make(map[string]Colour)}
	v.colors[item] = colour
	t.variations[name] = v
	theme_changed_target(t, Theme_Target{kind = .Variation, name = name}, Dirty_Flags{.Visual})
}

//* Sets a named constant on a variation.
theme_set_variation_constant :: proc(
	t: ^Theme,
	name: string,
	widget_type: Widget_Type,
	item: string,
	value: f32,
) {
	v := theme_variation_of(t, name)
	v.of = widget_type
	if v.constants == nil {v.constants = make(map[string]f32)}
	v.constants[item] = value
	t.variations[name] = v
	theme_changed_target(
		t,
		Theme_Target{kind = .Variation, name = name},
		Dirty_Flags{.Measure, .Visual},
	)
}

//* Returns a variation by name, initializing its maps when absent.
theme_variation_of :: proc(t: ^Theme, name: string) -> Variation {
	v, ok := t.variations[name]
	if !ok {
		v.colors = make(map[string]Colour)
		v.constants = make(map[string]f32)
	}
	return v
}

//* Sets the theme's default font family and invalidates dependent layout.
Theme_Set_Family :: proc(t: ^Theme, family: Font_Family_ID) {
	if t == nil {return}
	if t.family == family {return}
	t.family = family
	theme_changed(t)
}

//* Sets the theme's default text size and invalidates dependent layout.
Theme_Set_Size :: proc(t: ^Theme, size: f32) {
	if t == nil {return}
	if t.size == size {return}
	t.size = size
	theme_changed(t)
}

//* Advances the theme epoch and invalidates every themed widget.
theme_changed :: proc(t: ^Theme) {
	theme_changed_global(t)
}


theme_changed_global :: proc(t: ^Theme) {
	if t == nil {return}
	g := t.owner
	if g == nil {return}
	g.style_epoch += 1
	style_cache_drop(g)
	invalidate_theme(g)
}

Theme_Target_Kind :: enum {
	All,
	Type,
	Class,
	Variation,
}

Theme_Target :: struct {
	kind:        Theme_Target_Kind,
	widget_type: Widget_Type,
	name:        string,
}

theme_target_matches :: proc(g: ^GUI, w: ^Widget, target: Theme_Target) -> bool {
	if g == nil || w == nil || !w.use_theme {return false}
	#partial switch target.kind {
	case .Type:
		return w.type == target.widget_type
	case .Class:
		name := theme_class_name(g, w)
		return name != "" && name == target.name
	case .Variation:
		return target.name != "" && w.variation == target.name
	case .All:
		return true
	}
	return false
}

theme_class_name :: proc(g: ^GUI, w: ^Widget) -> string {
	if c, ok := class_get(g, w.class); ok {
		if c.name != "" {return c.name}
		return c.kind.theme_name
	}
	return ""
}

theme_entry_style :: proc(entries: ^Theme_Type) -> Style {
	s := Style{text = entries.text, transition = entries.transition}
	if box, has := entries.styleboxes[THEME_NORMAL]; has {s.box = box}
	return s
}

theme_changed_target :: proc(t: ^Theme, target: Theme_Target, flags: Dirty_Flags) {
	if t == nil {return}

	g := t.owner
	if g == nil {return}
	if target.kind == .All {
		theme_changed_global(t)
		return
	}
	all := flags + Dirty_Flags{.Theme}
	//* The change is global even when it matches no widget of this tree,
	//* so the frame cannot be reduced to a later visual change.
	draw_invalidate(g)
	for w in g.widgets {
		if w == nil || !w.use_theme {continue}
		if !theme_target_matches(g, w, target) {continue}
		w.style_cache.valid = false
		if t := w.style_cache.transition; t != nil {t.initialized = false}
		invalidate_widget(g, w, all)
	}
}

//* Transfers theme ownership to the GUI, freeing the previously assigned theme.
GUI_Set_Theme :: proc(g: ^GUI, t: ^Theme) {
	if g == nil {return}
	if g.theme != nil && g.theme != t {
		g.theme.owner = nil
		theme_destroy(g.theme)
	}
	g.theme = t
	if t != nil {t.owner = g}
	g.style_epoch += 1
	style_cache_drop(g)
	invalidate_theme(g)
}

//* Sets the default style and invalidates measurement only when size-affecting fields change.
GUI_Set_Default_Style :: proc(g: ^GUI, style: Style) {
	if g == nil {return}
	if g.default_style == style {return}
	measured := style_size_of(g.default_style) != style_size_of(style)
	g.default_style = style
	g.style_epoch += 1
	style_cache_drop(g)
	flags := Dirty_Flags{.Visual}
	if measured {flags += Dirty_Flags{.Measure}}
	invalidate_all(g, flags)
}

//* Extracts the style fields that can affect widget measurement.
style_size_of :: proc(s: Style) -> Style {
	return Style {
		box = StyleBox{content_margin = s.box.content_margin},
		text = text_style_size_of(s.text),
	}
}

//* Frees the theme and all maps it owns.
theme_destroy :: proc(t: ^Theme) {
	if t == nil {return}
	t.owner = nil
	for _, entries in t.types {
		delete(entries.styleboxes)
		delete(entries.colors)
		delete(entries.constants)
		delete(entries.fonts)
		delete(entries.font_sizes)
		delete(entries.icons)
	}
	delete(t.types)
	for _, entries in t.classes {
		delete(entries.styleboxes)
		delete(entries.colors)
		delete(entries.constants)
		delete(entries.fonts)
		delete(entries.font_sizes)
		delete(entries.icons)
	}
	delete(t.classes)
	for _, v in t.variations {
		delete(v.colors)
		delete(v.constants)
	}
	delete(t.variations)
	free(cast(rawptr)t)
}


//* == Style transitions ==
style_colour_lerp :: proc(a, b: Colour, t: f32) -> Colour {
	return Colour {
		r = a.r + (b.r - a.r) * t,
		g = a.g + (b.g - a.g) * t,
		b = a.b + (b.b - a.b) * t,
		a = a.a + (b.a - a.a) * t,
	}
}

style_side_lerp :: proc(a, b: [4]f32, t: f32) -> [4]f32 {
	out: [4]f32
	for i in 0 ..< 4 {
		out[i] = a[i] + (b[i] - a[i]) * t
	}
	return out
}

style_corner_colour_lerp :: proc(a, b: [4]Colour, t: f32) -> [4]Colour {
	out: [4]Colour
	for i in 0 ..< 4 {
		out[i] = style_colour_lerp(a[i], b[i], t)
	}
	return out
}

style_vec2_lerp :: proc(a, b: Vec2, t: f32) -> Vec2 {
	return Vec2 {
		x = a.x + (b.x - a.x) * t,
		y = a.y + (b.y - a.y) * t,
	}
}

style_text_lerp :: proc(a, b: Text_Style, t: f32) -> Text_Style {
	out := b
	out.size = a.size + (b.size - a.size) * t
	out.spacing = a.spacing + (b.spacing - a.spacing) * t
	out.colour = style_colour_lerp(a.colour, b.colour, t)
	out.hover_colour = style_colour_lerp(a.hover_colour, b.hover_colour, t)
	out.pressed_colour = style_colour_lerp(a.pressed_colour, b.pressed_colour, t)
	out.disabled_colour = style_colour_lerp(a.disabled_colour, b.disabled_colour, t)
	out.focus_colour = style_colour_lerp(a.focus_colour, b.focus_colour, t)
	out.outline_colour = style_colour_lerp(a.outline_colour, b.outline_colour, t)
	out.outline_size = a.outline_size + (b.outline_size - a.outline_size) * t
	out.shadow_colour = style_colour_lerp(a.shadow_colour, b.shadow_colour, t)
	out.shadow_offset = style_vec2_lerp(a.shadow_offset, b.shadow_offset, t)
	return out
}

style_transition_blend :: proc(a, b: Style, t: f32) -> Style {
	out := b
	out.box.bg_color = style_colour_lerp(a.box.bg_color, b.box.bg_color, t)
	out.box.border_width = style_side_lerp(a.box.border_width, b.box.border_width, t)
	out.box.border_color = style_corner_colour_lerp(a.box.border_color, b.box.border_color, t)
	out.box.corner_radius = style_side_lerp(a.box.corner_radius, b.box.corner_radius, t)
	out.box.content_margin = style_side_lerp(a.box.content_margin, b.box.content_margin, t)
	out.box.expand_margin = style_side_lerp(a.box.expand_margin, b.box.expand_margin, t)
	out.box.shadow_color = style_colour_lerp(a.box.shadow_color, b.box.shadow_color, t)
	out.box.shadow_size = a.box.shadow_size + (b.box.shadow_size - a.box.shadow_size) * t
	out.box.shadow_offset = style_vec2_lerp(a.box.shadow_offset, b.box.shadow_offset, t)
	out.box.shadow_spread = a.box.shadow_spread + (b.box.shadow_spread - a.box.shadow_spread) * t
	out.box.shadow_inset = t >= 0.5 ? b.box.shadow_inset : a.box.shadow_inset
	out.box.backdrop_blur = a.box.backdrop_blur + (b.box.backdrop_blur - a.box.backdrop_blur) * t
	out.box.optics.refraction = a.box.optics.refraction + (b.box.optics.refraction - a.box.optics.refraction) * t
	out.box.optics.dispersion = a.box.optics.dispersion + (b.box.optics.dispersion - a.box.optics.dispersion) * t
	out.box.optics.fresnel = a.box.optics.fresnel + (b.box.optics.fresnel - a.box.optics.fresnel) * t
	out.box.optics.saturation = a.box.optics.saturation + (b.box.optics.saturation - a.box.optics.saturation) * t
	out.text = style_text_lerp(a.text, b.text, t)
	return out
}

style_transition_current :: proc(t: ^Style_Transition_State) -> Style {
	if !t.active || t.duration <= 0 {
		return t.target
	}
	progress := clamp(t.elapsed / t.duration, 0, 1)
	return style_transition_blend(t.from, t.target, easing_apply(t.easing, progress))
}

style_transition_sync :: proc(
	t: ^Style_Transition_State,
	target: Style,
	state: Style_State,
	epoch: int,
) {
	duration := target.transition.duration
	easing := target.transition.easing

	if !t.initialized || t.epoch != epoch {
		t.from = target
		t.target = target
		t.state = state
		t.elapsed = 0
		t.duration = duration
		t.easing = easing
		t.active = false
		t.initialized = true
		t.epoch = epoch
		return
	}

	if t.state != state {
		current := style_transition_current(t)
		t.from = current
		t.target = target
		t.state = state
		t.elapsed = 0
		t.duration = duration
		t.easing = easing
		t.active = duration > 0 && current != target
		return
	}

	if t.target != target {
		current := style_transition_current(t)
		if duration > 0 && current != target {
			t.from = current
			t.elapsed = 0
			t.duration = duration
			t.easing = easing
			t.active = true
		} else {
			t.from = target
			t.duration = duration
			t.easing = easing
			t.active = false
		}
		t.target = target
		return
	}

	t.duration = duration
	t.easing = easing
	if !t.active {
		t.from = target
	}
}

style_transition_tick :: proc(g: ^GUI, w: ^Widget, dt: f32) {
	if g == nil || w == nil {return}
	t := w.style_cache.transition
	if t == nil || !t.active {return}
	if dt <= 0 {return}
	t.elapsed += dt
	if t.elapsed >= t.duration {
		t.elapsed = t.duration
		t.active = false
	}
	invalidate(g, w.id, Dirty_Flags{.Visual})
}

Style_Transitions_Update :: proc(g: ^GUI, dt: f32) {
	if g == nil {return}
	for w in g.widgets {
		if w == nil {continue}
		style_transition_tick(g, w, dt)
	}
}

Widget_Style_Transition_Active :: proc(g: ^GUI, id: Widget_ID) -> bool {
	if g == nil {return false}
	w := Widget_Get(g, id)
	if w == nil {return false}
	return w.style_cache.transition != nil && w.style_cache.transition.active
}
