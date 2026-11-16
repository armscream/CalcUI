package Core

import "core:math"

Easing :: enum {
	Linear,
	In_Quad,
	Out_Quad,
	In_Out_Quad,
	In_Cubic,
	Out_Cubic,
	In_Out_Cubic,
	In_Sine,
	Out_Sine,
	In_Out_Sine,
	Smooth,
}

Animation_Value :: union {
	f32,
	Vec2,
	Colour,
}

Animation_Value_Kind :: enum {
	None,
	Scalar,
	Vector,
	Colour,
}

Animation_Property :: enum {
	None,
	Background,
	Border,
	Shadow,
	Opacity,
	Width,
	Height,
	Position,
}

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

Animation_ID :: distinct u64

INVALID_ANIMATION_ID :: Animation_ID(0)

Animation_State :: enum {
	Delayed,
	Running,
	Paused,
	Completed,
	Cancelled,
}

Animation_Complete :: proc(
	g: ^GUI,
	anim: Animation_ID,
	target: Widget_ID,
	value: Animation_Value,
	user: rawptr,
)

Animation_Desc :: struct {
	target:      Widget_ID,
	property:    Animation_Property,
	from:        Animation_Value,
	to:          Animation_Value,
	duration:    f32,
	delay:       f32,
	easing:      Easing,
	repeat:      int,
	ping_pong:   bool,
	on_complete: Animation_Complete,
	user:        rawptr,
}

Tween :: struct {
	id:          Animation_ID,
	target:      Widget_ID,
	property:    Animation_Property,
	from:        Animation_Value,
	to:          Animation_Value,
	value:       Animation_Value,
	applied:     bool,
	duration:    f32,
	delay_left:  f32,
	elapsed:     f32,
	easing:      Easing,
	state:       Animation_State,
	repeat:      int,
	ping_pong:   bool,
	on_complete: Animation_Complete,
	user:        rawptr,
}

animation_forget :: proc(g: ^GUI, target: Widget_ID) {
	if g == nil || target == INVALID_WIDGET_ID {return}
	for i := len(g.animations) - 1; i >= 0; i -= 1 {
		if g.animations[i].target != target {continue}
		ordered_remove(&g.animations, i)
	}
}
