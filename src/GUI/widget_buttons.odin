//* Godot-style buttons: check box, option button, menu button and link.

package GUI

//** Check box

Check_Box_Data :: struct {
	text: string,
	on:   bool,
}

CHECK_BOX_SIZE :: 16
CHECK_BOX_GAP  :: 8

Check_Box_Opts :: struct {
	Base_Opts: Base_Opts,
	text:      string,
	on:        bool,
}

Make_Check_Box :: proc(g: ^GUI, parent: Widget_ID, opts: Check_Box_Opts) -> Widget_ID {
	kind_register(g, .CheckBox, check_box_kind())
	id := New_Widget(g, .CheckBox, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)
	w.data = Check_Box_Data{text = opts.text, on = opts.on}
	w.focus_mode = .All
	return id
}

check_box_kind :: proc() -> Widget_Kind {
	return Widget_Kind{
		draw = draw_check_box,
		click = click_check_box,
		theme_name = "CheckBox",
	}
}

check_box_set :: proc(g: ^GUI, id: Widget_ID, on: bool) {
	w := Widget_Get(g, id)
	if w == nil {
		return
	}
	#partial switch &d in w.data {
	case Check_Box_Data:
		if d.on == on {
			return
		}
		d.on = on
	}
	signal_toggled(g, id, on)
	invalidate(g, id, Dirty_Flags{.Visual})
}

check_box_is_on :: proc(g: ^GUI, id: Widget_ID) -> bool {
	w := Widget_Get(g, id)
	if w == nil {
		return false
	}
	#partial switch d in w.data {
	case Check_Box_Data:
		return d.on
	}
	return false
}

draw_check_box :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	#partial switch d in w.data {
	case Check_Box_Data:
		style := resolved_style(g, w)
		square := check_box_square(g, w, content)
		box, has := Theme_Get_Stylebox(g.theme, .CheckBox, check_box_style_name(d.on, w))
		if !has {
			box = check_box_default_box(d.on)
		}
		draw_stylebox_at(g, &box, square)
		if d.on {
			colour := style.text.colour
			if colour.a <= 0 {
				colour = resolved_text_colour(g, id, w)
			}
			draw_thick_line(g.target, {square.x + 4, square.y + 8.5}, {square.x + 6.5, square.y + 11}, 2, colour, g.atlas_texture)
			draw_thick_line(g.target, {square.x + 6.5, square.y + 11}, {square.x + 12, square.y + 5}, 2, colour, g.atlas_texture)
		}
		label := Rect{
			x = square.x + CHECK_BOX_SIZE + CHECK_BOX_GAP,
			y = content.y,
			w = content.w - CHECK_BOX_SIZE - CHECK_BOX_GAP,
			h = content.h,
		}
		draw_text(g, style.text, d.text, label, resolved_text_colour(g, id, w))
	}
}

check_box_content :: proc(g: ^GUI, w: ^Widget) -> Rect {
	style := resolved_style(g, w)
	return content_rect_with(w.rect, style.box.content_margin)
}

check_box_square :: proc(g: ^GUI, w: ^Widget, content: Rect) -> Rect {
	y := (content.h - CHECK_BOX_SIZE) * 0.5
	if y < 0 {
		y = 0
	}
	return Rect{x = content.x, y = content.y + y, w = CHECK_BOX_SIZE, h = CHECK_BOX_SIZE}
}

check_box_style_name :: proc(on: bool, w: ^Widget) -> string {
	hovered := .Hovered in w.state
	switch {
	case on && hovered:
		return "box_on_hover"
	case on:
		return "box_on"
	case hovered:
		return "box_hover"
	}
	return "box"
}

check_box_default_box :: proc(on: bool) -> StyleBox {
	if on {
		accent := RGBA(0.29, 0.58, 0.96, 1)
		return StyleBox{
			bg_color = accent,
			border_color = {accent, accent, accent, accent},
			border_width = {1, 1, 1, 1},
			corner_radius = {4, 4, 4, 4},
		}
	}
	border := RGBA(0.24, 0.26, 0.31, 1)
	return StyleBox{
		bg_color = RGBA(0.15, 0.16, 0.20, 1),
		border_color = {border, border, border, border},
		border_width = {1, 1, 1, 1},
		corner_radius = {4, 4, 4, 4},
	}
}

click_check_box :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	#partial switch d in w.data {
	case Check_Box_Data:
		square := check_box_square(g, w, check_box_content(g, w))
		if rect_contains(square, g.pointer.x, g.pointer.y) {
			check_box_set(g, id, !d.on)
		}
	}
}

//** Option button

Option_Button_Data :: struct {
	items:  [dynamic]string,
	active: int,
}

Option_Button_Opts :: struct {
	Base_Opts: Base_Opts,
	items:     []string,
}

Make_Option_Button :: proc(g: ^GUI, parent: Widget_ID, opts: Option_Button_Opts) -> Widget_ID {
	kind_register(g, .OptionButton, option_button_kind())
	id := New_Widget(g, .OptionButton, parent, base_widget_opts(opts.Base_Opts))
	data := Option_Button_Data{active = 0}
	for item in opts.items {
		append(&data.items, item)
	}
	w := Widget_Get(g, id)
	w.data = data
	w.focus_mode = .All
	return id
}

option_button_kind :: proc() -> Widget_Kind {
	return Widget_Kind{
		draw = draw_option_button,
		click = click_option_button,
		theme_name = "OptionButton",
	}
}

option_button_text :: proc(g: ^GUI, id: Widget_ID) -> string {
	w := Widget_Get(g, id)
	if w == nil {
		return ""
	}
	#partial switch d in w.data {
	case Option_Button_Data:
		if d.active >= 0 && d.active < len(d.items) {
			return d.items[d.active]
		}
	}
	return ""
}

option_button_select :: proc(g: ^GUI, id: Widget_ID, index: int) {
	w := Widget_Get(g, id)
	if w == nil {
		return
	}
	#partial switch &d in w.data {
	case Option_Button_Data:
		if index < 0 || index >= len(d.items) {
			return
		}
		d.active = index
	}
	signal_item_selected(g, id, index)
	invalidate(g, id, Dirty_Flags{.Visual})
}

draw_option_button :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	#partial switch d in w.data {
	case Option_Button_Data:
		style := resolved_style(g, w)
		text := ""
		if d.active >= 0 && d.active < len(d.items) {
			text = d.items[d.active]
		}
		colour := resolved_text_colour(g, id, w)
		draw_text(g, style.text, text, content, colour)
		draw_quad(
			g.target,
			Rect{x = content.x + content.w - 12, y = content.y + content.h * 0.5 - 2, w = 8, h = 4},
			g.atlas.white_uv,
			colour,
			g.atlas_texture,
		)
	}
}

click_option_button :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	#partial switch d in w.data {
	case Option_Button_Data:
		if len(d.items) > 0 {
			option_button_select(g, id, (d.active + 1) % len(d.items))
		}
	}
}

//** Menu button

Menu_Button_Data :: struct {
	text:  string,
	items: [dynamic]string,
	popup: Widget_ID,
}

Menu_Button_Opts :: struct {
	Base_Opts: Base_Opts,
	text:      string,
	items:     []string,
}

MENU_BUTTON_Z_INDEX :: POPUP_Z_INDEX

Make_Menu_Button :: proc(g: ^GUI, parent: Widget_ID, opts: Menu_Button_Opts) -> Widget_ID {
	kind_register(g, .MenuButton, menu_button_kind())
	id := New_Widget(g, .MenuButton, parent, base_widget_opts(opts.Base_Opts))
	data := Menu_Button_Data{text = opts.text, popup = INVALID_WIDGET_ID}
	for item in opts.items {
		append(&data.items, item)
	}
	w := Widget_Get(g, id)
	w.data = data
	w.focus_mode = .All

	popup := Make_Popup_Menu(g, g.root, Popup_Menu_Opts{items = opts.items})
	pw := Widget_Get(g, popup)
	if pw != nil {
		Widget_Set_Z_Index(g, popup, MENU_BUTTON_Z_INDEX)
		#partial switch &pd in pw.data {
		case Popup_Menu_Data:
			pd.owner = id
		}
	}
	#partial switch &d in w.data {
	case Menu_Button_Data:
		d.popup = popup
	}
	return id
}

menu_button_kind :: proc() -> Widget_Kind {
	return Widget_Kind{
		draw = draw_menu_button,
		click = click_menu_button,
		destroy = destroy_menu_button,
		theme_name = "MenuButton",
	}
}

draw_menu_button :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	#partial switch d in w.data {
	case Menu_Button_Data:
		style := resolved_style(g, w)
		draw_text(g, style.text, d.text, content, resolved_text_colour(g, id, w))
	}
}

menu_button_popup :: proc(g: ^GUI, id: Widget_ID) -> Widget_ID {
	w := Widget_Get(g, id)
	if w == nil {
		return INVALID_WIDGET_ID
	}
	#partial switch d in w.data {
	case Menu_Button_Data:
		return d.popup
	}
	return INVALID_WIDGET_ID
}

click_menu_button :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	popup := menu_button_popup(g, id)
	if popup == INVALID_WIDGET_ID {
		return
	}
	if Popup_Is_Open(g, popup) {
		Popup_Menu_Close(g, popup)
		return
	}
	menu_button_open(g, id)
}

menu_button_host :: proc(g: ^GUI, id: Widget_ID) -> Widget_ID {
	index := float_index_of(g, id)
	if index != FLOAT_NONE {
		return g.floats[index].widget
	}
	return g.root
}

menu_button_open :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil {
		return
	}
	popup := menu_button_popup(g, id)
	if popup == INVALID_WIDGET_ID {
		return
	}
	pw := Widget_Get(g, popup)
	if pw == nil || popup_menu_size(g, popup).x <= 0 {
		return
	}

	host := menu_button_host(g, id)
	if pw.parent != host {
		Widget_Attach(g, host, popup)
	}
	popup_menu_place(g, popup, w.rect)
	Popup_Menu_Open(g, popup)
}

menu_button_reposition :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil {
		return
	}
	popup := menu_button_popup(g, id)
	if popup == INVALID_WIDGET_ID || !Popup_Is_Open(g, popup) {
		return
	}
	popup_menu_place(g, popup, w.rect)
}

menu_buttons_reposition :: proc(g: ^GUI) {
	for w in g.widgets {
		if w != nil && w.type == .MenuButton {
			menu_button_reposition(g, w.id)
		}
	}
}

destroy_menu_button :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	popup := menu_button_popup(g, id)
	if popup != INVALID_WIDGET_ID {
		Widget_Free(g, popup)
	}
}

//** Link button

Link_Button_Data :: struct {
	text: string,
	link: string,
}

Link_Button_Opts :: struct {
	Base_Opts: Base_Opts,
	text:      string,
	link:      string,
}

Make_Link_Button :: proc(g: ^GUI, parent: Widget_ID, opts: Link_Button_Opts) -> Widget_ID {
	kind_register(g, .LinkButton, link_button_kind())
	id := New_Widget(g, .LinkButton, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)
	w.data = Link_Button_Data{text = opts.text, link = opts.link}
	w.focus_mode = .All
	return id
}

link_button_kind :: proc() -> Widget_Kind {
	return Widget_Kind{
		draw = draw_link_button,
		click = click_link_button,
		update = update_link_button,
		theme_name = "LinkButton",
	}
}

draw_link_button :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	#partial switch d in w.data {
	case Link_Button_Data:
		style := resolved_style(g, w)
		ink := resolved_text_colour(g, id, w)
		draw_text(g, style.text, d.text, content, ink)
		link_button_underline(g, style, d.text, content, ink)
	}
}

link_button_underline :: proc(g: ^GUI, style: ^Style, text: string, content: Rect, ink: Colour) {
	if text == "" {
		return
	}
	size := text_measure(g, style.text, text, 0)
	if size.x <= 0 {
		return
	}
	x := content.x
	switch style.text.align {
	case .Center:
		x += (content.w - size.x) * 0.5
	case .Right:
		x += content.w - size.x
	case .Left, .Fill:
	}
	top := content.y
	switch style.text.valign {
	case .Center:
		top += (content.h - size.y) * 0.5
	case .Bottom:
		top += content.h - size.y
	case .Top:
	}
	ascent := f32(0)
	if f := font_get(g, Font_Resolve(g, style.text)); f != nil {
		ascent = f.ascent
	}
	draw_rect(g, Rect{x = x, y = top + ascent + 1, w = size.x, h = 1}, ink, 0)
}

click_link_button :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	#partial switch d in w.data {
	case Link_Button_Data:
		if d.link == "" || signal_link_activated(g, id, d.link) {
			return
		}
		if g.backend.open_url != nil {
			g.backend.open_url(g.backend.ctx, d.link)
		}
	}
}

update_link_button :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, dt: f32) {
	if rect_contains(w.rect, g.pointer.x, g.pointer.y) {
		g.cursor = .Pointer
	}
}