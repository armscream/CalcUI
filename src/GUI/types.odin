//* The GUI core: a retained widget tree, a layout pass and an input
//* model. It knows nothing about windows or renderers — it only produces
//* a Draw_List that a backend consumes.
package GUI

import runa "./dependencies/Runa"
import virt "core:mem/virtual"

//* == Backend vtable ==
//* Declared here, implemented by the Backend package. The window handle
//* is a rawptr so no SDL type leaks into the core.
Backend :: struct {
	ctx:            rawptr,
	create:         proc(ctx, window: rawptr, w, h: i32) -> bool,
	destroy:        proc(ctx: rawptr),
	resize:         proc(ctx: rawptr, w, h: i32) -> bool,
	upload_texture: proc(ctx: rawptr, id: Texture_ID, pixels: []u8, w, h: i32) -> bool,
	submit:         proc(ctx: rawptr, dl: ^Draw_List),
	//* Renders a draw list into the window of a floating panel. The
	//* window is given a render target the first time it is used.
	submit_target:  proc(ctx: rawptr, dl: ^Draw_List, window: rawptr),
}

//* == GEO ==
Rect :: struct {
	x, y, w, h: f32,
}
Vec2 :: struct {
	x, y: f32,
}

//* == Colour -- linear RGBA, 0..1 ==
Colour :: struct {
	r, g, b, a: f32,
}

//* == Opaque resource handles ==
Texture_ID :: distinct u32
INVALID_TEXTURE_ID :: Texture_ID(0)

//* == Floating panels ==
//* A panel can be torn out of the dock tree. It then lives in a window
//* of its own, somewhere on the screen, and can be dragged anywhere.
Float_Panel :: struct {
	widget: Widget_ID, // the panel
	pos:    Vec2,      // its top left, in screen pixels
	size:   Vec2,      // its size, in pixels
	title:  string,
	draw:   Draw_List, // the list it is drawn into
}

//* == Widget Tree ==
Widget_Type :: enum {
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
}

Widget_ID :: distinct u32
INVALID_WIDGET_ID :: Widget_ID(0)

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
V_Align :: enum { Top, Center, Bottom }

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

Anchor :: struct { left, top, right, bottom: f32 } // 0..1
Offset :: struct { left, top, right, bottom: f32 } // pixels
Grow :: enum { Begin, End, Both }

Dock_Zone :: enum { None, Left, Right, Top, Bottom, Center }

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
	Tabs,  // the panel becomes a tab of the target
	Swap,  // the panel and the target exchange their slots
	Fill,  // the panel takes the empty space of the target
}

//* A drop, worked out before it happens. The preview draws this plan
//* and the drop applies it, so the two always agree.
Dock_Plan :: struct {
	kind: Dock_Kind,
	axis: Split_Direction,

	//* The container the drop happens on.
	container: Widget_ID,

	//* The split the drop would create. When `create_split` is set the
	//* container is replaced by a new split holding `children`.
	create_split: bool,
	children:     [MAX_DOCK_SLOTS]Widget_ID,
	weights:      [MAX_DOCK_SLOTS]f32,
	count:        int,
	panel_index:  int,

	//* The tab host the drop would create. When `create_tabs` is set the
	//* container becomes the first tab of a new host.
	create_tabs: bool,
	tab_host:    Widget_ID,
	tab_index:   int,

	//* The swap the drop would perform: the panel takes the target's
	//* slot and the target takes the panel's.
	swap_panel_parent: Widget_ID,
	swap_panel_index:  int,
	swap_host_parent:  Widget_ID,
	swap_host_index:   int,

	//* Where everything ends up.
	preview:     Rect, // the panel's content
	tab_button:  Rect, // the button the panel's tab would get
	tab_bar:     Rect, // the strip the tabs live in
	tab_widgets:      [MAX_TABS]Widget_ID, // the tabs the strip would show
	tab_widget_count: int,
	tab_buttons:      [MAX_TABS]Rect,
	tab_button_count: int,
	others:      [MAX_DOCK_SLOTS]Rect, // the content that gets moved
	other_count: int,
}

//* Resolves a preset into raw anchors.
anchor_of :: proc(preset: Anchor_Preset, custom: Anchor) -> Anchor {
	switch preset {
	case .Fill:         return Anchor{0, 0, 1, 1}
	case .Top_Left:     return Anchor{0, 0, 0, 0}
	case .Top_Right:    return Anchor{1, 0, 1, 0}
	case .Bottom_Left:  return Anchor{0, 1, 0, 1}
	case .Bottom_Right: return Anchor{1, 1, 1, 1}
	case .Center:       return Anchor{0.5, 0.5, 0.5, 0.5}
	case .Left:         return Anchor{0, 0, 0, 1}
	case .Right:        return Anchor{1, 0, 1, 1}
	case .Top:          return Anchor{0, 0, 1, 0}
	case .Bottom:       return Anchor{0, 1, 1, 1}
	case .Custom:       return custom
	}
	return Anchor{0, 0, 1, 1}
}

//* == Style ==
//* The appearance of a widget. A field that is not in `set` comes from
//* the theme, or from the GUI's own default; when `set` is empty the
//* fields that are set are worked out from their values, so a style
//* only has to name what it changes.
Style :: struct {
	set:          bit_set[Style_Field],
	bg:           Colour,
	border:       Colour,
	border_width: f32,
	padding:      [4]f32, // left, top, right, bottom
	text:         Text_Style,
}

//* The fields of a style. The bit set says which of them are set.
Style_Field :: enum {
	BG,
	Border,
	Border_Width,
	Padding,
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
	set: bit_set[Text_Field],

	//* The typeface and its size. A family of 0 is the GUI's default
	//* family; a size of 0 is the default size.
	family: Font_Family_ID,
	size:   f32,

	//* The ink. A colour of alpha 0 is "not set".
	colour:          Colour,
	hover_colour:    Colour,
	pressed_colour:  Colour,
	disabled_colour: Colour,
	focus_colour:    Colour,

	//* How the text sits in its box.
	align:  Text_Align,
	valign: V_Align,

	//* The lines.
	wrap:    Text_Wrap,
	spacing: f32, // extra pixels between the lines

	//* What is done to the string before it is laid out.
	transform: Text_Transform,

	//* What happens when the text does not fit.
	overrun: Text_Overrun,
	clip:    bool,

	//* The decorations. The outline is drawn under the text and the
	//* shadow under that.
	outline_colour: Colour,
	outline_size:   f32,
	shadow_colour:  Colour,
	shadow_offset:  Vec2,
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
	//* The style of every widget type.
	types: map[Widget_Type]Style,
	//* The style of every state of every widget type.
	states: map[Widget_Type]State_Styles,
	//* The named variations of a type, e.g. "danger" for a Button.
	variations: map[string]Variation,
	//* The family and the size the theme's text uses. A family of 0 is
	//* the GUI's default family; a size of 0 is the default size.
	family: Font_Family_ID,
	size:   f32,
}

//* A named variation of a widget type. Its style is applied over the
//* style of the type it varies from.
Variation :: struct {
	of:     Widget_Type,
	style:  Style,
	states: State_Styles,
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
Style_State :: enum { Normal, Hovered, Pressed, Disabled, Focused }

Split_Direction :: enum { Horizontal, Vertical }

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
}

Button_Data :: struct {
	text:     string,
	on_click: proc(g: ^GUI, id: Widget_ID),
}
Label_Data  :: struct { text: string }
Split_Data  :: struct { direction: Split_Direction }
Tabs_Data   :: struct { active: int }

//* A text field's own state: the buffer, the caret and the selection
//* (as byte offsets into the buffer).
Text_Input_Data :: struct {
	text:      string,
	caret:     int,
	sel_start: int,
	sel_end:   int,
}

Widget :: struct {
	id:     Widget_ID,
	type:   Widget_Type,
	name:   string,
	parent: Widget_ID,

	// Intrusive child list: O(1) detach/attach, which is what docking
	// is built on.
	first_child:  Widget_ID,
	last_child:   Widget_ID,
	prev_sibling: Widget_ID,
	next_sibling: Widget_ID,

	anchors:   Anchor,
	offsets:   Offset,
	grow_h:    Grow,
	grow_v:    Grow,
	min_size:  Vec2,
	weight:    f32, // share of the parent's split axis
	separation: f32, // gap between children of a VBox / HBox
	draggable: bool, // shows a title bar and can be dragged to dock

	//* The size the panel was pulled to, in pixels. A panel that was
	//* resized by hand keeps that size: the layout gives it this
	//* instead of a share of the space. The flags say which axis the
	//* size belongs to.
	manual_size: Vec2,
	manual_w:    bool,
	manual_h:    bool,

	// Resolved by the layout pass.
	rect:    Rect,
	content: Rect,
	clip:    Rect,

	style: Style,
	//* Whether the widget takes the theme's style for its type, and
	//* which named variation of that type it is.
	use_theme: bool,
	variation: string,
	state:     Widget_State,
	data:      Widget_Data,
}

//* == Widget creation options ==
//* Everything a widget needs at birth. Runtime changes go straight on
//* the Widget (see widget_get) — there are no setters.
Widget_Opts :: struct {
	name:       string,
	preset:     Anchor_Preset,
	anchors:    Anchor, // only used when preset is .Custom
	offsets:    Offset,
	min_size:   Vec2,
	weight:     f32,
	fixed:      bool, // keep min_size, take none of the parent's free space
	separation: f32, // gap between the children of a VBox / HBox
	draggable:  bool, // draw a title bar and allow drag-to-dock
	style:      Style,
	use_theme:  bool, // take the theme's style for this widget type
	variation:  string, // a named variation of the widget type
	hidden:     bool,
	split:      Split_Direction,
	text:       string,
	on_click:   proc(g: ^GUI, id: Widget_ID),
}

//* == Resizing ==
//* A dockable panel can be resized by pulling on its edges or on its
//* corners. The edges are the grips: a press on one starts a resize
//* and the edge follows the pointer from then on.

//* The edges of a panel that can be pulled.
Resize_Edge :: enum { Left, Right, Top, Bottom }

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
	active:  bool,
	armed:   bool, // the pointer is down on a handle, but has not moved
	origin:  Vec2, // where the pointer went down
	widget:  Widget_ID, // the widget being dragged
	target:  Widget_ID, // the container under the pointer
	tab_host: Widget_ID, // the container that would take the panel as a tab
	zone:    Dock_Zone, // which edge of the target
	kind:    Dock_Kind, // what the drop would do
	grab:    Vec2, // pointer offset inside the dragged widget
	pos:     Vec2, // pointer position, in screen pixels
	ghost:   Rect, // where the dragged widget is drawn
	size:    Vec2, // the size of the widget when the drag started
	slot:    Rect, // the slot the widget came from
	swap:    bool, // the pointer asked for a swap instead of a tab
	float_index: int, // the floating panel being moved, or -1
	plan:    Dock_Plan,
}

//* == GUI state ==
GUI :: struct {
	arena:       virt.Arena,
	frame_arena: virt.Arena,
	widgets:     [dynamic]^Widget,
	root:        Widget_ID,
	viewport:    Rect,
	//* Where the main window is on the screen, in screen pixels. A
	//* panel dropped outside of it floats instead of docking.
	window_rect: Rect,

	//* The panels that were torn out of the tree. Each one has a
	//* window of its own.
	floats: [dynamic]Float_Panel,

	events: [dynamic]Event,

	pointer:        Vec2,
	global_pointer: Vec2,
	lmb_down:       bool,
	lmb_pressed:    bool,
	lmb_released:   bool,
	mods:           Mods,
	hot:            Widget_ID,
	active:         Widget_ID,
	focused:        Widget_ID,
	quit_requested: bool,
	drag:           Drag_State,
	resize:         Resize_State,
	//* The panel whose grip the pointer is on, and the edges of it.
	//* The cursor follows from those edges.
	resize_hover:      Widget_ID,
	resize_hover_edges: Resize_Edges,
	cursor:            Cursor,
	ime_text:          string,

	draw:          Draw_List,
	//* The list the draw pass is filling. It is the main window's
	//* list, or the list of the floating panel being drawn.
	target:        ^Draw_List,
	backend:       Backend,
	white_texture: Texture_ID,
	next_texture:  Texture_ID,
	layout_dirty:  bool,

	// Text.
	fonts:         [dynamic]^Font,
	font_files:    [dynamic]^Font_File,
	font_families: [dynamic]^Font_Family,
	//* The instance of a family at a size, so a size that changes at
	//* runtime does not make a new one every time.
	font_instances: map[Font_Instance_Key]Font_ID,
	default_font:   Font_ID,
	default_family: Font_Family_ID,
	default_font_size: f32,
	shape_cache:  runa.Cache,
	cache_ready:  bool,
	upload_buf:   []u8,

	//* The theme: the look of every kind of widget, in one place.
	theme: ^Theme,
	//* The style every widget starts from. It is the GUI's own look,
	//* used where the theme says nothing.
	default_style: Style,
}

//* == Colour helper ==
rgba :: proc(r, g, b, a: f32) -> Colour {
	return Colour{r = r, g = g, b = b, a = a}
}

//* A colour that is brighter (or darker) than this one. The alpha is
//* left alone.
scale_colour :: proc(c: Colour, f: f32) -> Colour {
	return Colour{r = c.r * f, g = c.g * f, b = c.b * f, a = c.a}
}

//* The style of a piece of text: the ink, the size and the typeface. A
//* size of 0 is the GUI's default size and a family of 0 is the GUI's
//* default family.
text_style :: proc(
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
