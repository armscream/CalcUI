package Widgets
//* == The colour rectangle ==



Make_Color_Rect :: proc(g: ^GUI, parent: Widget_ID, opts: Color_Rect_Opts) -> Widget_ID {
	kind_register(g, .ColorRect, color_rect_kind())
	id := New_Widget(g, .ColorRect, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)
	w.data = Color_Rect_Data {
		colour = opts.colour,
	}
	return id
}

color_rect_kind :: proc() -> Widget_Kind {
	return Widget_Kind{draw = draw_color_rect, theme_name = "ColorRect"}
}

color_rect_set_colour :: proc(g: ^GUI, id: Widget_ID, colour: Colour) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Color_Rect_Data:
		if d.colour == colour {return}
		d.colour = colour
	}
	invalidate(g, id, Dirty_Flags{.Visual})
}

draw_color_rect :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	#partial switch d in w.data {
	case Color_Rect_Data:
		draw_rect(g, content, d.colour, 0)
	}
}

//* == The texture rectangle ==



Make_Texture_Rect :: proc(g: ^GUI, parent: Widget_ID, opts: Texture_Rect_Opts) -> Widget_ID {
	kind_register(g, .TextureRect, texture_rect_kind())
	id := New_Widget(g, .TextureRect, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)
	w.data = Texture_Rect_Data {
		texture = opts.texture,
	}
	return id
}

texture_rect_kind :: proc() -> Widget_Kind {
	return Widget_Kind{draw = draw_texture_rect, theme_name = "TextureRect"}
}

draw_texture_rect :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	#partial switch d in w.data {
	case Texture_Rect_Data:
		if !atlas_region_valid(g.atlas, d.texture.region) {return}
		radii := resolved_style(g, w).box.corner_radius
		draw_texture_rounded(g, d.texture, content, RGBA(1, 1, 1, 1), radii)
	}
}

//* == The nine patch rectangle ==



Make_Nine_Patch_Rect :: proc(g: ^GUI, parent: Widget_ID, opts: Nine_Patch_Opts) -> Widget_ID {
	kind_register(g, .NinePatchRect, nine_patch_rect_kind())
	id := New_Widget(g, .NinePatchRect, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)
	tint := opts.tint
	if tint == (Colour{}) {
		tint = RGBA(1, 1, 1, 1)
	}
	w.data = Nine_Patch_Data {
		texture = opts.texture,
		patch   = opts.patch,
		source  = opts.source,
		tint    = tint,
		horizontal_edge = opts.horizontal_edge,
		vertical_edge   = opts.vertical_edge,
		centre_mode     = opts.centre_mode,
	}
	return id
}

nine_patch_rect_kind :: proc() -> Widget_Kind {
	return Widget_Kind{draw = draw_nine_patch_rect, theme_name = "NinePatchRect"}
}

//* Changes the texture that the widget shows.
Nine_Patch_Set_Texture :: proc(g: ^GUI, id: Widget_ID, texture: Texture) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Nine_Patch_Data:
		d.texture = texture
	}
	invalidate(g, id, Dirty_Flags{.Visual})
}

//* Changes the sizes of the four borders, in source pixels. The order is
//* left, top, right and bottom.
Nine_Patch_Set_Patch :: proc(g: ^GUI, id: Widget_ID, patch: [4]f32) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Nine_Patch_Data:
		d.patch = patch
	}
	invalidate(g, id, Dirty_Flags{.Visual})
}

//* Changes the sub-rectangle of the texture that the widget shows. An
//* empty rectangle means the whole texture.
Nine_Patch_Set_Source :: proc(g: ^GUI, id: Widget_ID, source: Rect) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Nine_Patch_Data:
		d.source = source
	}
	invalidate(g, id, Dirty_Flags{.Visual})
}

//* Changes the colour that is multiplied into the texture.
Nine_Patch_Set_Tint :: proc(g: ^GUI, id: Widget_ID, tint: Colour) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Nine_Patch_Data:
		d.tint = tint
	}
	invalidate(g, id, Dirty_Flags{.Visual})
}

//* Changes how the edges and the centre fill their room.
Nine_Patch_Set_Modes :: proc(
	g: ^GUI,
	id: Widget_ID,
	horizontal_edge: Nine_Patch_Edge_Mode,
	vertical_edge: Nine_Patch_Edge_Mode,
	centre_mode: Nine_Patch_Centre_Mode,
) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Nine_Patch_Data:
		d.horizontal_edge = horizontal_edge
		d.vertical_edge = vertical_edge
		d.centre_mode = centre_mode
	}
	invalidate(g, id, Dirty_Flags{.Visual})
}

draw_nine_patch_rect :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	#partial switch d in w.data {
	case Nine_Patch_Data:
		draw_nine_patch(g, d, content)
	}
}


draw_nine_patch :: proc(g: ^GUI, data: Nine_Patch_Data, content: Rect) {
	if !atlas_region_valid(g.atlas, data.texture.region) {return}
	if content.w <= 0 || content.h <= 0 {return}

	texture_w := data.texture.size[0]
	texture_h := data.texture.size[1]
	if texture_w <= 0 || texture_h <= 0 {return}
	source := data.source
	if source.w <= 0 || source.h <= 0 {
		source = Rect{0, 0, f32(texture_w), f32(texture_h)}
	}
	limit_w := min(f32(texture_w), f32(data.texture.region.w))
	limit_h := min(f32(texture_h), f32(data.texture.region.h))
	if source.x < 0 || source.y < 0 {return}
	if source.x + source.w > limit_w {return}
	if source.y + source.h > limit_h {return}

	scale := g.scale
	if !(scale > 0) {scale = 1}

	layout := nine_patch_layout(source, content, data.patch, scale)
	if !layout.valid {return}

	atlas_touch(g.atlas, data.texture.region)

	tint := data.tint

	nine_patch_draw_cell(g, data.texture, &layout, .Top_Left, tint)
	nine_patch_draw_cell(g, data.texture, &layout, .Top_Right, tint)
	nine_patch_draw_cell(g, data.texture, &layout, .Bottom_Left, tint)
	nine_patch_draw_cell(g, data.texture, &layout, .Bottom_Right, tint)

	nine_patch_draw_edge(
		g,
		data.texture,
		layout.sources[int(Nine_Patch_Cell.Top)],
		layout.dests[int(Nine_Patch_Cell.Top)],
		tint,
		data.horizontal_edge,
		scale,
	)
	nine_patch_draw_edge(
		g,
		data.texture,
		layout.sources[int(Nine_Patch_Cell.Bottom)],
		layout.dests[int(Nine_Patch_Cell.Bottom)],
		tint,
		data.horizontal_edge,
		scale,
	)
	nine_patch_draw_edge_vertical(
		g,
		data.texture,
		layout.sources[int(Nine_Patch_Cell.Left)],
		layout.dests[int(Nine_Patch_Cell.Left)],
		tint,
		data.vertical_edge,
		scale,
	)
	nine_patch_draw_edge_vertical(
		g,
		data.texture,
		layout.sources[int(Nine_Patch_Cell.Right)],
		layout.dests[int(Nine_Patch_Cell.Right)],
		tint,
		data.vertical_edge,
		scale,
	)

	#partial switch data.centre_mode {
	case .Disabled:
	//* The centre is empty: the borders make a frame.
	case .Tile:
		nine_patch_draw_tiled_2d(
			g,
			data.texture,
			layout.sources[int(Nine_Patch_Cell.Centre)],
			layout.dests[int(Nine_Patch_Cell.Centre)],
			tint,
			scale,
		)
	case .Stretch:
		nine_patch_draw_cell(g, data.texture, &layout, .Centre, tint)
	}
}

NINE_PATCH_EPSILON :: 0.0001

//* Draws one cell at the size of its destination.
nine_patch_draw_cell :: proc(
	g: ^GUI,
	texture: Texture,
	layout: ^Nine_Patch_Layout,
	cell: Nine_Patch_Cell,
	tint: Colour,
) {
	nine_patch_draw_part(
		g,
		texture,
		layout.sources[int(cell)],
		layout.dests[int(cell)],
		tint,
	)
}

//* Draws one textured region of the source into one destination region.
nine_patch_draw_part :: proc(g: ^GUI, texture: Texture, source, dest: Rect, tint: Colour) {
	if source.w <= 0 || source.h <= 0 {return}
	if dest.w <= 0 || dest.h <= 0 {return}
	uv := atlas_region_uv_inside_f(
		g.atlas,
		texture.region,
		source.x,
		source.y,
		source.w,
		source.h,
	)
	draw_quad(g.target, dest, uv, tint, g.atlas_texture)
}

//* Draws a horizontal edge, either stretched over the destination or repeated along it.
nine_patch_draw_edge :: proc(
	g: ^GUI,
	texture: Texture,
	source, dest: Rect,
	tint: Colour,
	mode: Nine_Patch_Edge_Mode,
	scale: f32,
) {
	if mode == .Tile {
		nine_patch_draw_tiled_h(g, texture, source, dest, tint, scale)
		return
	}
	nine_patch_draw_part(g, texture, source, dest, tint)
}

//* Draws a vertical edge, either stretched over the destination or repeated along it.
nine_patch_draw_edge_vertical :: proc(
	g: ^GUI,
	texture: Texture,
	source, dest: Rect,
	tint: Colour,
	mode: Nine_Patch_Edge_Mode,
	scale: f32,
) {
	if mode == .Tile {
		nine_patch_draw_tiled_v(g, texture, source, dest, tint, scale)
		return
	}
	nine_patch_draw_part(g, texture, source, dest, tint)
}

//* Repeats a source region along the horizontal axis. The last repetition
//* shows only the part of the source that fits, so the pattern is never
//* stretched or cut off by the destination.
nine_patch_draw_tiled_h :: proc(
	g: ^GUI,
	texture: Texture,
	source, dest: Rect,
	tint: Colour,
	scale: f32,
) {
	if source.w <= 0 || source.h <= 0 {return}
	if dest.w <= 0 || dest.h <= 0 {return}
	tile_w := source.w / scale
	if !(tile_w > NINE_PATCH_EPSILON) {return}

	remaining := dest.w
	x := dest.x
	for remaining > NINE_PATCH_EPSILON {
		width := min(tile_w, remaining)
		if remaining - width <= NINE_PATCH_EPSILON {
			width = remaining
		}
		source_w := source.w * (width / tile_w)
		nine_patch_draw_part(
			g,
			texture,
			Rect{source.x, source.y, source_w, source.h},
			Rect{x, dest.y, width, dest.h},
			tint,
		)
		x += width
		remaining -= width
	}
}

//* Repeats a source region along the vertical axis.
nine_patch_draw_tiled_v :: proc(
	g: ^GUI,
	texture: Texture,
	source, dest: Rect,
	tint: Colour,
	scale: f32,
) {
	if source.w <= 0 || source.h <= 0 {return}
	if dest.w <= 0 || dest.h <= 0 {return}
	tile_h := source.h / scale
	if !(tile_h > NINE_PATCH_EPSILON) {return}

	remaining := dest.h
	y := dest.y
	for remaining > NINE_PATCH_EPSILON {
		height := min(tile_h, remaining)
		if remaining - height <= NINE_PATCH_EPSILON {
			height = remaining
		}
		source_h := source.h * (height / tile_h)
		nine_patch_draw_part(
			g,
			texture,
			Rect{source.x, source.y, source.w, source_h},
			Rect{dest.x, y, dest.w, height},
			tint,
		)
		y += height
		remaining -= height
	}
}

//* Repeats a source region along both axes.
nine_patch_draw_tiled_2d :: proc(
	g: ^GUI,
	texture: Texture,
	source, dest: Rect,
	tint: Colour,
	scale: f32,
) {
	if source.w <= 0 || source.h <= 0 {return}
	if dest.w <= 0 || dest.h <= 0 {return}
	tile_w := source.w / scale
	tile_h := source.h / scale
	if !(tile_w > NINE_PATCH_EPSILON) || !(tile_h > NINE_PATCH_EPSILON) {return}

	remaining_x := dest.w
	x := dest.x
	for remaining_x > NINE_PATCH_EPSILON {
		width := min(tile_w, remaining_x)
		if remaining_x - width <= NINE_PATCH_EPSILON {
			width = remaining_x
		}
		source_w := source.w * (width / tile_w)

		remaining_y := dest.h
		y := dest.y
		for remaining_y > NINE_PATCH_EPSILON {
			height := min(tile_h, remaining_y)
			if remaining_y - height <= NINE_PATCH_EPSILON {
				height = remaining_y
			}
			source_h := source.h * (height / tile_h)
			nine_patch_draw_part(
				g,
				texture,
				Rect{source.x, source.y, source_w, source_h},
				Rect{x, y, width, height},
				tint,
			)
			y += height
			remaining_y -= height
		}

		x += width
		remaining_x -= width
	}
}

//* == The reference rectangle ==


Make_Reference_Rect :: proc(g: ^GUI, parent: Widget_ID, opts: Reference_Rect_Opts) -> Widget_ID {
	id := New_Widget(g, .ReferenceRect, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)
	w.mouse_filter = .Ignore
	return id
}

//* == The rich text label ==



Make_Rich_Text_Label :: proc(g: ^GUI, parent: Widget_ID, opts: Rich_Text_Opts) -> Widget_ID {
	kind_register(g, .RichTextLabel, rich_text_label_kind())
	id := New_Widget(g, .RichTextLabel, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)
	w.data = Rich_Text_Data {
		text = opts.text,
	}
	return id
}

rich_text_label_kind :: proc() -> Widget_Kind {
	return Widget_Kind{draw = draw_rich_text_label, theme_name = "RichTextLabel"}
}

rich_text_label_text :: proc(g: ^GUI, id: Widget_ID) -> string {
	w := Widget_Get(g, id)
	if w == nil {return ""}
	#partial switch d in w.data {
	case Rich_Text_Data:
		return d.text
	}
	return ""
}

rich_text_label_set_text :: proc(g: ^GUI, id: Widget_ID, text: string) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Rich_Text_Data:
		if d.text == text {return}
		d.text = text
	}
	invalidate(g, id, Dirty_Flags{.Measure, .Visual})
	signal_text_changed(g, id, text)
}

draw_rich_text_label :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	#partial switch d in w.data {
	case Rich_Text_Data:
		text_style := resolved_style(g, w).text
		text_style.wrap = .Word
		draw_text(g, text_style, d.text, content, resolved_text_colour(g, id, w))
	}
}

//* == The item list ==




Make_Item_List :: proc(g: ^GUI, parent: Widget_ID, opts: Item_List_Opts) -> Widget_ID {
	kind_register(g, .ItemList, item_list_kind())
	id := New_Widget(g, .ItemList, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)
	data := Item_List_Data {
		selected = -1,
	}
	for item in opts.items {
		append(&data.items, Item_List_Item{text = item})
	}
	w.data = data
	w.focus_mode = .All
	return id
}

item_list_kind :: proc() -> Widget_Kind {
	return Widget_Kind{draw = draw_item_list, click = click_item_list, theme_name = "ItemList"}
}

item_list_count :: proc(g: ^GUI, id: Widget_ID) -> int {
	w := Widget_Get(g, id)
	if w == nil {return 0}
	#partial switch d in w.data {
	case Item_List_Data:
		return len(d.items)
	}
	return 0
}

item_list_text :: proc(g: ^GUI, id: Widget_ID, index: int) -> string {
	w := Widget_Get(g, id)
	if w == nil {return ""}
	#partial switch d in w.data {
	case Item_List_Data:
		if index < 0 || index >= len(d.items) {return ""}
		return d.items[index].text
	}
	return ""
}

item_list_add :: proc(g: ^GUI, id: Widget_ID, text: string) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Item_List_Data:
		append(&d.items, Item_List_Item{text = text})
	}
	invalidate(g, id, Dirty_Flags{.Visual})
}

item_list_remove :: proc(g: ^GUI, id: Widget_ID, index: int) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Item_List_Data:
		if index < 0 || index >= len(d.items) {return}
		ordered_remove(&d.items, index)
		if d.selected >= len(d.items) {d.selected = len(d.items) - 1}
	}
	invalidate(g, id, Dirty_Flags{.Visual})
}



draw_item_list :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	#partial switch d in w.data {
	case Item_List_Data:
		text_style := resolved_style(g, w).text
		y := content.y
		for item in d.items {
			if y >= content.y + content.h {break}
			row := Rect {
				x = content.x,
				y = y,
				w = content.w,
				h = ITEM_LIST_ROW,
			}
			if item.selected {
				draw_rect(g, row, RGBA(0.16, 0.42, 0.82, 1), 0)
			}
			label := Rect {
				x = row.x + 4,
				y = row.y,
				w = row.w - 8,
				h = row.h,
			}
			draw_text(g, text_style, item.text, label, resolved_text_colour(g, id, w))
			y += ITEM_LIST_ROW
		}
	}
}

click_item_list :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	item_list_click(g, id, w)
}

//* == The tree ==




Make_Tree :: proc(g: ^GUI, parent: Widget_ID, opts: Tree_Opts) -> Widget_ID {
	kind_register(g, .Tree, tree_kind())
	id := New_Widget(g, .Tree, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)
	w.data = Tree_Data {
		selected = -1,
	}
	w.focus_mode = .All
	return id
}

tree_kind :: proc() -> Widget_Kind {
	return Widget_Kind{
		draw = draw_tree,
		click = click_tree,
		key = key_tree,
		pointer = pointer_tree,
		measure = measure_tree,
		theme_name = "Tree",
	}
}



measure_tree :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) -> Vec2 {
	d := tree_data(g, id)
	if d == nil {return {}}
	style := resolved_style(g, w)

	width := f32(0)
	for item in d.items {
		size := text_measure(g, style.text, item.text, 0).x
		size += f32(TREE_INDENT) * f32(item.depth)
		if size > width {width = size}
	}

	pad := style.box.content_margin
	width += f32(TREE_PADDING) * 2 + pad[0] + pad[2]
	return Vec2{width, f32(TREE_ROW)}
}

//* Adds an item under the given parent, or at the root when parent is -1.
tree_add_item :: proc(g: ^GUI, id: Widget_ID, text: string, parent: int) -> int {
	w := Widget_Get(g, id)
	if w == nil {return -1}
	#partial switch &d in w.data {
	case Tree_Data:
		depth := 0
		if parent >= 0 && parent < len(d.items) {
			depth = d.items[parent].depth + 1
			d.items[parent].expanded = true
		}
		append(&d.items, Tree_Item{text = text, depth = depth, parent = parent})
		invalidate(g, id, Dirty_Flags{.Measure, .Visual})
		return len(d.items) - 1
	}
	return -1
}

tree_item_count :: proc(g: ^GUI, id: Widget_ID) -> int {
	w := Widget_Get(g, id)
	if w == nil {return 0}
	#partial switch d in w.data {
	case Tree_Data:
		return len(d.items)
	}
	return 0
}

tree_item_text :: proc(g: ^GUI, id: Widget_ID, index: int) -> string {
	w := Widget_Get(g, id)
	if w == nil {return ""}
	#partial switch d in w.data {
	case Tree_Data:
		if index < 0 || index >= len(d.items) {return ""}
		return d.items[index].text
	}
	return ""
}


tree_set_expanded :: proc(g: ^GUI, id: Widget_ID, index: int, expanded: bool) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Tree_Data:
		if index < 0 || index >= len(d.items) {return}
		d.items[index].expanded = expanded
	}
	invalidate(g, id, Dirty_Flags{.Visual})
}

TREE_PADDING :: 4




TREE_WHEEL_LINES :: 3

pointer_tree :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Pointer_Event) {
	if e.kind != .Wheel {return}
	d := tree_data(g, id)
	if d == nil {return}
	content := tree_content(g, w)
	delta := e.amount * f32(TREE_ROW) * TREE_WHEEL_LINES
	if !wheel_scroll(&d.scroll, delta, tree_content_height(d), content.h) {return}
	invalidate(g, id, Dirty_Flags{.Visual})
	Event_Handled(g)
}

key_tree :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Key_Down_Event) {
	d := tree_data(g, id)
	if d == nil {return}
	if len(d.items) == 0 {return}

	target := d.selected
	#partial switch e.key {
	case .Up:
		target = d.selected - 1
	case .Down:
		target = d.selected + 1
	case .Home:
		target = 0
	case .End:
		target = len(d.items) - 1
	case:
		return
	}
	if d.selected < 0 {target = 0}
	if target < 0 {target = 0}
	if target >= len(d.items) {target = len(d.items) - 1}
	if target == d.selected {return}

	tree_select_item(g, id, target)
	Event_Handled(g)
}

draw_tree :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	d := tree_data(g, id)
	if d == nil {return}
	text_style := resolved_style(g, w).text
	ink := resolved_text_colour(g, id, w)
	tree_scroll_clamp(d, content.h)

	draw_push_clip(g.target, content)
	y := content.y - d.scroll
	for item in d.items {
		if y >= content.y + content.h {break}
		if y + f32(TREE_ROW) > content.y {
			row := Rect {
				x = content.x,
				y = y,
				w = content.w,
				h = TREE_ROW,
			}
			if item.selected {
				draw_rect(g, row, RGBA(0.16, 0.42, 0.82, 1), 0)
			}
			indent := f32(item.depth) * f32(TREE_INDENT)
			label := Rect {
				x = row.x + f32(TREE_PADDING) + indent,
				y = row.y,
				w = row.w - f32(TREE_PADDING) * 2 - indent,
				h = row.h,
			}
			draw_text(g, text_style, item.text, label, ink)
		}
		y += TREE_ROW
	}
	draw_pop_clip(g.target)
}

click_tree :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	tree_click(g, id, w)
}

//* == The tab bar ==


Make_Tab_Bar :: proc(g: ^GUI, parent: Widget_ID, opts: Tab_Bar_Opts) -> Widget_ID {
	return New_Widget(g, .TabBar, parent, base_widget_opts(opts.Base_Opts))
}

//* == The separators ==



Make_Separator :: proc(g: ^GUI, parent: Widget_ID, vertical: bool) -> Widget_ID {
	kind_register(g, .HSeparator, separator_kind())
	kind_register(g, .VSeparator, separator_kind())
	id := New_Widget(g, .HSeparator, parent, Widget_Opts{})
	w := Widget_Get(g, id)
	if vertical {
		w.type = .VSeparator
	}
	w.data = Separator_Data {
		vertical = vertical,
	}
	w.mouse_filter = .Ignore
	return id
}

separator_kind :: proc() -> Widget_Kind {
	return Widget_Kind{draw = draw_separator, theme_name = "HSeparator"}
}

draw_separator :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	#partial switch d in w.data {
	case Separator_Data:
		colour := RGBA(0.25, 0.27, 0.33, 1)
		if d.vertical {
			draw_quad(
				g.target,
				Rect{x = content.x + content.w * 0.5, y = content.y, w = 1, h = content.h},
				g.atlas.white_uv,
				colour,
				g.atlas_texture,
			)
		} else {
			draw_quad(
				g.target,
				Rect{x = content.x, y = content.y + content.h * 0.5, w = content.w, h = 1},
				g.atlas.white_uv,
				colour,
				g.atlas_texture,
			)
		}
	}
}

//* == The menu bar ==


Make_Menu_Bar :: proc(g: ^GUI, parent: Widget_ID, opts: Menu_Bar_Opts) -> Widget_ID {
	return New_Widget(g, .MenuBar, parent, base_widget_opts(opts.Base_Opts))
}
