package Widgets
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"

//* Writes widget trees in the scene format read by scene.odin.
//* Only properties supported by the loader are saved. Runtime widget
//* state, such as list items, table rows, and palette commands, is omitted.
//*
//* Duplicate names receive a numeric suffix in the file; widget names
//* are unchanged. Widgets without their own constructor use their base
//* widget type. Widgets without any available constructor are skipped,
//* but their children are still written under their former parent.
//*
//* Unnamed widgets receive a type-based name, such as Label1 or Label2.
//* Anchors and offsets are always saved. Borders use one colour for all
Scene_Save_Options :: struct {
	dock_layout: bool,
}

//* Writes the tree under root and returns the scene text.
//* The caller owns the returned string and must free it with the
//* allocator used to create it. An invalid root returns an empty string.
Scene_Save :: proc(g: ^GUI, root: Widget_ID, allocator: mem.Allocator = context.allocator) -> string {
	return Scene_Save_With_Options(g, root, {}, allocator)
}

Scene_Save_With_Options :: proc(
	g: ^GUI,
	root: Widget_ID,
	options: Scene_Save_Options,
	allocator: mem.Allocator = context.allocator,
) -> string {
	if g == nil {return ""}
	if Widget_Get(g, root) == nil {return ""}

	//* Register built-in constructors before checking widget types.
	scene_register_defaults(g)

	builder: strings.Builder
	if _, err := strings.builder_init_len_cap(&builder, 0, 256, allocator); err != nil {
		return ""
	}

	saver := scene_saver {
		g = g,
		options = options,
		taken = make(map[string]bool),
		used = make(map[string]bool),
		counters = make(map[Widget_Type]int),
	}
	defer scene_saver_destroy(&saver)

	scene_save_take_names(&saver, root)
	if options.dock_layout {
		for f in g.floats {
			if Widget_Get(g, f.widget) == nil {continue}
			scene_save_take_names(&saver, f.widget)
		}
		scene_save_dock_section(&builder, g)
	}

	scene_save_node(&builder, &saver, root, "", 0)

	if options.dock_layout {
		for f in g.floats {
			if Widget_Get(g, f.widget) == nil {continue}
			strings.write_byte(&builder, '\n')
			scene_save_node(&builder, &saver, f.widget, "", 0)
		}
	}
	return strings.to_string(builder)
}

//* Writes the scene tree to a file. Returns false if the path or tree
//* is invalid, or if writing fails.
Scene_Save_File :: proc(g: ^GUI, root: Widget_ID, path: string) -> bool {
	return Scene_Save_File_With_Options(g, root, path, {})
}

Scene_Save_File_With_Options :: proc(
	g: ^GUI,
	root: Widget_ID,
	path: string,
	options: Scene_Save_Options = {},
	allocator: mem.Allocator = context.allocator,
) -> bool {
	if path == "" {return false}
	text := Scene_Save_With_Options(g, root, options, allocator)
	defer delete(text, allocator)
	if text == "" {return false}
	return os.write_entire_file(path, text) == nil
}

scene_save_dock_section :: proc(builder: ^strings.Builder, g: ^GUI) {
	strings.write_string(builder, "[dock]\n")

	scene_save_line(builder, 1, "version")
	strings.write_int(builder, SCENE_DOCK_VERSION)
	strings.write_byte(builder, '\n')

	viewport := [4]f32{g.viewport.x, g.viewport.y, g.viewport.w, g.viewport.h}
	scene_save_line(builder, 1, "viewport")
	scene_save_write_numbers(builder, viewport[:])
	strings.write_byte(builder, '\n')

	window_rect := [4]f32{g.window_rect.x, g.window_rect.y, g.window_rect.w, g.window_rect.h}
	scene_save_line(builder, 1, "window_rect")
	scene_save_write_numbers(builder, window_rect[:])
	strings.write_byte(builder, '\n')
	strings.write_byte(builder, '\n')
}

//* Tracks names used by the tree and the file.
scene_saver :: struct {
	g:        ^GUI,
	options:  Scene_Save_Options,
	//* Original widget names, reserved for generated names.
	taken:    map[string]bool,
	//* Names already written to the file.
	used:     map[string]bool,
	//* Owns copies of names stored in used.
	names:    [dynamic]string,
	//* Counters for generated names, grouped by widget type.
	counters: map[Widget_Type]int,
}

//* Releases the writer's name copies and maps.
scene_saver_destroy :: proc(saver: ^scene_saver) {
	for name in saver.names {delete(name)}
	delete(saver.names)
	delete(saver.taken)
	delete(saver.used)
	delete(saver.counters)
}

//* Reserves all existing names before generating any replacements.
scene_save_take_names :: proc(saver: ^scene_saver, id: Widget_ID) {
	w := Widget_Get(saver.g, id)
	if w == nil {return}
	if w.name != "" {saver.taken[w.name] = true}
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(saver.g, child)
		if c == nil {break}
		scene_save_take_names(saver, child)
		child = c.next_sibling
	}
}

//* Adds a copied name to the set of names used in the file.
scene_save_take_name :: proc(saver: ^scene_saver, name: string) {
	if saver.used[name] {return}
	kept := strings.clone(name)
	saver.used[kept] = true
	append(&saver.names, kept)
}

//* Writes a widget and its children.
scene_save_node :: proc(
	builder: ^strings.Builder,
	saver: ^scene_saver,
	id: Widget_ID,
	parent_name: string,
	depth: int,
) {
	g := saver.g
	w := Widget_Get(g, id)
	if w == nil {return}

	//* Internal helpers such as a graph creation menu are not part of
	//* the scene, but anything under them still is.
	if w.skip_scene_save {
		scene_save_children(builder, saver, w, parent_name, depth)
		return
	}

	//* Skip widgets the loader cannot construct, but preserve their children.
	if !scene_save_can_be_made(g, w) {
		log.warnf(
			"scene: the widget %q of the kind %q has no constructor, so it is left out of the file",
			w.name,
			type_name_of(w.type),
		)
		scene_save_children(builder, saver, w, parent_name, depth)
		return
	}

	name_buf: [256]u8
	name := scene_save_file_name(saver, w, name_buf[:])
	type_name := scene_save_type_of(g, w)

	scene_save_indent(builder, depth)
	strings.write_string(builder, "[node name=\"")
	scene_save_write_escaped(builder, name)
	strings.write_string(builder, "\" type=\"")
	scene_save_write_escaped(builder, type_name)
	strings.write_string(builder, "\"")
	if parent_name != "" {
		strings.write_string(builder, " parent=\"")
		scene_save_write_escaped(builder, parent_name)
		strings.write_string(builder, "\"")
	}
	strings.write_string(builder, "]\n")

	scene_save_properties(builder, saver, w, depth + 1)
	scene_save_children(builder, saver, w, name, depth + 1)
}

//* Writes children under the supplied parent name.
scene_save_children :: proc(
	builder: ^strings.Builder,
	saver: ^scene_saver,
	w: ^Widget,
	parent_name: string,
	depth: int,
) {
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(saver.g, child)
		if c == nil {break}
		strings.write_byte(builder, '\n')
		scene_save_node(builder, saver, child, parent_name, depth)
		child = c.next_sibling
	}
}

//* Returns a unique file name without changing the widget's name.
scene_save_file_name :: proc(saver: ^scene_saver, w: ^Widget, buf: []u8) -> string {
	name := w.name
	if name == "" {
		name = scene_save_make_name(saver, w, buf)
		scene_save_take_name(saver, name)
		return name
	}
	if !saver.used[name] {
		scene_save_take_name(saver, name)
		return name
	}

	base := name
	if len(base) + 8 > len(buf) {base = base[:len(buf) - 8]}
	counter := 2
	for {
		candidate := fmt.bprintf(buf, "%s%d", base, counter)
		if !saver.used[candidate] {
			scene_save_take_name(saver, candidate)
			return candidate
		}
		counter += 1
	}
}

//* Uses the class name when it has its own constructor; otherwise uses
//* the base widget type understood by the loader.
scene_save_type_of :: proc(g: ^GUI, w: ^Widget) -> string {
	if c, ok := class_get(g, w.class); ok && c.constructor != nil && c.name != "" {
		return c.name
	}
	return type_name_of(w.type)
}

//* Checks whether the loader has a constructor for this widget.
scene_save_can_be_made :: proc(g: ^GUI, w: ^Widget) -> bool {
	if c, ok := class_get(g, w.class); ok && c.constructor != nil {return true}
	return Scene_Constructor_Of(g, w.type) != nil
}

//* Generates a unique type-based name for an unnamed widget.
scene_save_make_name :: proc(saver: ^scene_saver, w: ^Widget, buf: []u8) -> string {
	kind := type_name_of(w.type)
	if kind == "" {kind = "Widget"}
	counter := saver.counters[w.type] + 1
	for {
		name := fmt.bprintf(buf, "%s%d", kind, counter)
		if !saver.taken[name] && !saver.used[name] {
			saver.counters[w.type] = counter
			return name
		}
		counter += 1
	}
}

//* Writes the properties supported by the scene loader.
scene_save_properties :: proc(
	builder: ^strings.Builder,
	saver: ^scene_saver,
	w: ^Widget,
	depth: int,
) {
	g := saver.g
	//* Always save anchors and offsets to preserve layout.
	anchors := [4]f32{w.anchors.left, w.anchors.top, w.anchors.right, w.anchors.bottom}
	scene_save_line(builder, depth, "anchors")
	scene_save_write_numbers(builder, anchors[:])
	strings.write_byte(builder, '\n')

	offsets := [4]f32{w.offsets.left, w.offsets.top, w.offsets.right, w.offsets.bottom}
	scene_save_line(builder, depth, "offsets")
	scene_save_write_numbers(builder, offsets[:])
	strings.write_byte(builder, '\n')

	if saver.options.dock_layout {
		if w.weight != 1 {
			scene_save_line(builder, depth, "weight")
			scene_save_write_number(builder, w.weight)
			strings.write_byte(builder, '\n')
		}

		#partial switch d in w.data {
		case Tabs_Data:
			if d.active > 0 {
				scene_save_line(builder, depth, "active")
				strings.write_int(builder, d.active)
				strings.write_byte(builder, '\n')
			}
		case Tab_Container_Data:
			if d.active > 0 {
				scene_save_line(builder, depth, "active")
				strings.write_int(builder, d.active)
				strings.write_byte(builder, '\n')
			}
		}

		if index := float_of(g, w.id); index != FLOAT_NONE {
			f := g.floats[index]
			scene_save_line(builder, depth, "floating")
			strings.write_string(builder, "true")
			strings.write_byte(builder, '\n')

			pos := [2]f32{f.pos.x, f.pos.y}
			scene_save_line(builder, depth, "float_pos")
			scene_save_write_numbers(builder, pos[:])
			strings.write_byte(builder, '\n')

			size := [2]f32{f.size.x, f.size.y}
			scene_save_line(builder, depth, "float_size")
			scene_save_write_numbers(builder, size[:])
			strings.write_byte(builder, '\n')
		}
	}

	if kind := widget_kind(g, w); kind.scene_save_text != nil {
		//* A widget with its own scene text carries a whole model there.
		text := kind.scene_save_text(g, w.id, w)
		if text != "" {
			scene_save_line(builder, depth, "text")
			strings.write_byte(builder, '"')
			scene_save_write_escaped(builder, text)
			strings.write_byte(builder, '"')
			strings.write_byte(builder, '\n')
		}
		delete(text)
	} else {
		text := scene_save_text_of(w)
		if text != "" {
			scene_save_line(builder, depth, "text")
			strings.write_byte(builder, '"')
			scene_save_write_escaped(builder, text)
			strings.write_byte(builder, '"')
			strings.write_byte(builder, '\n')
		}
	}

	fields := style_fields_of(&w.style)
	text_fields := text_fields_of(&w.style.text)

	//* Colour rectangles always save their fill, including transparent.
	if w.type == .ColorRect {
		scene_save_line(builder, depth, "bg")
		scene_save_write_colour(builder, scene_save_fill_of(w))
		strings.write_byte(builder, '\n')
	} else if .BG in fields {
		scene_save_line(builder, depth, "bg")
		scene_save_write_colour(builder, w.style.box.bg_color)
		strings.write_byte(builder, '\n')
	}

	if w.type == .TextureRect {
		#partial switch d in w.data {
		case Texture_Rect_Data:
			scene_save_write_texture(builder, depth, d.texture_path)
		}
	}

	if w.type == .NinePatchRect {
		#partial switch d in w.data {
		case Nine_Patch_Data:
			scene_save_write_texture(builder, depth, d.texture_path)

			patch := d.patch
			scene_save_line(builder, depth, "patch")
			scene_save_write_numbers(builder, patch[:])
			strings.write_byte(builder, '\n')

			if d.source != (Rect{}) {
				source := [4]f32{d.source.x, d.source.y, d.source.w, d.source.h}
				scene_save_line(builder, depth, "source")
				scene_save_write_numbers(builder, source[:])
				strings.write_byte(builder, '\n')
			}

			scene_save_line(builder, depth, "tint")
			scene_save_write_colour(builder, d.tint)
			strings.write_byte(builder, '\n')

			if d.horizontal_edge != .Stretch {
				scene_save_line(builder, depth, "horizontal_edge")
				scene_save_write_nine_patch_edge(builder, d.horizontal_edge)
				strings.write_byte(builder, '\n')
			}
			if d.vertical_edge != .Stretch {
				scene_save_line(builder, depth, "vertical_edge")
				scene_save_write_nine_patch_edge(builder, d.vertical_edge)
				strings.write_byte(builder, '\n')
			}
			if d.centre_mode != .Stretch {
				scene_save_line(builder, depth, "centre_mode")
				switch d.centre_mode {
				case .Disabled:
					strings.write_string(builder, "\"disabled\"")
				case .Tile:
					strings.write_string(builder, "\"tile\"")
				case .Stretch:
				}
				strings.write_byte(builder, '\n')
			}
		}
	}

	//* The scene format uses one border colour for all sides.
	if .Border in fields {
		scene_save_line(builder, depth, "border")
		scene_save_write_colour(builder, w.style.box.border_color[0])
		strings.write_byte(builder, '\n')
	}

	if .Border_Width in fields {
		scene_save_line(builder, depth, "border_width")
		scene_save_write_number(builder, w.style.box.border_width[0])
		strings.write_byte(builder, '\n')
	}

	if .Padding in fields {
		scene_save_line(builder, depth, "padding")
		scene_save_write_numbers(builder, w.style.box.content_margin[:])
		strings.write_byte(builder, '\n')
	}

	if .Corner_Radius in fields {
		scene_save_line(builder, depth, "corner_radius")
		scene_save_write_numbers(builder, w.style.box.corner_radius[:])
		strings.write_byte(builder, '\n')
	}

	if .Shadow in fields {
		scene_save_line(builder, depth, "shadow")
		scene_save_write_colour(builder, w.style.box.shadow_color)
		strings.write_byte(builder, '\n')

		scene_save_line(builder, depth, "shadow_size")
		scene_save_write_number(builder, w.style.box.shadow_size)
		strings.write_byte(builder, '\n')

		offset := [2]f32{w.style.box.shadow_offset.x, w.style.box.shadow_offset.y}
		scene_save_line(builder, depth, "shadow_offset")
		scene_save_write_numbers(builder, offset[:])
		strings.write_byte(builder, '\n')
	}

	if .Shadow_Spread in fields {
		scene_save_line(builder, depth, "shadow_spread")
		scene_save_write_number(builder, w.style.box.shadow_spread)
		strings.write_byte(builder, '\n')
	}

	if .Shadow_Inset in fields {
		scene_save_line(builder, depth, "shadow_inset")
		strings.write_string(builder, w.style.box.shadow_inset ? "true" : "false")
		strings.write_byte(builder, '\n')
	}

	if .Backdrop_Blur in fields {
		scene_save_line(builder, depth, "backdrop_blur")
		scene_save_write_number(builder, w.style.box.backdrop_blur)
		strings.write_byte(builder, '\n')
	}

	if .Optics_Refraction in fields {
		scene_save_line(builder, depth, "optics_refraction")
		scene_save_write_number(builder, w.style.box.optics.refraction)
		strings.write_byte(builder, '\n')
	}

	if .Optics_Dispersion in fields {
		scene_save_line(builder, depth, "optics_dispersion")
		scene_save_write_number(builder, w.style.box.optics.dispersion)
		strings.write_byte(builder, '\n')
	}

	if .Optics_Fresnel in fields {
		scene_save_line(builder, depth, "optics_fresnel")
		scene_save_write_number(builder, w.style.box.optics.fresnel)
		strings.write_byte(builder, '\n')
	}

	if .Optics_Saturation in fields {
		scene_save_line(builder, depth, "optics_saturation")
		scene_save_write_number(builder, w.style.box.optics.saturation)
		strings.write_byte(builder, '\n')
	}

	if .Colour in text_fields {
		scene_save_line(builder, depth, "colour")
		scene_save_write_colour(builder, w.style.text.colour)
		strings.write_byte(builder, '\n')
	}

	if .Size in text_fields {
		scene_save_line(builder, depth, "font_size")
		scene_save_write_number(builder, w.style.text.size)
		strings.write_byte(builder, '\n')
	}

	//* Save a font family only when it can be resolved by the GUI.
	if .Family in text_fields {
		fam := font_family_get(g, w.style.text.family)
		if fam != nil {
			scene_save_line(builder, depth, "font")
			strings.write_byte(builder, '"')
			scene_save_write_escaped(builder, fam.name)
			strings.write_byte(builder, '"')
			strings.write_byte(builder, '\n')
		}
	}

	if !(.Visible in w.state) {
		scene_save_line(builder, depth, "visible")
		strings.write_string(builder, "false")
		strings.write_byte(builder, '\n')
	}

	if w.interactive != widget_type_interactive(w.type) {
		scene_save_line(builder, depth, "interactive")
		strings.write_string(builder, w.interactive ? "true" : "false")
		strings.write_byte(builder, '\n')
	}

	if w.base_min_size != (Vec2{}) {
		size := [2]f32{w.base_min_size.x, w.base_min_size.y}
		scene_save_line(builder, depth, "min_size")
		scene_save_write_numbers(builder, size[:])
		strings.write_byte(builder, '\n')
	}

	if w.custom_min_size != (Vec2{}) {
		size := [2]f32{w.custom_min_size.x, w.custom_min_size.y}
		scene_save_line(builder, depth, "custom_min_size")
		scene_save_write_numbers(builder, size[:])
		strings.write_byte(builder, '\n')
	}
}

//* Returns the text value represented by a widget in the scene file.
scene_save_text_of :: proc(w: ^Widget) -> string {
	#partial switch d in w.data {
	case Label_Data:
		return d.text
	case Button_Data:
		return d.text
	case Text_Box_Data:
		return d.text
	case Check_Box_Data:
		return d.text
	case Menu_Button_Data:
		return d.text
	case Link_Button_Data:
		return d.text
	case Rich_Text_Data:
		return d.text
	case Dialog_Data:
		return d.text
	case Toast_Data:
		return d.text
	case Toggle_Switch_Data:
		return d.text
	case Tooltip_Data:
		return d.text
	case Search_Field_Data:
		//* Save the placeholder shown when the search field is empty.
		return d.placeholder
	case Emoji_Picker_Data:
		return d.emoji
	case Command_Palette_Data:
		//* Save the palette's filter text.
		return d.text
	case Chat_Input_Data:
		//* Save the chat input's field text.
		return d.text
	case Rich_Text_Editor_Data:
		if d.state != nil {return d.state.text}
	}
	return ""
}

//* Returns the fill colour of a colour rectangle.
scene_save_fill_of :: proc(w: ^Widget) -> Colour {
	#partial switch d in w.data {
	case Color_Rect_Data:
		return d.colour
	}
	return {}
}

//* Writes indentation using four spaces per tree level.
scene_save_indent :: proc(builder: ^strings.Builder, depth: int) {
	for i in 0 ..< depth * 4 {
		strings.write_byte(builder, ' ')
	}
}

//* Writes an indented property name and separator.
scene_save_line :: proc(builder: ^strings.Builder, depth: int, key: string) {
	scene_save_indent(builder, depth)
	strings.write_string(builder, key)
	strings.write_string(builder, " = ")
}

//* Writes a list of numbers in the format expected by the loader.
scene_save_write_numbers :: proc(builder: ^strings.Builder, values: []f32) {
	strings.write_byte(builder, '{')
	for value, index in values {
		if index > 0 {strings.write_string(builder, ", ")}
		scene_save_write_number(builder, value)
	}
	strings.write_byte(builder, '}')
}

//* Writes a float using its shortest round-trippable representation.
scene_save_write_number :: proc(builder: ^strings.Builder, value: f32) {
	buf: [64]u8
	text := strconv.write_float(buf[:], f64(value), 'g', -1, 32)
	if len(text) > 0 && text[0] == '+' {text = text[1:]}
	strings.write_string(builder, text)
}

scene_save_write_texture :: proc(builder: ^strings.Builder, depth: int, path: string) {
	if path == "" {return}
	scene_save_line(builder, depth, "texture")
	strings.write_byte(builder, '"')
	scene_save_write_escaped(builder, path)
	strings.write_byte(builder, '"')
	strings.write_byte(builder, '\n')
}

//* Writes a colour as four float values.
scene_save_write_colour :: proc(builder: ^strings.Builder, colour: Colour) {
	values := [4]f32{colour.r, colour.g, colour.b, colour.a}
	scene_save_write_numbers(builder, values[:])
}

//* Writes an edge rendering mode as a quoted scene value.
scene_save_write_nine_patch_edge :: proc(
	builder: ^strings.Builder,
	mode: Nine_Patch_Edge_Mode,
) {
	switch mode {
	case .Stretch:
		strings.write_string(builder, "\"stretch\"")
	case .Tile:
		strings.write_string(builder, "\"tile\"")
	}
}

//* Escapes text for the scene format. The caller writes the quotes.
scene_save_write_escaped :: proc(builder: ^strings.Builder, text: string) {
	for i in 0 ..< len(text) {
		c := text[i]
		switch c {
		case '\\':
			strings.write_string(builder, "\\\\")
		case '"':
			strings.write_string(builder, "\\\"")
		case '\n':
			strings.write_string(builder, "\\n")
		case '\t':
			strings.write_string(builder, "\\t")
		case '\r':
			strings.write_string(builder, "\\r")
		case:
			strings.write_byte(builder, c)
		}
	}
}
