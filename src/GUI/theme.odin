package GUI

style_fields_of :: proc(s: ^Style) -> bit_set[Style_Field] {
	if s.set != (bit_set[Style_Field]{}) {return s.set}
	fields: bit_set[Style_Field]
	if s.box.bg_color != (Colour{}) {fields += bit_set[Style_Field]{.BG}}
	if s.box.border_color != ([4]Colour{}) {fields += bit_set[Style_Field]{.Border}}
	if s.box.border_width != ([4]f32{}) {fields += bit_set[Style_Field]{.Border_Width}}
	if s.box.content_margin != ([4]f32{}) {fields += bit_set[Style_Field]{.Padding}}
	if s.box.corner_radius != ([4]f32{}) {fields += bit_set[Style_Field]{.Corner_Radius}}
	if s.box.expand_margin != ([4]f32{}) {fields += bit_set[Style_Field]{.Expand_Margin}}
	if s.box.shadow_color != (Colour{}) ||
	   s.box.shadow_size != 0 ||
	   s.box.shadow_offset != (Vec2{}) {
		fields += bit_set[Style_Field]{.Shadow}
	}
	if text_fields_of(&s.text) != (bit_set[Text_Field]{}) {fields += bit_set[Style_Field]{.Text}}
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
	if .Expand_Margin in fields {
		base.box.expand_margin = over.box.expand_margin
		applied += bit_set[Style_Field]{.Expand_Margin}
	}
	if .Text in fields {
		apply_text_style(&base.text, &over.text)
		applied += bit_set[Style_Field]{.Text}
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
resolved_style :: proc(g: ^GUI, w: ^Widget) -> ^Style {
	if w == nil {return nil}
	if style_cache_is_good(g, w) {
		return &w.style_cache.style
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
	w.style_cache.style = base
	w.style_cache.style_of_widget = w.style
	w.style_cache.default_style = g.default_style
	w.style_cache.use_theme = w.use_theme
	w.style_cache.variation = w.variation
	w.style_cache.epoch = g.style_epoch
	w.style_cache.valid = true
	return &w.style_cache.style
}

//* Checks whether the cached style still matches its inputs and theme epoch.
style_cache_is_good :: proc(g: ^GUI, w: ^Widget) -> bool {
	if w == nil {return false}
	c := &w.style_cache
	if !c.valid {return false}
	if c.epoch != g.style_epoch {return false}
	if c.style_of_widget != w.style {return false}
	if c.default_style != g.default_style {return false}
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
theme_state_style :: proc(g: ^GUI, w: ^Widget, state: Style_State) -> (^Style, bool) {
	if g.theme == nil || !w.use_theme {return nil, false}
	if w.variation != "" {
		if v, found := g.theme.variations[w.variation]; found {
			if s, has := state_style_of(&v.states, state); has {
				w.style_cache.theme_state = s^
				return &w.style_cache.theme_state, true
			}
		}
	}
	if entries, found := theme_entries_for(g, w); found {
		if s, has := state_style_of(&entries.states, state); has {
			w.style_cache.theme_state = s^
			return &w.style_cache.theme_state, true
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
	if g.active == id {return .Pressed}
	if g.hot == id {return .Hovered}
	if g.focused == id {return .Focused}
	return .Normal
}

//* Resolves the base style with state overrides and reports the applied fields.
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
	applied: bit_set[Style_Field]
	if st, ok := theme_state_style(g, w, state); ok {
		w.style_cache.state = base^
		applied = apply_style(&w.style_cache.state, st)
		return &w.style_cache.state, applied
	}
	return base, applied
}

//* Resolves the background colour, using state styles before fallback tinting.
resolved_bg :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) -> Colour {
	state := widget_style_state(g, id, w)
	s, applied := resolved_state_style(g, w, state)
	bg := s.box.bg_color
	#partial switch state {
	case .Pressed:
		if .BG in applied {return bg}
		return Scale_Colour(bg, 0.75)
	case .Hovered:
		if .BG in applied {return bg}
		return Scale_Colour(bg, 1.3)
	}
	return bg
}

//* Resolves text colour from state-specific colours, with disabled fallback tinting.
resolved_text_colour :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) -> Colour {
	state := widget_style_state(g, id, w)
	s, _ := resolved_state_style(g, w, state)
	c := s.text.colour
	#partial switch state {
	case .Disabled:
		if s.text.disabled_colour.a > 0 {return s.text.disabled_colour}
		return Scale_Colour(c, 0.5)
	case .Pressed:
		if s.text.pressed_colour.a > 0 {return s.text.pressed_colour}
	case .Hovered:
		if s.text.hover_colour.a > 0 {return s.text.hover_colour}
	}
	if g.focused == id && (.Enabled in w.state) && s.text.focus_colour.a > 0 {
		return s.text.focus_colour
	}
	return c
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
	entries := theme_class_entries_of(t, name)
	entries.styleboxes[THEME_NORMAL] = style.box
	entries.text = style.text
	theme_put_class_entries(t, name, entries)
	theme_changed(t)
}

//* Sets a named stylebox for a widget class.
theme_set_class_stylebox :: proc(t: ^Theme, name: string, item: string, box: StyleBox) {
	entries := theme_class_entries_of(t, name)
	entries.styleboxes[item] = box
	theme_put_class_entries(t, name, entries)
	theme_changed(t)
}

//* Sets a named colour for a widget class.
Theme_Set_Class_Color :: proc(t: ^Theme, name: string, item: string, colour: Colour) {
	entries := theme_class_entries_of(t, name)
	entries.colors[item] = colour
	theme_put_class_entries(t, name, entries)
	theme_changed(t)
}

//* Sets a named constant for a widget class.
Theme_Set_Class_Constant :: proc(t: ^Theme, name: string, item: string, value: f32) {
	entries := theme_class_entries_of(t, name)
	entries.constants[item] = value
	theme_put_class_entries(t, name, entries)
	theme_changed(t)
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
	theme_changed(t)
}

//* Sets the base style for a widget type.
Theme_Set_Type :: proc(t: ^Theme, widget_type: Widget_Type, style: Style) {
	entries := theme_entries_of(t, widget_type)
	entries.styleboxes[THEME_NORMAL] = style.box
	entries.text = style.text
	theme_put_entries(t, widget_type, entries)
	theme_changed(t)
}

//* Sets a named stylebox for a widget type.
theme_set_stylebox :: proc(t: ^Theme, widget_type: Widget_Type, name: string, box: StyleBox) {
	entries := theme_entries_of(t, widget_type)
	entries.styleboxes[name] = box
	theme_put_entries(t, widget_type, entries)
	theme_changed(t)
}

//* Sets a named colour for a widget type.
theme_set_color :: proc(t: ^Theme, widget_type: Widget_Type, name: string, colour: Colour) {
	entries := theme_entries_of(t, widget_type)
	entries.colors[name] = colour
	theme_put_entries(t, widget_type, entries)
	theme_changed(t)
}

//* Sets a named constant for a widget type.
theme_set_constant :: proc(t: ^Theme, widget_type: Widget_Type, name: string, value: f32) {
	entries := theme_entries_of(t, widget_type)
	entries.constants[name] = value
	theme_put_entries(t, widget_type, entries)
	theme_changed(t)
}

//* Sets a named font for a widget type.
theme_set_font :: proc(t: ^Theme, widget_type: Widget_Type, name: string, font: Font_ID) {
	entries := theme_entries_of(t, widget_type)
	entries.fonts[name] = font
	theme_put_entries(t, widget_type, entries)
	theme_changed(t)
}

//* Sets a named font size for a widget type.
theme_set_font_size :: proc(t: ^Theme, widget_type: Widget_Type, name: string, size: f32) {
	entries := theme_entries_of(t, widget_type)
	entries.font_sizes[name] = size
	theme_put_entries(t, widget_type, entries)
	theme_changed(t)
}

//* Sets a named icon for a widget type.
theme_set_icon :: proc(t: ^Theme, widget_type: Widget_Type, name: string, icon: Texture_ID) {
	entries := theme_entries_of(t, widget_type)
	entries.icons[name] = icon
	theme_put_entries(t, widget_type, entries)
	theme_changed(t)
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
	theme_changed(t)
}

//* Adds a named variation whose style overrides its base widget type.
Theme_Add_Variation :: proc(t: ^Theme, name: string, widget_type: Widget_Type, style: Style) {
	v := theme_variation_of(t, name)
	v.of = widget_type
	s := style
	apply_style(&v.style, &s)
	t.variations[name] = v
	theme_changed(t)
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
	theme_changed(t)
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
	theme_changed(t)
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
	theme_changed(t)
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

//* Advances the theme epoch and invalidates styles, layout, and drawing.
theme_changed :: proc(t: ^Theme) {
	if t == nil {return}
	g := t.owner
	if g == nil {return}
	g.style_epoch += 1
	style_cache_drop(g)
	invalidate_theme(g)
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
		set = s.set,
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