package GUI

//* == The colour rectangle ==

Color_Rect_Data :: struct {
	colour: Colour,
}

Color_Rect_Opts :: struct {
	Base_Opts: Base_Opts,
	colour:    Colour,
}

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

draw_color_rect :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	#partial switch d in w.data {
	case Color_Rect_Data:
		draw_rect(g, content, d.colour, 0)
	}
}

//* == The texture rectangle ==

Texture_Rect_Data :: struct {
	texture: Texture,
	region:  Rect,
}

Texture_Rect_Opts :: struct {
	Base_Opts: Base_Opts,
	texture:   Texture,
}

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
		draw_texture(g, d.texture, content, RGBA(1, 1, 1, 1))
	}
}

//* == The nine patch rectangle ==

Nine_Patch_Data :: struct {
	texture: Texture,
	patch:   [4]f32,
}

Nine_Patch_Opts :: struct {
	Base_Opts: Base_Opts,
	texture:   Texture,
	patch:     [4]f32,
}

Make_Nine_Patch_Rect :: proc(g: ^GUI, parent: Widget_ID, opts: Nine_Patch_Opts) -> Widget_ID {
	kind_register(g, .NinePatchRect, nine_patch_rect_kind())
	id := New_Widget(g, .NinePatchRect, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)
	w.data = Nine_Patch_Data {
		texture = opts.texture,
		patch   = opts.patch,
	}
	return id
}

nine_patch_rect_kind :: proc() -> Widget_Kind {
	return Widget_Kind{draw = draw_nine_patch_rect, theme_name = "NinePatchRect"}
}

draw_nine_patch_rect :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	#partial switch d in w.data {
	case Nine_Patch_Data:
		draw_nine_patch(g, d.texture, d.patch, content)
	}
}

//* Draws corners at their original size, stretches edges along one axis
//* and stretches the centre to fill the remaining space.
draw_nine_patch :: proc(g: ^GUI, texture: Texture, patch: [4]f32, content: Rect) {
	if !atlas_region_valid(g.atlas, texture.region) {return}
	if content.w <= 0 || content.h <= 0 {return}
	atlas_touch(g.atlas, texture.region)

	scale := g.scale
	if !(scale > 0) {scale = 1}

	pw := f32(texture.size[0])
	ph := f32(texture.size[1])
	if pw <= 0 || ph <= 0 {return}

	left := max(patch[0], 0)
	top := max(patch[1], 0)
	right := max(patch[2], 0)
	bottom := max(patch[3], 0)
	if left + right > pw {right = max(pw - left, 0); left = max(pw - right, 0)}
	if top + bottom > ph {bottom = max(ph - top, 0); top = max(ph - bottom, 0)}

	ml := left / scale
	mt := top / scale
	mr := right / scale
	mb := bottom / scale
	if ml + mr > content.w {mr = max(content.w - ml, 0); ml = max(content.w - mr, 0)}
	if mt + mb > content.h {mb = max(content.h - mt, 0); mt = max(content.h - mb, 0)}

	sx := left
	sy := top
	sw := pw - left - right
	sh := ph - top - bottom
	mx := content.x + ml
	my := content.y + mt
	mw := content.w - ml - mr
	mh := content.h - mt - mb

	nine_patch_part(g, texture, {sx, sy, left, top}, {content.x, content.y, ml, mt})
	nine_patch_part(g, texture, {sx + sw, sy, right, top}, {content.x + content.w - mr, content.y, mr, mt})
	nine_patch_part(g, texture, {sx, sy + sh, left, bottom}, {content.x, content.y + content.h - mb, ml, mb})
	nine_patch_part(
		g,
		texture,
		{sx + sw, sy + sh, right, bottom},
		{content.x + content.w - mr, content.y + content.h - mb, mr, mb},
	)

	nine_patch_part(g, texture, {sx, sy, sw, top}, {mx, content.y, mw, mt})
	nine_patch_part(g, texture, {sx, sy + sh, sw, bottom}, {mx, content.y + content.h - mb, mw, mb})
	nine_patch_part(g, texture, {sx, sy, left, sh}, {content.x, my, ml, mh})
	nine_patch_part(g, texture, {sx + sw, sy, right, sh}, {content.x + content.w - mr, my, mr, mh})

	nine_patch_part(g, texture, {sx, sy, sw, sh}, {mx, my, mw, mh})
}

nine_patch_part :: proc(g: ^GUI, texture: Texture, source: Rect, dest: Rect) {
	if source.w <= 0 || source.h <= 0 {return}
	if dest.w <= 0 || dest.h <= 0 {return}
	uv := atlas_region_uv_inside(
		g.atlas,
		texture.region,
		int(source.x),
		int(source.y),
		int(source.w),
		int(source.h),
	)
	draw_quad(g.target, dest, uv, RGBA(1, 1, 1, 1), g.atlas_texture)
}

//* == The reference rectangle ==

Reference_Rect_Opts :: struct {
	Base_Opts: Base_Opts,
}

Make_Reference_Rect :: proc(g: ^GUI, parent: Widget_ID, opts: Reference_Rect_Opts) -> Widget_ID {
	id := New_Widget(g, .ReferenceRect, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)
	w.mouse_filter = .Ignore
	return id
}

//* == The rich text label ==

Rich_Text_Data :: struct {
	text:   string,
	offset: f32,
}

Rich_Text_Opts :: struct {
	Base_Opts: Base_Opts,
	text:      string,
}

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

Item_List_Item :: struct {
	text:     string,
	icon:     Texture_ID,
	selected: bool,
}

Item_List_Data :: struct {
	items:    [dynamic]Item_List_Item,
	selected: int,
	scroll:   f32,
}

Item_List_Opts :: struct {
	Base_Opts: Base_Opts,
	items:     []string,
}

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

//* Selects an item and emits the item-selected signal.
item_list_select :: proc(g: ^GUI, id: Widget_ID, index: int) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Item_List_Data:
		if index < 0 || index >= len(d.items) {return}
		for &item in d.items {item.selected = false}
		d.items[index].selected = true
		d.selected = index
	}
	invalidate(g, id, Dirty_Flags{.Visual})
	signal_item_selected(g, id, index)
}

ITEM_LIST_ROW :: 22

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

Tree_Item :: struct {
	text:     string,
	depth:    int,
	parent:   int, // -1 for a root item
	expanded: bool,
	selected: bool,
	icon:     Texture_ID,
}

Tree_Data :: struct {
	items:    [dynamic]Tree_Item,
	selected: int,
	scroll:   f32,
}

Tree_Opts :: struct {
	Base_Opts: Base_Opts,
}

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

tree_data :: proc(g: ^GUI, id: Widget_ID) -> ^Tree_Data {
	w := Widget_Get(g, id)
	if w == nil {return nil}
	#partial switch &d in w.data {
	case Tree_Data:
		return &d
	}
	return nil
}

tree_content :: proc(g: ^GUI, w: ^Widget) -> Rect {
	style := resolved_style(g, w)
	return content_rect_with(w.rect, style.box.content_margin)
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

tree_select_item :: proc(g: ^GUI, id: Widget_ID, index: int) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Tree_Data:
		if index < 0 || index >= len(d.items) {return}
		for &item in d.items {item.selected = false}
		d.items[index].selected = true
		d.selected = index
		content := tree_content(g, w)
		tree_scroll_to_item(&d, index, content.h)
	}
	invalidate(g, id, Dirty_Flags{.Visual})
	signal_item_selected(g, id, index)
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

TREE_ROW     :: 20
TREE_INDENT  :: 16
TREE_PADDING :: 4

tree_content_height :: proc(d: ^Tree_Data) -> f32 {
	if d == nil {return 0}
	return f32(len(d.items)) * f32(TREE_ROW)
}

tree_scroll_clamp :: proc(d: ^Tree_Data, viewport: f32) {
	if d == nil {return}
	scroll_clamp(&d.scroll, tree_content_height(d), viewport)
}

tree_scroll_to_item :: proc(d: ^Tree_Data, index: int, viewport: f32) {
	if d == nil {return}
	if index < 0 {return}
	top := f32(index) * f32(TREE_ROW)
	bottom := top + f32(TREE_ROW)
	if top < d.scroll {
		d.scroll = top
	} else if bottom > d.scroll + viewport {
		d.scroll = bottom - viewport
	}
	tree_scroll_clamp(d, viewport)
}

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

Tab_Bar_Opts :: struct {
	Base_Opts: Base_Opts,
}

Make_Tab_Bar :: proc(g: ^GUI, parent: Widget_ID, opts: Tab_Bar_Opts) -> Widget_ID {
	return New_Widget(g, .TabBar, parent, base_widget_opts(opts.Base_Opts))
}

//* == The separators ==

Separator_Data :: struct {
	vertical: bool,
}

Separator_Opts :: struct {
	Base_Opts: Base_Opts,
}

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

Menu_Bar_Opts :: struct {
	Base_Opts: Base_Opts,
}

Make_Menu_Bar :: proc(g: ^GUI, parent: Widget_ID, opts: Menu_Bar_Opts) -> Widget_ID {
	return New_Widget(g, .MenuBar, parent, base_widget_opts(opts.Base_Opts))
}