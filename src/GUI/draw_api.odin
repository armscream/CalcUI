//* == Drawing from outside ==
//* A widget of a class of its own draws itself with these. They are the
//* same drawing the built-in widgets use: the same atlas, the same
//* clip, the same one draw call for the whole window.
//
//* The colour of a widget that is drawn is the colour the theme gives
//* it, and that is what Widget_Background and Widget_Text_Colour give
//* back: a widget that follows the theme does not have to know the
//* colours of the theme.

package GUI

//* Draws a rectangle of a colour. The corners are rounded when the
//* radius is not zero.
Draw_Rect :: proc(g: ^GUI, e: Rect, colour: Colour, radius: f32 = 0) {
	if g == nil { return }
	draw_rect(g, e, colour, radius)
}

//* Draws a piece of text in a box, in the style of the text. The style
//* comes from Widget_Style.
Draw_Text :: proc(g: ^GUI, ts: Text_Style, text: string, e: Rect, colour: Colour) {
	if g == nil { return }
	draw_text(g, ts, text, e, colour)
}

//* The size of a piece of text as it would be drawn. The width is the
//* width the text is wrapped at; zero means that it is not wrapped.
Measure_Text :: proc(g: ^GUI, ts: Text_Style, text: string, width: f32 = 0) -> Vec2 {
	if g == nil { return {} }
	return text_measure(g, ts, text, width)
}

//* Draws a part of a texture. The uv is the four corners of the part:
//* left, top, eight, bottom.
Draw_Quad :: proc(g: ^GUI, e: Rect, uv: [4]f32, colour: Colour, texture: Texture_ID) {
	if g == nil { return }
	draw_quad(g.target, e, uv, colour, texture)
}

//* Draws a rectangle of one colour, without a texture. It is the same
//* as Draw_Rect, and it is here because a solid rectangle is what a
//* widget wants most of the time.
Draw_Solid :: proc(g: ^GUI, e: Rect, colour: Colour) {
	if g == nil { return }
	draw_quad(g.target, e, g.atlas.white_uv, colour, g.atlas_texture)
}

//* Draws a line between two points.
Draw_Line :: proc(g: ^GUI, a, b: Vec2, width: f32, colour: Colour) {
	if g == nil { return }
	draw_thick_line(g.target, {a.x, a.y}, {b.x, b.y}, width, colour, g.atlas_texture)
}

//* Draws a polygon. The points are the corners of it.
Draw_Polygon :: proc(g: ^GUI, points: [][2]f32, colour: Colour) {
	if g == nil { return }
	draw_polygon(g.target, points, colour, g.atlas_texture)
}

//* The texture of the whole UI: the white texel, the glyphs of every
//* font and the images all live in it.
GUI_Atlas_Texture :: proc(g: ^GUI) -> Texture_ID {
	if g == nil { return INVALID_TEXTURE_ID }
	return g.atlas_texture
}

//* The part of the atlas that is the white texel. It is what a solid
//* rectangle is drawn with.
GUI_Atlas_White_UV :: proc(g: ^GUI) -> [4]f32 {
	if g == nil { return {} }
	return g.atlas.white_uv
}

//* == The look of a widget ==
//* These are the things a widget needs to draw itself: the style it is
//* drawn in, the colours it takes, and the space it has.

//* The style of a widget as it is drawn: the theme's style for its
//* kind, with the widget's own style on top of it.
Widget_Style :: proc(g: ^GUI, id: Widget_ID) -> Style {
	if g == nil { return {} }
	w := Widget_Get(g, id)
	if w == nil { return {} }
	return resolved_style(g, w)^
}

//* The background of a widget, in the state it is in: it is brighter
//* under the pointer and darker while it is pressed, unless the theme
//* says otherwise.
Widget_Background :: proc(g: ^GUI, id: Widget_ID) -> Colour {
	if g == nil { return {} }
	w := Widget_Get(g, id)
	if w == nil { return {} }
	return resolved_bg(g, id, w)
}

//* The colour of the text of a widget, in the state it is in.
Widget_Text_Colour :: proc(g: ^GUI, id: Widget_ID) -> Colour {
	if g == nil { return {} }
	w := Widget_Get(g, id)
	if w == nil { return {} }
	return resolved_text_colour(g, id, w)
}

//* The place of a widget in the window of the GUI.
Widget_Rect :: proc(g: ^GUI, id: Widget_ID) -> Rect {
	if g == nil { return {} }
	w := Widget_Get(g, id)
	if w == nil { return {} }
	return w.rect
}

//* The space of the content of a widget: its rect without the padding
//* of its style. This is the space the draw hook of a widget gets.
Widget_Content_Rect :: proc(g: ^GUI, id: Widget_ID) -> Rect {
	if g == nil { return {} }
	w := Widget_Get(g, id)
	if w == nil { return {} }
	return content_rect_with(w.rect, resolved_style(g, w).box.content_margin)
}

//* The name of a widget.
Widget_Name :: proc(g: ^GUI, id: Widget_ID) -> string {
	if g == nil { return "" }
	w := Widget_Get(g, id)
	if w == nil { return "" }
	return w.name
}

//* == Saying that something changed ==
//* A widget of a class of its own says what it changed, so that the
//* core measures and draws it again.

//* Marks a widget as out of date. The flags say what is stale about
//* it: the size of it, the place of it or the look of it.
Widget_Invalidate :: proc(g: ^GUI, id: Widget_ID, flags: Dirty_Flags) {
	if g == nil { return }
	invalidate(g, id, flags)
}
