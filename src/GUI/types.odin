//* The GUI core: a retained widget tree, a layout pass and an input
//* model. It knows nothing about windows or renderers — it only produces
//* a Draw_List that a backend consumes.
package GUI

import "core:math"


import runa "./dependencies/Runa"
import virt "core:mem/virtual"

//* == Backend vtable ==
//* Declared here, implemented by the Backend package. The window handle
//* is a rawptr so no SDL type leaks into the core. The rules a backend
//* keeps to are in docs/contracts.md.
Backend :: struct {
	ctx:                    rawptr,
	create:                 proc(ctx, window: rawptr, w, h: i32) -> bool,
	destroy:                proc(ctx: rawptr),
	resize:                 proc(ctx: rawptr, w, h: i32) -> bool,
	upload_texture:         proc(ctx: rawptr, id: Texture_ID, pixels: []u8, w, h: i32) -> bool,
	//* Uploads the parts of a texture that changed, in one call. The
	//* pixels of each part are RGBA in rows, and they are only valid
	//* for the call. A backend that cannot do this gets the whole
	//* texture through upload_texture instead.
	upload_texture_regions: proc(ctx: rawptr, id: Texture_ID, regions: []Texture_Upload) -> bool,
	//* Gives a texture back. Called when the GUI gives the atlas up.
	destroy_texture:        proc(ctx: rawptr, id: Texture_ID),
	submit:                 proc(ctx: rawptr, dl: ^Draw_List),
	//* Renders a draw list into the window of a floating panel. The
	//* window is given a render target the first time it is used.
	submit_target:          proc(ctx: rawptr, dl: ^Draw_List, window: rawptr),
	//* Whether the backend can do the shape effects of the fragment
	//* shader: rounded corners, gradients. A backend that cannot does
	//* them on the CPU, with polygons.
	supports_shapes:        bool,
}

//* A part of a texture that goes up to the backend.
Texture_Upload :: struct {
	pixels: []u8,
	w, h, x, y: i32,
}

//* == GEO ==
Rect :: struct {
	x, y, w, h: f32,
}
Vec2 :: struct {
	x, y: f32,
}

//* == The arithmetic on a point ==
//* Odin has no operator overloading, so the arithmetic on a point is
//* done with these. They are here because the arithmetic on points is
//* most of the toolkit.

//* One point added to another.
vec2_add :: proc(a, b: Vec2) -> Vec2 {
	return Vec2{a.x + b.x, a.y + b.y}
}

//* One point taken away from another.
vec2_sub :: proc(a, b: Vec2) -> Vec2 {
	return Vec2{a.x - b.x, a.y - b.y}
}

//* A point scaled by a number.
vec2_scale :: proc(a: Vec2, s: f32) -> Vec2 {
	return Vec2{a.x * s, a.y * s}
}

//* A point added to a point in place.
vec2_add_to :: proc(a: ^Vec2, b: Vec2) {
	a.x += b.x
	a.y += b.y
}

//* A point taken away from a point in place.
vec2_sub_from :: proc(a: ^Vec2, b: Vec2) {
	a.x -= b.x
	a.y -= b.y
}

//* How long a point is.
vec2_length :: proc(a: Vec2) -> f32 {
	return math.sqrt(a.x * a.x + a.y * a.y)
}

//* == Colour -- linear RGBA, 0..1 ==
Colour :: struct {
	r, g, b, a: f32,
}

//* == Opaque resource handles ==
//* A texture is named by a number the backend gives it. Zero names
//* nothing; the atlas of the GUI is ATLAS_TEXTURE_ID.
Texture_ID :: distinct u32
INVALID_TEXTURE_ID :: Texture_ID(0)

//* The one texture of the whole UI: the white texel, the glyphs of
//* every font and the images all live in it.
ATLAS_TEXTURE_ID :: Texture_ID(1)

//* == Floating panels ==
//* A panel can be torn out of the dock tree. It then lives in a window
//* of its own, somewhere on the screen, and can be dragged anywhere.
Float_Panel :: struct {
	widget: Widget_ID, // the panel
	pos:    Vec2, // its top left, in screen pixels
	size:   Vec2, // its size, in pixels
	title:  string,
	draw:   Draw_List, // the list it is drawn into
}

//* == Widget Tree ==
Widget_Type :: enum {
	//* The ones CalcUI started with.
	Panel,
	Button,
	Label,
	Image,
	TextInput,
	ScrollArea,
	Split,
	Tabs,
	VBox, // children stacked vertically
	HBox, // children stacked horizontally

	//* Containers.
	GridContainer,
	MarginContainer,
	CenterContainer,
	PanelContainer,
	ScrollContainer,
	FlowContainer,
	AspectRatioContainer,
	TabContainer,

	//* Simple controls.
	ColorRect,
	TextureRect,
	NinePatchRect,
	ReferenceRect,
	RichTextLabel,
	TextEdit,
	ItemList,
	Tree,
	TabBar,
	HSeparator,
	VSeparator,
	MenuBar,

	//* Buttons.
	CheckBox,
	CheckButton,
	OptionButton,
	MenuButton,
	LinkButton,

	//* Range.
	HSlider,
	VSlider,
	SpinBox,
	ProgressBar,

	//* Popups.
	PopupMenu,
	PopupPanel,
	AcceptDialog,
	ConfirmationDialog,
	FileDialog,

	//* The widgets Godot does not have.
	Toast,
	CommandPalette,
	Rating,
	Segmented,
	ToggleSwitch,
	ComboBox,
	VirtualList,
	DataTable,
	DatePicker,
	TimePicker,
	ColorPicker,
	EmojiPicker,
	Accordion,
	ContextMenu,
	ChatInput,
	SearchField,
	NumberInput,
	Tooltip,

	//* The heavy features.
	Chart,
	NodeGraph,
	Canvas,
	FileViewer,
	RichTextEditor,
	VectorDrawing,
	AudioPlayer,
}

//* What a widget does with the mouse.
Mouse_Filter :: enum {
	//* The widget takes the mouse, and the events stop there.
	Stop,
	//* The widget takes the mouse, but the events go on to the widgets
	//* behind it.
	Pass,
	//* The widget does not take the mouse at all.
	Ignore,
}

//* How a widget gets the keyboard focus.
Focus_Mode :: enum {
	//* The widget cannot be focused.
	None,
	//* The widget is focused when it is clicked.
	Click,
	//* The widget is focused when it is clicked, and when the tab key
	//* reaches it.
	All,
}

//* Whether a widget cuts its children to its own rect.
Clip_Contents :: enum {
	//* The widget cuts its children to its own rect. This is what a
	//* widget gets when nothing is asked for, and it is the safe
	//* choice: a child that runs out of its parent is cut off.
	Default,
	//* The widget cuts its children to its own rect.
	On,
	//* The children of the widget are drawn outside of it.
	Off,
}

//* How a widget takes up the space of its parent. They are flags, so a
//* widget can have more than one of them.
Size_Flag :: enum u8 {
	//* The widget takes all the space it is given.
	Fill          = 1,
	//* The widget takes a share of the space that is left over.
	Expand        = 2,
	//* The widget keeps its minimum size and sits in the middle of the
	//* space it is given.
	Shrink_Center = 4,
}
Size_Flags :: bit_set[Size_Flag]

//* The direction the text of a widget runs in.
Layout_Direction :: enum {
	//* The direction of the parent.
	Inherit,
	//* The direction of the language of the platform.
	Locale,
	//* Left to right.
	LTR,
	//* Right to left.
	RTL,
}

//* A handle to a widget. It names the slot the widget has in the
//* table of the GUI and the generation of the widget that is in that
//* slot. A widget that is destroyed leaves a handle behind that names
//* nothing, and a widget that is made again in the same slot gets a
//* new generation, so the handle of the old one is never mistaken for
//* the handle of the new one.
Widget_ID :: struct {
	//* The slot of the widget. The first slot is 1, so that 0 is
	//* never the handle of a widget.
	index:      u32,
	//* How many times the slot has been used. Every widget that is
	//* made in a slot gets a generation of its own.
	generation: u32,
}

//* The handle of a widget that does not exist. It is also the zero
//* value of a handle, so a handle that was never set names nothing.
INVALID_WIDGET_ID :: Widget_ID {
	index      = 0,
	generation = 0,
}

//* == Text ==
//* How the text of a widget sits in its box and how it is broken into
//* lines.
Text_Align :: enum {
	Left,
	Center,
	Right,
	Fill, // both edges are pushed out to the box
}

//* Where the text sits in its box, vertically.
V_Align :: enum {
	Top,
	Center,
	Bottom,
}

//* How the text is broken into lines.
Text_Wrap :: enum {
	Off, // the text stays on one line
	Word, // the text breaks at word boundaries
	Anywhere, // the text breaks anywhere, even inside a word
}

//* What is done to the string before it is laid out.
Text_Transform :: enum {
	None,
	Upper,
	Lower,
	Capitalize, // the first letter of every word
}

//* What happens when the text does not fit.
Text_Overrun :: enum {
	None, // the text runs out of the box
	Ellipsis, // the text is cut short and an ellipsis is added
	Words, // the text is cut short at a word boundary
}

Widget_State :: bit_set[Widget_State_Flag]
Widget_State_Flag :: enum {
	Visible,
	Enabled,
	Hovered,
	Pressed,
	Focused,
}

//* == Declarative layout input ==
//* Anchor positions a widget inside its parent. The zero value of
//* Widget_Opts has to mean something useful, so the anchor comes from
//* a preset (Fill by default) and the raw anchors are only used for
//* .Custom.
Anchor_Preset :: enum {
	Fill, // the whole parent
	Top_Left,
	Top_Right,
	Bottom_Left,
	Bottom_Right,
	Center,
	Left, // left half, full height
	Right,
	Top, // top half, full width
	Bottom,
	Custom,
}

Anchor :: struct {
	left, top, right, bottom: f32,
} 	// 0..1
Offset :: struct {
	left, top, right, bottom: f32,
} 	// pixels
Grow :: enum {
	Begin,
	End,
	Both,
}

Dock_Zone :: enum {
	None,
	Left,
	Right,
	Top,
	Bottom,
	Center,
}

//* == Docking ==
//* The most children a dock plan can describe. A split with more
//* children than this still lays out as usual; the plan only previews
//* the first MAX_DOCK_SLOTS of them.
MAX_DOCK_SLOTS :: 16
//* The most tabs a tab host can show.
MAX_TABS :: 16

//* What a drop would do.
Dock_Kind :: enum {
	None,
	Split, // the panel becomes a slice of a split
	Tabs, // the panel becomes a tab of the target
	Swap, // the panel and the target exchange their slots
	Fill, // the panel takes the empty space of the target
}

//* A drop, worked out before it happens. The preview draws this plan
//* and the drop applies it, so the two always agree.
Dock_Plan :: struct {
	kind:              Dock_Kind,
	axis:              Split_Direction,

	//* The container the drop happens on.
	container:         Widget_ID,

	//* The split the drop would create. When `create_split` is set the
	//* container is replaced by a new split holding `children`.
	create_split:      bool,
	children:          [MAX_DOCK_SLOTS]Widget_ID,
	weights:           [MAX_DOCK_SLOTS]f32,
	count:             int,
	panel_index:       int,

	//* The tab host the drop would create. When `create_tabs` is set the
	//* container becomes the first tab of a new host.
	create_tabs:       bool,
	tab_host:          Widget_ID,
	tab_index:         int,

	//* The swap the drop would perform: the panel takes the target's
	//* slot and the target takes the panel's.
	swap_panel_parent: Widget_ID,
	swap_panel_index:  int,
	swap_host_parent:  Widget_ID,
	swap_host_index:   int,

	//* Where everything ends up.
	preview:           Rect, // the panel's content
	tab_button:        Rect, // the button the panel's tab would get
	tab_bar:           Rect, // the strip the tabs live in
	tab_widgets:       [MAX_TABS]Widget_ID, // the tabs the strip would show
	tab_widget_count:  int,
	tab_buttons:       [MAX_TABS]Rect,
	tab_button_count:  int,
	others:            [MAX_DOCK_SLOTS]Rect, // the content that gets moved
	other_count:       int,
}

//* Resolves a preset into raw anchors.
anchor_of :: proc(preset: Anchor_Preset, custom: Anchor) -> Anchor {
	switch preset {
	case .Fill:
		return Anchor{0, 0, 1, 1}
	case .Top_Left:
		return Anchor{0, 0, 0, 0}
	case .Top_Right:
		return Anchor{1, 0, 1, 0}
	case .Bottom_Left:
		return Anchor{0, 1, 0, 1}
	case .Bottom_Right:
		return Anchor{1, 1, 1, 1}
	case .Center:
		return Anchor{0.5, 0.5, 0.5, 0.5}
	case .Left:
		return Anchor{0, 0, 0, 1}
	case .Right:
		return Anchor{1, 0, 1, 1}
	case .Top:
		return Anchor{0, 0, 1, 0}
	case .Bottom:
		return Anchor{0, 1, 1, 1}
	case .Custom:
		return custom
	}
	return Anchor{0, 0, 1, 1}
}

//* == Style ==
//* The appearance of a widget. A field that is not in `set` comes from
//* the theme, or from the GUI's own default; when `set` is empty the
//* fields that are set are worked out from their values, so a style
//* only has to name what it changes.
//
//* The box is the box around the widget: its background, its border,
//* its corners and the space kept free inside it. The text is the
//* style of the text inside it.
Style :: struct {
	set:  bit_set[Style_Field],
	box:  StyleBox,
	text: Text_Style,
}

//* The style of a widget as it was last worked out, and the things it
//* was worked out from. The style is worked out again when any of them
//* changed, so a program that writes to a widget itself is not left
//* with a style that is out of date.
Style_Cache :: struct {
	//* The style as it was worked out.
	style:           Style,
	//* The style of the widget in the state it is in, and the style of
	//* the theme for that state. They are the room the styles of the
	//* states are worked out in, so that a style is not copied for
	//* every widget of every frame.
	state:           Style,
	theme_state:     Style,
	//* The style of the widget itself.
	style_of_widget: Style,
	//* The style every widget starts from.
	default_style:   Style,
	//* Whether the widget took the theme.
	use_theme:       bool,
	//* The name of the variation the widget took.
	variation:       string,
	//* The number of the look of the GUI. It goes up when the theme or
	//* the default style changes.
	epoch:           int,
	//* Whether there is a style to give back.
	valid:           bool,
}

//* The fields of a style. The bit set says which of them are set.
Style_Field :: enum {
	BG,
	Border,
	Border_Width,
	Padding,
	Corner_Radius,
	Shadow,
	Expand_Margin,
	Text,
}

//* == Text style ==
//* How the text of a widget looks. The zero value means "whatever the
//* GUI's default is", so a widget that says nothing about its text
//* still looks right.
//
//* A field that is not in `set` comes from the theme, or from the
//* built-in default. When `set` is empty the fields that are set are
//* worked out from their values, the same way a style's fields are.
Text_Style :: struct {
	set:             bit_set[Text_Field],

	//* The typeface and its size. A family of 0 is the GUI's default
	//* family; a size of 0 is the default size.
	family:          Font_Family_ID,
	size:            f32,

	//* The ink. A colour of alpha 0 is "not set".
	colour:          Colour,
	hover_colour:    Colour,
	pressed_colour:  Colour,
	disabled_colour: Colour,
	focus_colour:    Colour,

	//* How the text sits in its box.
	align:           Text_Align,
	valign:          V_Align,

	//* The lines.
	wrap:            Text_Wrap,
	spacing:         f32, // extra pixels between the lines

	//* What is done to the string before it is laid out.
	transform:       Text_Transform,

	//* What happens when the text does not fit.
	overrun:         Text_Overrun,
	clip:            bool,

	//* The decorations. The outline is drawn under the text and the
	//* shadow under that.
	outline_colour:  Colour,
	outline_size:    f32,
	shadow_colour:   Colour,
	shadow_offset:   Vec2,
}

//* The fields of a text style. The bit set says which of them are set.
Text_Field :: enum {
	Family,
	Size,
	Colour,
	Hover_Colour,
	Pressed_Colour,
	Disabled_Colour,
	Focus_Colour,
	Align,
	VAlign,
	Wrap,
	Spacing,
	Transform,
	Overrun,
	Clip,
	Outline_Colour,
	Outline_Size,
	Shadow_Colour,
	Shadow_Offset,
}

//* == Theme ==
//* The look of every kind of widget, in one place. A theme has a style
//* for every widget type, a style for every state a widget can be in,
//* and named variations of a type.
Theme :: struct {
	//* The look of every widget type.
	types:      map[Widget_Type]Theme_Type,
	//* The look of the classes that are not one of the built-in types.
	//* A class of a program's own is named here, and the name of the
	//* class is what the theme looks it up by.
	classes:    map[string]Theme_Type,
	//* The named variations of a type, e.g. "danger" for a Button.
	variations: map[string]Variation,
	//* The family and the size the theme's text uses. A family of 0 is
	//* the GUI's default family; a size of 0 is the default size.
	family:     Font_Family_ID,
	size:       f32,
	//* The GUI the theme is on. A theme that is changed while it is on
	//* a GUI says so, so that the widgets that take the theme are
	//* measured and drawn again.
	owner:      ^GUI,
}

//* The look of one kind of widget. Every kind of item is named, the
//* way Godot does it, so a type can hold several style boxes, several
//* colours and several fonts.
Theme_Type :: struct {
	styleboxes: map[string]StyleBox,
	colors:     map[string]Colour,
	constants:  map[string]f32,
	fonts:      map[string]Font_ID,
	font_sizes: map[string]f32,
	icons:      map[string]Texture_ID,
	//* The text style of the type.
	text:       Text_Style,
	states:     State_Styles,
}

//* A named variation of a widget type. Its style is applied over the
//* style of the type it varies from.
Variation :: struct {
	of:        Widget_Type,
	style:     Style,
	states:    State_Styles,
	//* The named items of the variation.
	colors:    map[string]Colour,
	constants: map[string]f32,
}

//* The style of the states a widget can be in. Each one is sparse: it
//* changes what it names and leaves the rest alone.
State_Styles :: struct {
	hover:    Style,
	pressed:  Style,
	disabled: Style,
	focus:    Style,
}

//* The state a widget is in, for the theme's sake.
Style_State :: enum {
	Normal,
	Hovered,
	Pressed,
	Disabled,
	Focused,
}

Split_Direction :: enum {
	Horizontal,
	Vertical,
}

//* Odin unions name their variants by type, so each payload gets its own
//* type. The core switches on the active variant and only reads the
//* fields of the matching case.
None_Data :: struct {}

Widget_Data :: union {
	None_Data,
	Button_Data,
	Label_Data,
	Split_Data,
	Tabs_Data,
	Text_Input_Data,
	Grid_Data,
	Margin_Data,
	Scroll_Data,
	Aspect_Data,
	Tab_Container_Data,
	Check_Box_Data,
	Check_Button_Data,
	Link_Button_Data,
	Menu_Button_Data,
	Option_Button_Data,
	Slider_Data,
	Spin_Box_Data,
	Progress_Bar_Data,
	Color_Rect_Data,
	Texture_Rect_Data,
	Nine_Patch_Data,
	Item_List_Data,
	Tree_Data,
	Text_Edit_Data,
	Rich_Text_Data,
	Popup_Menu_Data,
	Dialog_Data,
	File_Dialog_Data,
	Separator_Data,

	//* The widgets that came later. The ones that hold a lot of data
	//* keep it behind a pointer, so that a widget stays small.
	Toast_Data,
	Command_Palette_Data,
	Rating_Data,
	Segmented_Data,
	Toggle_Switch_Data,
	Combo_Box_Data,
	Virtual_List_Data,
	Data_Table_Data,
	Date_Picker_Data,
	Time_Picker_Data,
	Color_Picker_Data,
	Emoji_Picker_Data,
	Accordion_Data,
	Context_Menu_Data,
	Chat_Input_Data,
	Search_Field_Data,
	Number_Input_Data,
	Tooltip_Data,
	Chart_Data,
	Node_Graph_Data,
	Canvas_Data,
	File_Viewer_Data,
	Rich_Text_Editor_Data,
	Vector_Drawing_Data,
	Audio_Player_Data,

	//* The data of a widget that a program brought of its own. The core
	//* never looks inside it.
	Custom_Data,
}

Button_Data :: struct {
	text:     string,
	on_click: proc(g: ^GUI, id: Widget_ID),
}
Label_Data :: struct {
	text: string,
}
Split_Data :: struct {
	direction: Split_Direction,
}
Tabs_Data :: struct {
	active: int,
}

//* A text field's own state: the buffer, the caret and the selection
//* (as byte offsets into the buffer).
Text_Input_Data :: struct {
	text:      string,
	caret:     int,
	sel_start: int,
	sel_end:   int,
}

Widget :: struct {
	id:               Widget_ID,
	type:             Widget_Type,
	//* The class of the widget: what it does. A widget of a program's
	//* own has a class of its own; a widget that is built in has the
	//* class of its kind.
	class:            Widget_Class_ID,
	name:             string,
	parent:           Widget_ID,

	//* Whether the widget is being destroyed. A widget that is
	//* destroyed says so before anything else happens, so that it
	//* cannot be destroyed twice.
	freeing:          bool,

	// Intrusive child list: O(1) detach/attach, which is what docking
	// is built on.
	first_child:      Widget_ID,
	last_child:       Widget_ID,
	prev_sibling:     Widget_ID,
	next_sibling:     Widget_ID,
	anchors:          Anchor,
	offsets:          Offset,
	grow_h:           Grow,
	grow_v:           Grow,
	min_size:         Vec2,
	//* The smallest size the program asked for. The size of the text
	//* of the widget is added to it by the measure pass, so the size of
	//* a widget whose text got shorter goes down again.
	base_min_size:    Vec2,
	weight:           f32, // share of the parent's split axis
	separation:       f32, // gap between children of a VBox / HBox
	draggable:        bool, // shows a title bar and can be dragged to dock

	//* The size the panel was pulled to, in pixels. A panel that was
	//* resized by hand keeps that size: the layout gives it this
	//* instead of a share of the space. The flags say which axis the
	//* size belongs to.
	manual_size:      Vec2,
	manual_w:         bool,
	manual_h:         bool,

	// Resolved by the layout pass.
	rect:             Rect,
	content:          Rect,
	clip:             Rect,
	style:            Style,
	//* Whether the widget takes the theme's style for its type, and
	//* which named variation of that type it is.
	use_theme:        bool,
	variation:        string,
	state:            Widget_State,
	data:             Widget_Data,

	//* == The control features ==

	//* What the widget does with the mouse.
	mouse_filter:     Mouse_Filter,
	//* How the widget gets the keyboard focus.
	focus_mode:       Focus_Mode,
	//* The widgets the arrow keys move to: left, top, right, bottom.
	focus_neighbour:  [4]Widget_ID,
	//* The widgets the tab key moves to.
	focus_next:       Widget_ID,
	focus_previous:   Widget_ID,
	//* The place of the widget in the order of the tab key.
	tab_index:        int,
	//* How the widget takes up the space of its parent.
	size_flags_h:     Size_Flags,
	size_flags_v:     Size_Flags,
	//* The share of the space of the parent when more than one widget
	//* wants it.
	stretch_ratio:    f32,
	//* Whether the children of the widget are cut to its own rect.
	clip_contents:    bool,
	//* The text that is shown when the pointer rests on the widget.
	tooltip_text:     string,
	//* The size the widget asks for, and the size it never goes past.
	custom_min_size:  Vec2,
	custom_max_size:  Vec2,
	//* The order the widget is drawn in. A widget with a higher number
	//* is drawn later, so it lies on top of the others.
	z_index:          int,
	//* The transform of the widget: the turn around its pivot, and how
	//* much it is scaled.
	rotation:         f32,
	scale:            Vec2,
	pivot_offset:     Vec2,
	//* The direction the text of the widget runs in.
	layout_direction: Layout_Direction,
	//* The signals of the widget.
	signals:          Signals,

	//* == The invalidation ==
	//* What is out of date about the widget itself, and what is out of
	//* date about the whole branch under it. The measure pass and the
	//* layout pass use the second one to leave a branch alone that
	//* nothing happened to.
	dirty:            Dirty_Flags,
	subtree_dirty:    Dirty_Flags,

	//* == The style cache ==
	//* The style of the widget as it was last worked out, and the
	//* things it was worked out from. The style is worked out again
	//* when any of them changed, so a program that writes to the style
	//* of a widget itself is not left with a stale one.
	style_cache:      Style_Cache,
}

//* == Widget creation options ==
//* Everything a widget needs at birth. Runtime changes go through the
//* setters (see setter.odin), so that the toolkit knows what a change
//* made stale.
Widget_Opts :: struct {
	name:            string,
	preset:          Anchor_Preset,
	anchors:         Anchor, // only used when preset is .Custom
	offsets:         Offset,
	min_size:        Vec2,
	weight:          f32,
	fixed:           bool, // keep min_size, take none of the parent's free space
	separation:      f32, // gap between the children of a VBox / HBox
	draggable:       bool, // draw a title bar and allow drag-to-dock
	style:           Style,
	use_theme:       bool, // take the theme's style for this widget type
	variation:       string, // a named variation of the widget type
	hidden:          bool,
	split:           Split_Direction,
	text:            string,
	on_click:        proc(g: ^GUI, id: Widget_ID),

	//* == The control features ==
	mouse_filter:    Mouse_Filter,
	focus_mode:      Focus_Mode,
	tab_index:       int,
	size_flags_h:    Size_Flags,
	size_flags_v:    Size_Flags,
	stretch_ratio:   f32,
	clip_contents:   Clip_Contents,
	tooltip:         string,
	custom_min_size: Vec2,
	custom_max_size: Vec2,
	z_index:         int,
}

//* == Resizing ==
//* A dockable panel can be resized by pulling on its edges or on its
//* corners. The edges are the grips: a press on one starts a resize
//* and the edge follows the pointer from then on.

//* The edges of a panel that can be pulled.
Resize_Edge :: enum {
	Left,
	Right,
	Top,
	Bottom,
}

//* The edges a resize holds.
Resize_Edges :: bit_set[Resize_Edge]

//* A resize in progress.
Resize_State :: struct {
	active:      bool,
	widget:      Widget_ID, // the panel being resized
	edges:       Resize_Edges, // the edges that are being pulled
	origin:      Vec2, // where the pointer went down
	last:        Vec2, // where the pointer was at the last step
	float_index: int, // the floating panel it lives in, or FLOAT_NONE
}

//* The cursor the pointer asks for. The platform makes the cursor
//* that goes with it.
Cursor :: enum {
	Default,
	//* The pointer that says that something can be picked.
	Pointer,
	//* The pointer that says that text can be written.
	Text,
	//* The pointer that says that a place can be aimed at.
	Crosshair,
	//* The pointer that says that the thing is busy.
	Wait,
	//* The pointer that says that the thing cannot be used.
	Not_Allowed,
	//* The pointer that says that the thing can be moved.
	Grab,
	//* The pointer that says that the thing is being moved.
	Grabbing,
	//* The pointer that says that the thing is being resized.
	Resize_NS,
	Resize_W,
	Resize_E,
	Resize_N,
	Resize_S,
	Resize_NW,
	Resize_NE,
	Resize_SW,
	Resize_SE,
}

//* == Drag state ==
//* A drag carries a panel over the tree. It is armed when the pointer
//* goes down on a drag handle and becomes active once the pointer has
//* moved far enough.
Drag_State :: struct {
	active:      bool,
	armed:       bool, // the pointer is down on a handle, but has not moved
	origin:      Vec2, // where the pointer went down
	widget:      Widget_ID, // the widget being dragged
	target:      Widget_ID, // the container under the pointer
	tab_host:    Widget_ID, // the container that would take the panel as a tab
	zone:        Dock_Zone, // which edge of the target
	kind:        Dock_Kind, // what the drop would do
	grab:        Vec2, // pointer offset inside the dragged widget
	pos:         Vec2, // pointer position, in screen pixels
	ghost:       Rect, // where the dragged widget is drawn
	size:        Vec2, // the size of the widget when the drag started
	slot:        Rect, // the slot the widget came from
	swap:        bool, // the pointer asked for a swap instead of a tab
	float_index: int, // the floating panel being moved, or -1
	plan:        Dock_Plan,
}

//* == GUI state ==
GUI :: struct {
	arena:                     virt.Arena,
	frame_arena:               virt.Arena,
	//* The table of the widgets. Every widget that was ever made has a
	//* slot in it; the slot holds the widget itself.
	widgets:                   [dynamic]^Widget,
	//* How many times each slot of the table has been used. The
	//* generation of a widget is the number of its slot, so a widget
	//* that is made again in a slot that was used before gets a new
	//* handle.
	widget_generations:        [dynamic]u32,
	//* The slots of the table that are free. A widget that is made
	//* again takes one of them, so that the table does not grow for
	//* ever.
	free_widgets:              [dynamic]u32,
	root:                      Widget_ID,
	viewport:                  Rect,
	//* Where the main window is on the screen, in screen pixels. A
	//* panel dropped outside of it floats instead of docking.
	window_rect:               Rect,

	//* The panels that were torn out of the tree. Each one has a
	//* window of its own.
	floats:                    [dynamic]Float_Panel,
	events:                    [dynamic]Event,
	pointer:                   Vec2,
	global_pointer:            Vec2,
	//* Whether the pointer has ever been moved. The widget under the
	//* pointer is looked up again when the tree moves under it, but
	//* only when the pointer is known.
	pointer_known:             bool,
	lmb_down:                  bool,
	lmb_pressed:               bool,
	lmb_released:              bool,
	mods:                      Mods,
	hot:                       Widget_ID,
	active:                    Widget_ID,
	focused:                   Widget_ID,
	//* The slider that is being moved, when the pointer is on one.
	slider_active:             Widget_ID,
	quit_requested:            bool,
	drag:                      Drag_State,
	resize:                    Resize_State,
	//* The panel whose grip the pointer is on, and the edges of it.
	//* The cursor follows from those edges.
	resize_hover:              Widget_ID,
	resize_hover_edges:        Resize_Edges,
	cursor:                    Cursor,
	ime_text:                  string,
	draw:                      Draw_List,
	//* The list the draw pass is filling. It is the main window's
	//* list, or the list of the floating panel being drawn.
	target:                    ^Draw_List,
	backend:                   Backend,
	//* The one texture of the whole UI: the white texel, the glyphs of
	//* every font and the images all live in it.
	atlas:                     ^UI_Atlas,
	atlas_texture:             Texture_ID,
	//* How many times the atlas could not give out the space that was
	//* asked for. It goes up when the atlas is full.
	atlas_failures:            int,
	//* What has to be done again before the next frame is drawn. The
	//* flags say how much of the tree is affected.
	dirty:                     Dirty_Flags,
	//* Whether the whole tree is to be measured and laid out again
	//* from the top, whatever the flags say. This is the way out for a
	//* program that writes to a widget itself.
	full_layout:               bool,
	//* How many widgets the measure pass measured and the layout pass
	//* laid out in the last frame. They are there to see whether the
	//* work was done or left alone.
	measured_count:            int,
	arranged_count:            int,
	//* The number of the look of the GUI. It goes up when the theme or
	//* the default style changes, so that the styles that were worked
	//* out before are worked out again.
	style_epoch:               int,

	// Text.
	fonts:                     [dynamic]^Font,
	font_files:                [dynamic]^Font_File,
	font_families:             [dynamic]^Font_Family,
	//* The instance of a family at a size, so a size that changes at
	//* runtime does not make a new one every time.
	font_instances:            map[Font_Instance_Key]Font_ID,
	default_font:              Font_ID,
	default_family:            Font_Family_ID,
	default_font_size:         f32,
	shape_cache:               runa.Cache,
	cache_ready:               bool,
	upload_buf:                []u8,

	//* The theme: the look of every kind of widget, in one place.
	theme:                     ^Theme,
	//* The commands of the program, and the keys that do them.
	commands:                  Commands,
	//* The hooks of the kinds of the widgets. A widget that came after
	//* the first ones puts its hooks here.
	kinds:                     [dynamic]Widget_Kind,
	//* The classes of the widgets. Every widget belongs to a class: the
	//* class says what the widget does. A program that brings a widget
	//* of its own registers a class of its own here, and nothing
	//* outside the class has to be changed for the widget to work.
	classes:                   [dynamic]Widget_Class,
	//* The class of a kind of widget, by the type of the kind.
	class_by_type:             map[Widget_Type]Widget_Class_ID,
	//* The class of a kind of widget, by the name of the kind.
	class_by_name:             map[string]Widget_Class_ID,
	//* The connections to the signals of the widgets. A signal is rare
	//* and the table is short, so one table for the whole GUI is
	//* enough.
	signal_conns:              [dynamic]Signal_Conn_Entry,
	//* The constructors of the widgets for the scene loader. Every GUI
	//* has a table of its own, so that a program can bring a widget of
	//* its own without touching the other programs.
	scene_constructors:        [dynamic]Scene_Constructor,
	scene_defaults_registered: bool,
	//* How long the last frame took, in seconds. A widget that counts
	//* down needs it.
	dt:                        f32,
	//* The overlay that says what the program is doing.
	inspector:                 Inspector,
	//* The sizes of the texts that have been measured.
	measure_cache:             map[Measure_Key]Vec2,
	//* When the last frame was.
	last_frame:                i64,
	//* The clipboard, shared with the window.
	clipboard:                 Clipboard,
	//* The sound of the GUI, when it has one.
	audio:                     ^Audio_State,
	//* The style every widget starts from. It is the GUI's own look,
	//* used where the theme says nothing.
	default_style:             Style,
}

//* == Colour helper ==
RGBA :: proc(r, g, b, a: f32) -> Colour {
	return Colour{r = r, g = g, b = b, a = a}
}

//* A colour that is brighter (or darker) than this one. The alpha is
//* left alone.
Scale_Colour :: proc(c: Colour, f: f32) -> Colour {
	return Colour{r = c.r * f, g = c.g * f, b = c.b * f, a = c.a}
}

//* The style of a piece of text: the ink, the size and the typeface. A
//* size of 0 is the GUI's default size and a family of 0 is the GUI's
//* default family.
Make_Text_Style :: proc(
	colour: Colour,
	size: f32 = 0,
	family: Font_Family_ID = INVALID_FONT_FAMILY_ID,
) -> Text_Style {
	return Text_Style{colour = colour, size = size, family = family}
}

//* == Scene file (declarative authoring) ==
UI_Scene :: struct {
	format: u32 `json:"format"`,
	name:   string `json:"name"`,
	root:   Node `json:"root"`,
}

Node :: struct {
	type:     string `json:"type"`, // "Panel" | "Label" | "Button" | ...
	name:     string `json:"name"`,
	text:     string `json:"text,omitempty"`,
	anchors:  Anchor `json:"anchors"`,
	offsets:  Offset `json:"offsets"`,
	style:    Style `json:"style,omitempty"`,
	children: []Node `json:"children,omitempty"`,
}
