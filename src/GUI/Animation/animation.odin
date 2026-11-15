package Animation

import "core:log"
import "core:math"

import Core "../Core"

GUI :: Core.GUI
Widget :: Core.Widget
Widget_ID :: Core.Widget_ID
INVALID_WIDGET_ID :: Core.INVALID_WIDGET_ID
Style :: Core.Style
Style_Field :: Core.Style_Field
Dirty_Flags :: Core.Dirty_Flags
Vec2 :: Core.Vec2
Colour :: Core.Colour
Easing :: Core.Easing
Animation_Value :: Core.Animation_Value
Animation_Value_Kind :: Core.Animation_Value_Kind
Animation_Property :: Core.Animation_Property
Animation_ID :: Core.Animation_ID
INVALID_ANIMATION_ID :: Core.INVALID_ANIMATION_ID
Animation_State :: Core.Animation_State
Animation_Desc :: Core.Animation_Desc
Tween :: Core.Tween

easing_apply :: proc(easing: Easing, t: f32) -> f32 {
	x := clamp(t, 0, 1)
	switch easing {
	case .Linear:
		return x
	case .In_Quad:
		return x * x
	case .Out_Quad:
		y := 1 - x
		return 1 - y * y
	case .In_Out_Quad:
		if x < 0.5 {return 2 * x * x}
		y := -2 * x + 2
		return 1 - y * y * 0.5
	case .In_Cubic:
		return x * x * x
	case .Out_Cubic:
		y := 1 - x
		return 1 - y * y * y
	case .In_Out_Cubic:
		if x < 0.5 {return 4 * x * x * x}
		y := -2 * x + 2
		return 1 - y * y * y * 0.5
	case .In_Sine:
		return 1 - math.cos(x * math.PI * 0.5)
	case .Out_Sine:
		return math.sin(x * math.PI * 0.5)
	case .In_Out_Sine:
		return -(math.cos(math.PI * x) - 1) * 0.5
	case .Smooth:
		return x * x * (3 - 2 * x)
	}
	return x
}

animation_property_accepts :: proc(property: Animation_Property, kind: Animation_Value_Kind) -> bool {
	switch property {
	case .None:
		return true
	case .Background:
		return kind == .Colour
	case .Border:
		return kind == .Colour || kind == .Scalar
	case .Shadow:
		return kind == .Colour || kind == .Scalar || kind == .Vector
	case .Opacity, .Width, .Height:
		return kind == .Scalar
	case .Position:
		return kind == .Vector
	}
	return false
}

animation_value_kind :: proc(value: Animation_Value) -> Animation_Value_Kind {
	if _, ok := value.(f32); ok {return .Scalar}
	if _, ok := value.(Vec2); ok {return .Vector}
	if _, ok := value.(Colour); ok {return .Colour}
	return .None
}

animation_value_lerp :: proc(a, b: Animation_Value, t: f32) -> (Animation_Value, bool) {
	if av, aok := a.(f32); aok {
		if bv, bok := b.(f32); bok {
			return f32(av + (bv - av) * t), true
		}
	}
	if av, aok := a.(Vec2); aok {
		if bv, bok := b.(Vec2); bok {
			return Vec2 {
				x = av.x + (bv.x - av.x) * t,
				y = av.y + (bv.y - av.y) * t,
			}, true
		}
	}
	if av, aok := a.(Colour); aok {
		if bv, bok := b.(Colour); bok {
			return Colour {
				r = av.r + (bv.r - av.r) * t,
				g = av.g + (bv.g - av.g) * t,
				b = av.b + (bv.b - av.b) * t,
				a = av.a + (bv.a - av.a) * t,
			}, true
		}
	}
	return {}, false
}

Animation_Start :: proc(g: ^GUI, desc: Animation_Desc) -> Animation_ID {
	if g == nil {return INVALID_ANIMATION_ID}

	if desc.target != INVALID_WIDGET_ID && Core.Widget_Get(g, desc.target) == nil {
		log.warnf(
			"an animation was asked for the widget %d, which is not a widget that is there",
			int(desc.target.index),
		)
		return INVALID_ANIMATION_ID
	}

	kind := animation_value_kind(desc.from)
	if kind == .None || kind != animation_value_kind(desc.to) {
		log.warn("an animation was given two values that are not of the same kind")
		return INVALID_ANIMATION_ID
	}
	if !animation_property_accepts(desc.property, kind) {
		log.warn("an animation was given a property that does not take its value")
		return INVALID_ANIMATION_ID
	}
	if desc.property != .None && desc.target == INVALID_WIDGET_ID {
		log.warn("an animation was given a property but no widget")
		return INVALID_ANIMATION_ID
	}

	duration := desc.duration
	if duration != duration || duration < 0 {duration = 0}
	delay := desc.delay
	if delay != delay || delay < 0 {delay = 0}
	repeat := desc.repeat
	if repeat < -1 {repeat = -1}

	g.next_animation_id += 1
	if g.next_animation_id == 0 {g.next_animation_id = 1}

	tween := Tween {
		id          = Animation_ID(g.next_animation_id),
		target      = desc.target,
		property    = desc.property,
		from        = desc.from,
		to          = desc.to,
		value       = desc.from,
		duration    = duration,
		delay_left  = delay,
		easing      = desc.easing,
		state       = delay > 0 ? Animation_State.Delayed : Animation_State.Running,
		repeat      = repeat,
		ping_pong   = desc.ping_pong,
		on_complete = desc.on_complete,
		user        = desc.user,
	}
	append(&g.animations, tween)
	return tween.id
}

Animation_Get :: proc(g: ^GUI, id: Animation_ID) -> (Tween, bool) {
	index := animation_find(g, id)
	if index < 0 {return {}, false}
	return g.animations[index], true
}

Animation_Value_Of :: proc(g: ^GUI, id: Animation_ID) -> (Animation_Value, bool) {
	index := animation_find(g, id)
	if index < 0 {return {}, false}
	return g.animations[index].value, true
}

Animation_State_Of :: proc(g: ^GUI, id: Animation_ID) -> (Animation_State, bool) {
	index := animation_find(g, id)
	if index < 0 {return {}, false}
	return g.animations[index].state, true
}

Animation_Count :: proc(g: ^GUI) -> int {
	if g == nil {return 0}
	return len(g.animations)
}

Animation_Is_Active :: proc(g: ^GUI, id: Animation_ID) -> bool {
	index := animation_find(g, id)
	if index < 0 {return false}
	state := g.animations[index].state
	return state == .Delayed || state == .Running || state == .Paused
}

Animation_Any_Active :: proc(g: ^GUI) -> bool {
	if g == nil {return false}
	for tween in g.animations {
		if tween.state == .Delayed || tween.state == .Running {return true}
	}
	return false
}

Animation_Stop :: proc(g: ^GUI, id: Animation_ID) -> bool {
	index := animation_find(g, id)
	if index < 0 {return false}
	ordered_remove(&g.animations, index)
	return true
}

Animation_Cancel :: proc(g: ^GUI, id: Animation_ID) -> bool {
	return Animation_Stop(g, id)
}

Animation_Stop_Target :: proc(g: ^GUI, target: Widget_ID) -> int {
	if g == nil || target == INVALID_WIDGET_ID {return 0}
	stopped := 0
	for i := len(g.animations) - 1; i >= 0; i -= 1 {
		if g.animations[i].target != target {continue}
		ordered_remove(&g.animations, i)
		stopped += 1
	}
	return stopped
}

animation_forget :: proc(g: ^GUI, target: Widget_ID) {
	Animation_Stop_Target(g, target)
}

Animation_Clear :: proc(g: ^GUI) {
	if g == nil {return}
	clear(&g.animations)
	clear(&g.animations_done)
}

Animation_Pause :: proc(g: ^GUI, id: Animation_ID) -> bool {
	index := animation_find(g, id)
	if index < 0 {return false}
	tween := &g.animations[index]
	if tween.state != .Delayed && tween.state != .Running {return false}
	tween.state = .Paused
	return true
}

Animation_Resume :: proc(g: ^GUI, id: Animation_ID) -> bool {
	index := animation_find(g, id)
	if index < 0 {return false}
	tween := &g.animations[index]
	if tween.state != .Paused {return false}
	tween.state = tween.delay_left > 0 ? Animation_State.Delayed : Animation_State.Running
	return true
}

Animation_Reverse :: proc(g: ^GUI, id: Animation_ID) -> bool {
	index := animation_find(g, id)
	if index < 0 {return false}
	tween := &g.animations[index]
	if tween.state == .Completed || tween.state == .Cancelled {return false}

	animation_swap_ends(tween)
	tween.applied = false
	if tween.delay_left <= 0 && tween.duration > 0 {
		tween.elapsed = tween.duration - tween.elapsed
		animation_refresh_value(tween)
	} else {
		tween.value = tween.from
	}
	return true
}

Animation_Update :: proc(g: ^GUI, dt: f32) {
	if g == nil {return}
	if g.animations_updating {return}
	g.animations_updating = true
	defer g.animations_updating = false

	delta := dt
	if delta != delta || delta < 0 {delta = 0}

	clear(&g.animations_done)
	for i in 0 ..< len(g.animations) {
		tween := &g.animations[i]
		if tween.target != INVALID_WIDGET_ID && Core.Widget_Get(g, tween.target) == nil {
			tween.state = .Cancelled
			continue
		}
		animation_step(tween, delta)
		if tween.property != .None &&
		   (tween.state == .Running || tween.state == .Completed || !tween.applied) {
			animation_apply_value(g, tween)
			tween.applied = true
		}
		if tween.state == .Completed {
			append(&g.animations_done, tween^)
		}
	}

	animation_drop_finished(g)

	for i := 0; i < len(g.animations_done); i += 1 {
		tween := g.animations_done[i]
		if tween.on_complete == nil {continue}
		tween.on_complete(g, tween.id, tween.target, tween.value, tween.user)
	}
	clear(&g.animations_done)
}

animation_find :: proc(g: ^GUI, id: Animation_ID) -> int {
	if g == nil || id == INVALID_ANIMATION_ID {return -1}
	for tween, index in g.animations {
		if tween.id == id {return index}
	}
	return -1
}

animation_drop_finished :: proc(g: ^GUI) {
	write := 0
	for read in 0 ..< len(g.animations) {
		tween := g.animations[read]
		if tween.state == .Completed || tween.state == .Cancelled {continue}
		if write != read {g.animations[write] = tween}
		write += 1
	}
	resize(&g.animations, write)
}

animation_swap_ends :: proc(tween: ^Tween) {
	from := tween.from
	tween.from = tween.to
	tween.to = from
}

animation_value_at :: proc(tween: ^Tween) -> Animation_Value {
	if tween.duration <= 0 {return tween.to}
	progress := clamp(tween.elapsed / tween.duration, 0, 1)
	value, ok := animation_value_lerp(tween.from, tween.to, easing_apply(tween.easing, progress))
	if !ok {return tween.to}
	return value
}

animation_refresh_value :: proc(tween: ^Tween) {
	if tween.delay_left > 0 {
		tween.value = tween.from
		return
	}
	tween.value = animation_value_at(tween)
}

animation_step :: proc(tween: ^Tween, dt: f32) {
	if tween.state == .Paused || tween.state == .Completed || tween.state == .Cancelled {return}

	time := dt
	if tween.delay_left > 0 {
		if time < tween.delay_left {
			tween.delay_left -= time
			tween.state = .Delayed
			return
		}
		time -= tween.delay_left
		tween.delay_left = 0
	}
	tween.state = .Running

	if tween.duration <= 0 {
		tween.elapsed = 0
		tween.value = tween.to
		tween.state = .Completed
		return
	}

	animation_advance(tween, time)
}

animation_advance :: proc(tween: ^Tween, time: f32) {
	if time <= 0 {
		animation_refresh_value(tween)
		return
	}

	duration := tween.duration
	total := tween.elapsed + time
	crossed := int(total / duration)
	remainder := total - f32(crossed) * duration

	if tween.repeat >= 0 {
		available := tween.repeat + 1
		if crossed >= available {
			completed := available - 1
			if tween.ping_pong && (completed & 1) == 1 {animation_swap_ends(tween)}
			tween.elapsed = duration
			tween.repeat = 0
			tween.value = tween.to
			tween.state = .Completed
			return
		}
		tween.repeat -= crossed
	}

	if tween.ping_pong && (crossed & 1) == 1 {animation_swap_ends(tween)}
	tween.elapsed = remainder
	if tween.elapsed >= duration {tween.elapsed = 0}
	tween.value = animation_value_at(tween)
}

animation_apply_visual_style :: proc(g: ^GUI, w: ^Widget, style: Style) {
	if w.style == style {return}
	w.style = style
	w.style_cache.valid = false
	Core.invalidate(g, w.id, Dirty_Flags{.Visual})
}

animation_resize_axis :: proc(w: ^Widget, horizontal: bool, size: f32) {
	target := max(size, 0)
	if horizontal {
		w.manual_size.x = target
		w.manual_w = true
	} else {
		w.manual_size.y = target
		w.manual_h = true
	}
}

animation_apply_value :: proc(g: ^GUI, tween: ^Tween) {
	if g == nil || tween == nil {return}
	w := Core.Widget_Get(g, tween.target)
	if w == nil {return}

	switch tween.property {
	case .None:
		return
	case .Background:
		value, ok := tween.value.(Colour)
		if !ok {return}
		style := w.style
		style.box.bg_color = value
		style.set += bit_set[Style_Field]{.BG}
		animation_apply_visual_style(g, w, style)
	case .Border:
		style := w.style
		if value, ok := tween.value.(Colour); ok {
			style.box.border_color = {value, value, value, value}
			style.set += bit_set[Style_Field]{.Border}
		} else if value, ok := tween.value.(f32); ok {
			width := max(value, 0)
			style.box.border_width = {width, width, width, width}
			style.set += bit_set[Style_Field]{.Border_Width}
		} else {
			return
		}
		animation_apply_visual_style(g, w, style)
	case .Shadow:
		style := w.style
		if value, ok := tween.value.(Colour); ok {
			style.box.shadow_color = value
			style.set += bit_set[Style_Field]{.Shadow}
		} else if value, ok := tween.value.(f32); ok {
			style.box.shadow_size = max(value, 0)
			style.set += bit_set[Style_Field]{.Shadow}
		} else if value, ok := tween.value.(Vec2); ok {
			style.box.shadow_offset = value
			style.set += bit_set[Style_Field]{.Shadow}
		} else {
			return
		}
		animation_apply_visual_style(g, w, style)
	case .Opacity:
		value, ok := tween.value.(f32)
		if !ok {return}
		Core.Widget_Set_Opacity(g, w.id, value)
	case .Width:
		value, ok := tween.value.(f32)
		if !ok {return}
		animation_resize_axis(w, true, value)
		Core.invalidate(g, w.id, Dirty_Flags{.Measure, .Arrange})
	case .Height:
		value, ok := tween.value.(f32)
		if !ok {return}
		animation_resize_axis(w, false, value)
		Core.invalidate(g, w.id, Dirty_Flags{.Measure, .Arrange})
	case .Position:
		value, ok := tween.value.(Vec2)
		if !ok {return}
		origin := Vec2{w.rect.x, w.rect.y}
		if !tween.applied {
			if from, from_ok := tween.from.(Vec2); from_ok {origin = from}
		}
		dx := value.x - origin.x
		dy := value.y - origin.y
		if dx == 0 && dy == 0 {return}
		offsets := w.offsets
		offsets.left += dx
		offsets.right += dx
		offsets.top += dy
		offsets.bottom += dy
		Core.Widget_Set_Offsets(g, w.id, offsets)
	}
}
