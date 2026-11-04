//* == The options of the widgets ==
//* Every kind of widget has its own options, and they all share the
//* options that every widget has. The shared ones are in Base_Opts, so
//* a program only has to name the ones that are different.
//
//*   GUI.Make_Button(g, parent, GUI.Button_Opts{
//*       Base_Opts = GUI.Base_Opts{name = "ok"},
//       text = "OK",
//   })

package GUI

//* The options that every widget has.
Base_Opts :: struct {
	name:          string,
	preset:        Anchor_Preset,
	anchors:       Anchor,
	offsets:       Offset,
	min_size:      Vec2,
	max_size:      Vec2,
	weight:        f32,
	fixed:         bool,
	separation:    f32,
	draggable:     bool,
	style:         Style,
	use_theme:     bool,
	variation:     string,
	hidden:        bool,

	//* The control features.
	mouse_filter:  Mouse_Filter,
	focus_mode:    Focus_Mode,
	tab_index:     int,
	size_flags_h:  Size_Flags,
	size_flags_v:  Size_Flags,
	stretch_ratio: f32,
	clip_contents: Clip_Contents,
	tooltip:       string,
	z_index:       int,
}

//* The options of the primitive, made from the shared ones.
base_widget_opts :: proc(base: Base_Opts) -> Widget_Opts {
	return Widget_Opts {
		name = base.name,
		preset = base.preset,
		anchors = base.anchors,
		offsets = base.offsets,
		min_size = base.min_size,
		custom_max_size = base.max_size,
		weight = base.weight,
		fixed = base.fixed,
		separation = base.separation,
		draggable = base.draggable,
		style = base.style,
		use_theme = base.use_theme,
		variation = base.variation,
		hidden = base.hidden,
		mouse_filter = base.mouse_filter,
		focus_mode = base.focus_mode,
		tab_index = base.tab_index,
		size_flags_h = base.size_flags_h,
		size_flags_v = base.size_flags_v,
		stretch_ratio = base.stretch_ratio,
		clip_contents = base.clip_contents,
		tooltip = base.tooltip,
		z_index = base.z_index,
	}
}

//* A style with a background, a border and a margin on every side. It
//* is the shape most widgets want, so it is made here.
base_style :: proc(bg: Colour, border: Colour, width: f32, margin: f32) -> Style {
	return Style {
		box = StyleBox {
			bg_color = bg,
			border_color = {border, border, border, border},
			border_width = {width, width, width, width},
			content_margin = {margin, margin, margin, margin},
		},
	}
}
