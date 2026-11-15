package Core

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
