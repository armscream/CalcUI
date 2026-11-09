package GUI

//* == widget options ==
//*   GUI.Make_Button(g, parent, GUI.Button_Opts{
//*       Base_Opts = GUI.Base_Opts{name = "ok"},
//       text = "OK",
//   })

//* The shared options are in Base_Opts, so
//* a program only has to name the ones that are different.

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
	//* How the widget takes the room of its parent along the horizontal
	//* axis, and along the vertical one. A widget that expands takes a
	//* share of the room that is left over, and a widget that does not
	//* expand takes only its minimum size. A widget that fills takes the
	//* room it is given, and a widget that shrinks takes only its
	//* minimum size and is centred in the room it would have had. The
	//* default of a widget is `.Fill` and `.Expand` on both axes, and a
	//* set of flags with nothing in it means the program says nothing
	//* about that axis.
	size_flags_h:  Size_Flags,
	size_flags_v:  Size_Flags,
	//* The share of the space of the parent the widget takes when there
	//* is room left over: the weight of the widget times this ratio. A
	//* ratio of 0 in the options is the same as saying nothing: the
	//* ratio of 1 is used. A ratio of 0 is set with
	//* `Widget_Set_Stretch_Ratio`.
	stretch_ratio: f32,
	//* The direction the widget grows in: from the left to the right or
	//* from the right to the left. A container that stacks its children
	//* along the horizontal axis puts them in the other order when the
	//* direction is from the right to the left. The default is to take
	//* the direction of the parent.
	layout_direction: Layout_Direction,
	clip_contents: Clip_Contents,
	tooltip:       string,
	z_index:       int,
	access_role:        Access_Role,
	access_name:        string,
	access_description: string,
}

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
		layout_direction = base.layout_direction,
		clip_contents = base.clip_contents,
		tooltip = base.tooltip,
		z_index = base.z_index,
		access_role = base.access_role,
		access_name = base.access_name,
		access_description = base.access_description,
	}
}

//* A style with a background, a border and a margin on every side.
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
