package Core

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
	t := &w.style_cache.transition
	if !t.active {return}
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
	return w.style_cache.transition.active
}
