//* The box around a widget: its background, border, corners and
//* the space that is kept free inside it. 
//
//* A style box is a plain struct, so it can be made on the spot:
//*
//*   style = Style{
//*       box = StyleBox{
//*           bg_color = rgba(0.2, 0.2, 0.3, 1),
//*           corner_radius = {4, 4, 4, 4},
//*       },
//*,}
//
//* The sides and the corners are given in the order Godot uses:
//* left, top, right, bottom for the sides and top left, top right,
//* bottom right, bottom left for the corners.

package Core
//* The four sides of a box.
Side :: enum { Left, Top, Right, Bottom }

//* The four corners of a box.
Corner :: enum { Top_Left, Top_Right, Bottom_Right, Bottom_Left }

StyleBox :: struct {
	//* The colour of the background.
	bg_color: Colour,

	//* The border. Every side has its own width and its own colour.
	border_width: [4]f32,
	border_color: [4]Colour,

	//* The corners. A corner that is 0 is square.
	corner_radius: [4]f32,

	//* The space that is kept free inside the box, so that the content
	//* of a widget does not touch its border.
	content_margin: [4]f32,

	//* The space the box is allowed to grow into, so that a border does
	//* not get cut off at the edge of its parent.
	expand_margin: [4]f32,

	//* The shadow under the box.
	shadow_color:  Colour,
	shadow_size:   f32,
	shadow_offset: Vec2,

	//* The radius of the blur of everything behind the box. Zero draws
	//* the background as it is. A backend that cannot read its own
	//* target ignores it and draws the tint alone.
	backdrop_blur: f32,

	//* Whether the corners are smoothed.
	anti_aliasing: bool,
}

stylebox :: proc(bg: Colour) -> StyleBox {
	return StyleBox{bg_color = bg}
}

//* A style box with a background and a border of the same colour on
//* every side.
stylebox_bordered :: proc(bg: Colour, border: Colour, width: f32) -> StyleBox {
	return StyleBox{
		bg_color     = bg,
		border_width = {width, width, width, width},
		border_color = {border, border, border, border},
	}
}

//* A style box with rounded corners.
stylebox_round :: proc(bg: Colour, radius: f32) -> StyleBox {
	return StyleBox{
		bg_color      = bg,
		corner_radius = {radius, radius, radius, radius},
		anti_aliasing = true,
	}
}

//* The largest corner radius of the box.
stylebox_radius :: proc(box: ^StyleBox) -> f32 {
	r := box.corner_radius
	return max(max(r[0], r[1]), max(r[2], r[3]))
}

stylebox_radii :: proc(box: ^StyleBox) -> [4]f32 {
	return box.corner_radius
}

clamp_corner_radii :: proc(radii: [4]f32, w, h: f32) -> [4]f32 {
	out := radii
	if !(w > 0) || !(h > 0) {return {}}
	limit := min(w, h) * 0.5
	for i in 0 ..< 4 {
		out[i] = clamp(out[i], 0, limit)
	}
	if s := radius_pair_scale(out[0], out[1], w); s < 1 {
		out[0] *= s
		out[1] *= s
	}
	if s := radius_pair_scale(out[3], out[2], w); s < 1 {
		out[3] *= s
		out[2] *= s
	}
	if s := radius_pair_scale(out[0], out[3], h); s < 1 {
		out[0] *= s
		out[3] *= s
	}
	if s := radius_pair_scale(out[1], out[2], h); s < 1 {
		out[1] *= s
		out[2] *= s
	}
	return out
}

radius_pair_scale :: proc(a, b, extent: f32) -> f32 {
	sum := a + b
	if sum > extent && sum > 0 {
		return extent / sum
	}
	return 1
}

radii_are_zero :: proc(radii: [4]f32) -> bool {
	return radii[0] <= 0 && radii[1] <= 0 && radii[2] <= 0 && radii[3] <= 0
}

max_corner_radius :: proc(radii: [4]f32) -> f32 {
	return max(max(radii[0], radii[1]), max(radii[2], radii[3]))
}

//* True when the box has a border on any side.
stylebox_has_border :: proc(box: ^StyleBox) -> bool {
	for w in box.border_width {
		if w > 0 { return true }
	}
	return false
}

stylebox_has_corners :: proc(box: ^StyleBox) -> bool {
	return stylebox_radius(box) > 0
}

//* The content of the box: the box without its content margin.
stylebox_content :: proc(box: StyleBox, rect: Rect) -> Rect {
	m := box.content_margin
	return Rect{
		x = rect.x + m[0],
		y = rect.y + m[1],
		w = rect.w - m[0] - m[2],
		h = rect.h - m[1] - m[3],
	}
}

//* The style box of a widget without its shadow and without the parts
//* that are not drawn: what the draw pass needs.
stylebox_plain :: proc(box: StyleBox) -> StyleBox {
	out := box
	out.shadow_color = Colour{}
	out.shadow_size = 0
	out.shadow_offset = Vec2{}
	out.expand_margin = [4]f32{}
	out.backdrop_blur = 0
	return out
}
