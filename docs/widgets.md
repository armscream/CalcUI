# CalcUI widgets

Every widget kind, what it takes at construction and the calls that matter afterwards. Every options struct embeds `Base_Opts`, and every constructor returns a `Widget_ID`. The rest of the API is getters and setters on that id.

## Shared options

The shared fields, grouped for readability:

```odin
Base_Opts :: struct {
	name:       string,
	preset:     Anchor_Preset,
	anchors:    Anchor,
	offsets:    Offset,
	min_size, max_size: Vec2,
	weight, stretch_ratio, shrink_weight: f32,
	fixed, absolute, hidden, draggable: bool,
	separation: f32,
	style:      Style,
	use_theme:  bool,
	variation:  string,

	mouse_filter:  Mouse_Filter, // .Stop, .Pass, .Ignore
	focus_mode:    Focus_Mode,   // .None, .Click, .All
	tab_index:     int,
	size_flags_h, size_flags_v: Size_Flags,
	layout_direction: Layout_Direction,
	clip_contents: Clip_Contents,
	tooltip:       string,
	z_index:       int,

	access_role:        Access_Role,
	access_name:        string,
	access_description: string,
}
```

Most widgets set `name`, a placement (`preset`, or `anchors` and `offsets`), a size or weight, and a style. `hidden` removes a widget from layout. `clip_contents = .On` cuts children at the widget's rounded outline. `focus_mode = .All` also joins Tab navigation.

## Changing a widget

Widget fields are public, but setters are the safe path: each marks only the affected measurements as stale.

| Setter | Changes |
|---|---|
| `Widget_Set_Text`, `Widget_Set_Text_Rules` | Text and input rules. |
| `Widget_Set_Visible`, `Widget_Set_Enabled` | Visibility and enablement. |
| `Widget_Set_Style`, `Widget_Set_Variation`, `Widget_Set_Use_Theme` | Appearance and theme. |
| `Widget_Set_Min_Size`, `Widget_Set_Custom_Min_Size`, `Widget_Set_Max_Size` | Size limits. |
| `Widget_Set_Weight`, `Widget_Set_Size_Flags`, `Widget_Set_Stretch_Ratio`, `Widget_Set_Shrink_Weight` | Space sharing. |
| `Widget_Set_Anchors`, `Widget_Set_Offsets`, `Widget_Set_Absolute` | Placement. |
| `Widget_Set_Separation`, `Widget_Set_Layout_Direction` | Box layout. |
| `Widget_Set_Tooltip`, `Widget_Set_Mouse_Filter`, `Widget_Set_Focus_Mode`, `Widget_Set_Tab_Index`, `Widget_Set_Z_Index` | Interaction and draw order. |
| `Widget_Set_Clip_Contents` | Clipping. |
| `Widget_Set_Parent` | Reparent; the id is preserved. |

Change the tree with `Widget_Attach`, `Widget_Insert_At`, `Widget_Detach` and `Widget_Free`. Writing fields directly skips invalidation; use `GUI_Invalidate_All` (or `GUI_Invalidate_Theme` for themed widgets) after such a write.

## Keyboard and pointer

| Call | Purpose |
|---|---|
| `Focus_Set(g, id)`, `Focus_Clear(g)` | Give or remove keyboard focus. |
| `Focused_Widget(g)`, `Widget_Has_Focus(g, id)` | Query focus. |
| `Widget_Capture_Pointer(g, id)`, `Widget_Release_Pointer(g)` | Capture or release the pointer. |
| `Pointer_Captured(g)` | Widget holding the pointer. |
| `Event_Handled(g)` | Stop the event reaching widgets behind. |

## Catalogue

| Group | Kinds |
|---|---|
| Layout | `Panel`, `VBox`, `HBox`, `GridContainer`, `MarginContainer`, `CenterContainer`, `PanelContainer`, `ScrollContainer`, `ScrollArea`, `FlowContainer`, `AspectRatioContainer`, `Split`, `Tabs`, `TabContainer`, `TabBar`, separators, `ReferenceRect` |
| Basic controls | `Button`, `Label`, `TextBox`, `RichTextLabel`, `RichTextEditor`, `CheckBox`, `ToggleSwitch`, `LinkButton` |
| Selection and input | `OptionButton`, `MenuButton`, `ComboBox`, `ItemList`, `Tree`, `VirtualList`, `DataTable`, `Rating`, `Segmented`, sliders, `SpinBox`, `ProgressBar`, `SearchField`, `ChatInput`, `NumberInput`, date, time, colour and emoji pickers |
| Menus and overlays | `MenuBar`, `PopupMenu`, `PopupPanel`, `ContextMenu`, `CommandPalette`, `Tooltip`, `Toast`, dialogs, `Accordion` |
| Display and media | `ColorRect`, `TextureRect`, `NinePatchRect`, `Chart`, `NodeGraph`, `Canvas`, `Gizmo`, `VectorDrawing`, `FileViewer`, `AudioPlayer` |

## Layout and containers

| Constructor | Options |
|---|---|
| `Make_Panel` | `Panel_Opts{}` |
| `Make_VBox`, `Make_HBox` | `Box_Opts{}` |
| `Make_Split` | `Split_Opts{direction}` |
| `Make_Tabs`, `Make_Tab_Container` | `Tabs_Opts{}`, `Tab_Container_Opts{}` |
| `Make_Tab_Bar` | `Tab_Bar_Opts{}` |
| `Make_Grid_Container` | `Grid_Opts{columns, h_separation, v_separation, margin, show_lines, line_colour}` |
| `Make_Margin_Container` | `Margin_Opts{margin}` |
| `Make_Center_Container` | `Center_Opts{}` |
| `Make_Panel_Container` | `Panel_Container_Opts{}` |
| `Make_Scroll_Container`, `Make_Scroll_Area` | `Scroll_Container_Opts{scroll_bar}` |
| `Make_Flow_Container` | `Flow_Container_Opts{}` |
| `Make_Aspect_Container` | `Aspect_Container_Opts{ratio}` |
| `Make_Reference_Rect` | `Reference_Rect_Opts{}` |
| `Make_Separator(g, parent, vertical)` | No options struct. |

`Panel` is an empty box. `VBox` and `HBox` stack children, with `separation` as the gap. `Split` divides its space along `.Horizontal` or `.Vertical`. `Tabs` shows one child at a time. `scroll_bar` is `.Right`, `.Left`, `.Top`, `.Bottom` or `.None`.

For a scroll container, use `Scroll_Container_Set_Offset`, `_Get_Offset`, `_Content_Size`, `_Viewport_Size` and `_Visible_Rect`. It measures wrapped content at its width; a virtualized child reports a logical size through the `content_size` kind hook.

## Text and basic controls

| Constructor | Options | Notes |
|---|---|---|
| `Make_Button` | `Button_Opts{text, on_pressed, text_align}` | Fires on release. |
| `Make_Label` | `Label_Opts{text}` | |
| `Make_Text_Box` | `Text_Box_Opts{text, rules, flags, shown_chars}` | Single-line unless `.Multiline`. |
| `Make_Rich_Text_Label` | `Rich_Text_Opts{text}` | |
| `Make_Rich_Text_Editor` | `Rich_Text_Editor_Opts{text, wrap, rules}` | Multiple cursors. |
| `Make_Check_Box` | `Check_Box_Opts{text, on}` | `check_box_set`, `check_box_is_on`. |
| `Make_Toggle_Switch` | `Toggle_Switch_Opts{text, on}` | `toggle_switch_set`, `_is_on`. |
| `Make_Link_Button` | `Link_Button_Opts{text, link}` | Fires `on_link_activated`. |
| `Make_Option_Button` | `Option_Button_Opts{items}` | Drop-down list. |
| `Make_Menu_Button` | `Menu_Button_Opts{text, items}` | Menu below the button. |
| `Make_Combo_Box` | `Combo_Box_Opts{items}` | `combo_box_select`, `_text`. |
| `Make_Item_List` | `Item_List_Opts{items}` | `item_list_add`, `_select`. |
| `Make_Tree` | `Tree_Opts{}` | `tree_add_item`, `_select_item`, `_set_expanded`. |
| `Make_Segmented` | `Segmented_Opts{items}` | `segmented_select`. |
| `Make_Rating` | `Rating_Opts{value, max, mark}` | `rating_set`. |

## Ranges and input fields

| Constructor | Options | Notes |
|---|---|---|
| `Make_H_Slider`, `Make_V_Slider` | `Slider_Opts{value, min, max, step}` | `slider_value`, `slider_set_value`. |
| `Make_Spin_Box` | `Spin_Box_Opts{value, min, max, step}` | Arrow buttons step the value. |
| `Make_Progress_Bar` | `Progress_Bar_Opts{value, max}` | `progress_bar_set_value`. |
| `Make_Number_Input` | `Number_Input_Opts{value, min, max, step}` | Editable text plus arrows. |
| `Make_Search_Field` | `Search_Field_Opts{text, placeholder, hide_icon, max_width, on_submitted}` | Magnifier and clear button. |
| `Make_Chat_Input` | `Chat_Input_Opts{}` | Transcript above a field. |
| `Make_Date_Picker` | `Date_Picker_Opts{year, month, day}` | Calendar popup. |
| `Make_Time_Picker` | `Time_Picker_Opts{hour, minute}` | Time list. |
| `Make_Color_Picker` | `Color_Picker_Opts{colour}` | HSV picker plus an editable hex code. |
| `Make_Emoji_Picker` | `Emoji_Picker_Opts{emoji, group}` | Emoji grid. |

A slider clamps to its bounds and snaps to `step`; `step = 0` means one hundredth of the range. A spin box clamps but leaves stepping to its arrows.

## Menus, overlays and dialogs

| Constructor | Options | Notes |
|---|---|---|
| `Make_Popup_Menu` | `Popup_Menu_Opts{items}` | `Popup_Menu_Open`, `_Close`, `_Select`. |
| `Make_Popup_Panel` | `Popup_Panel_Opts{}` | `Popup_Panel_Open`, `_Close`. |
| `Make_Menu_Bar` | `Menu_Bar_Opts{}` | Strip of menus. |
| `Make_Context_Menu` | `Context_Menu_Opts{items}` | `Context_Menu_Open(pos)`. |
| `Make_Command_Palette` | `Command_Palette_Opts{}` | `Command_Palette_Add`, `_Open`. |
| `Make_Accordion` | `Accordion_Opts{}` | At most one section open. |
| `Make_Tooltip` | `Tooltip_Opts{text, target}` | `Tooltip_Show`, `_Hide`. |
| `Make_Toast` | `Toast_Opts{text, kind, duration}` | `Toast_Show`, `_Is_Visible`. |
| `Make_Accept_Dialog`, `Make_Confirmation_Dialog` | `Accept_Dialog_Opts{text}` | `Dialog_Open`, `_Accept`, `_Was_Accepted`. |
| `Make_File_Dialog` | `File_Dialog_Opts{mode}` | `File_Dialog_Open`, `_Path`, `_Set_Path`. |

`Popup_Attach_To_Root` moves a popup above scroll containers. An open popup takes the pointer and focus, and returns focus when it closes; Escape closes the topmost popup.

## Display and heavy widgets

| Constructor | Options | Notes |
|---|---|---|
| `Make_Color_Rect` | `Color_Rect_Opts{colour}` | `color_rect_set_colour`. |
| `Make_Texture_Rect` | `Texture_Rect_Opts{texture}` | Load with `Texture_Load_File`. |
| `Make_Nine_Patch_Rect` | `Nine_Patch_Opts{texture, patch, source, tint, ...}` | See below. |
| `Make_Chart` | `Chart_Opts{kind}` | `.Bar`, `.Line` or `.Pie`; `chart_add_series`. |
| `Make_Canvas` | `Canvas_Opts{repaint_rate}` | Program-drawn items or a paint callback. |
| `Make_Gizmo` | `Gizmo_Opts{transform, mode, ...}` | Move, rotate and scale handles. |
| `Make_Vector_Drawing` | `Vector_Drawing_Opts{}` | Editable lines and shapes. |
| `Make_File_Viewer` | `File_Viewer_Opts{}` | Directory listing; the program supplies the loader. |
| `Make_Audio_Player` | `Audio_Player_Opts{path, volume, loops}` | Needs a backend audio binding. |
| `Make_Node_Graph` | `Node_Graph_Opts{zoom, min_zoom, max_zoom, grid_visible, grid_size, grid_major, snap}` | See [`node-graph.md`](node-graph.md). |

`Chart`, `Canvas`, `Gizmo`, `VectorDrawing`, `FileViewer`, `AudioPlayer` and `NodeGraph` keep their data behind a pointer, so the widget stays small however large its contents are.

## Text boxes

One widget covers single-line fields and multiline boxes. The `Multiline` flag selects the latter; `shown_chars` defaults to 50 for a single-line field.

Both forms share the same editing model: a click places the caret, a drag selects, a double click selects a word, `Ctrl+A` selects all, and `Ctrl+Z` / `Ctrl+Y` undo and redo. A single-line field ignores line breaks, submits on Enter and moves focus on Tab. A multiline box wraps at word boundaries, grows with its lines, inserts a newline on Enter and four spaces on Tab.

```odin
Text_Rules :: struct {
	max_length: int, // 0 means unlimited
	min_length: int,
	allowed:    string, // characters that may be typed; empty allows all
	pattern:    string, // per-character pattern; empty allows all
}
```

Rules apply to typing and pasting, not to text set by the program. The pattern supports literals, bracket sets, `.`, the quantifiers `|`, `*`, `+`, `?` and `{n,m}`, and the classes `\d`, `\w` and `\s`.

```odin
GUI.Make_Text_Box(g, g.root, GUI.Text_Box_Opts{
	Base_Opts = GUI.Base_Opts{name = "amount"},
	rules = GUI.Text_Rules{max_length = 6, allowed = "0123456789"},
})
```

Add `flags = GUI.Text_Box_Flags{.Multiline}` for a multiline box.

## Nine-patch images

A nine-patch divides a texture into nine cells by four border measurements. The corners keep their size, the edges stretch or tile, and the centre takes the remaining room. Borders stay sharp when the widget grows.

`patch` is the left, top, right and bottom border in source pixels. `source` selects a sub-rectangle (empty means the whole texture). `tint` is multiplied into the texture; zero means white. The edge modes are `.Stretch` (default) and `.Tile`; the centre mode is `.Stretch`, `.Tile` or `.Disabled` (an empty frame).

```odin
texture, ok := GUI.Texture_Load_File(g, "frame.png")
GUI.Make_Nine_Patch_Rect(g, g.root, GUI.Nine_Patch_Opts{
	Base_Opts = GUI.Base_Opts{name = "frame", offsets = GUI.Offset{left = 20, top = 20, right = 260, bottom = 140}},
	texture = texture,
	patch = {12, 12, 12, 12},
	centre_mode = .Disabled,
})
```

`Nine_Patch_Set_Texture`, `_Set_Patch`, `_Set_Source`, `_Set_Tint` and `_Set_Modes` change it later.

## Virtual lists and data tables

A virtual list draws only the rows on screen. The program supplies the rows:

```odin
List_Source :: struct {
	count:  proc(ctx: rawptr) -> int,
	text:   proc(ctx: rawptr, index: int) -> string,
	key:    proc(ctx: rawptr, index: int) -> u64,
	height: proc(ctx: rawptr, index: int) -> f32,
	ctx:    rawptr,
}
```

`key` defaults to the row index; `height` is only needed when rows differ. Selection is stored by key, so it survives reordering. Call `virtual_list_refresh` after the source changes. `List_Source_Texts` builds a source from strings.

A data table adds columns and a sortable header:

```odin
Table_Source :: struct {
	count:  proc(ctx: rawptr) -> int,
	values: proc(ctx: rawptr, index: int) -> []string,
	key:    proc(ctx: rawptr, index: int) -> u64,
	ctx:    rawptr,
}
```

Columns use `Data_Table_Column{title, width, size, min_width, sort, compare}`; `size` is `.Fixed` or `.Stretch`, and `sort` is `.None`, `.Ascending` or `.Descending`. `data_table_add_column` adds one. Sorting and filtering run when they change, not per frame, and selection survives both. Use `data_table_refresh` after the source changes.

Both widgets take focus and support arrow keys, Home/End and the wheel; a data table also uses Left/Right for columns and Shift+wheel for horizontal scrolling.

## Signals

Every widget has the same signals, so a handler can connect without knowing the kind.

| Signal | Payload | Fires when |
|---|---|---|
| `on_pressed` | | The widget is pressed and released. |
| `on_toggled` | `on: bool` | A toggle changes. |
| `on_link_activated` | `link: string` | A link is activated; return true if handled. |
| `on_value_changed` | `value: f32` | A range, rating or progress value changes. |
| `on_colour_changed` | `colour: Colour` | A colour changes. |
| `on_text_changed` | `text: string` | Editable text changes. |
| `on_item_selected` | `index: int` | A list, tab or menu item is picked. |
| `on_submitted` | `text: string` | A field is submitted. |
| `on_focus_entered`, `on_focus_exited` | | Keyboard focus moves. |
| `on_dragged`, `on_resized` | `delta` / `size` | Reserved; currently unfired. |

An unconnected signal is nil. The signals are made the first time one is connected:

```odin
signals := GUI.Widget_Signals(g, id)
signals.on_pressed = on_pressed
```

## Writing a widget

```odin
setup :: proc(g: ^GUI.GUI) {
	box := GUI.Make_VBox(g, g.root, GUI.Box_Opts{
		Base_Opts = GUI.Base_Opts{
			name = "main",
			offsets = GUI.Offset{left = 16, top = 16, right = -16, bottom = -16},
			separation = 8,
		},
	})

	GUI.Make_Label(g, box, GUI.Label_Opts{
		Base_Opts = GUI.Base_Opts{name = "title"},
		text = "Hello, CalcUI",
	})

	GUI.Make_Button(g, box, GUI.Button_Opts{
		Base_Opts = GUI.Base_Opts{name = "counter"},
		text = "Press me",
		on_pressed = on_pressed,
	})
}

on_pressed :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) {
	w := GUI.Widget_Get(g, id)
	w.style.box.bg_color = GUI.RGBA(0.20, 0.60, 1.00, 1)
}
```

Widgets are created once and found again by id. `Widget_Get` returns a pointer, so fields can be written directly. Kind-specific data is in `w.data`, a tagged union:

```odin
#partial switch &d in w.data {
case GUI.Button_Data:
	d.text = "Pressed"
}
```

## Removing a widget

```odin
Widget_Free :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) -> bool
```

`Widget_Free` destroys a widget and everything under it, releasing focus, pointer capture, owned buffers and references from other widgets. The handle becomes invalid; `Widget_Alive(g, id)` checks whether it still names a widget.

`Widget_Attach` and `Widget_Insert_At` move a widget instead, preserving its handle. `New_Widget(g, type, parent, opts)` creates one by `Widget_Type`. `Image` has no data and no scene constructor, so a scene node of that type is reported and skipped.

## Shapes, borders and shadows

`GUI.StyleBox` describes the box a widget is drawn in. `corner_radius` holds four radii in the order top left, top right, bottom right, bottom left. `border_color` and `border_width` are per side; four different colours become strips that follow the outline. `backdrop_blur` turns the fill into frosted glass, and `optics` adds refraction, dispersion, a rim light and saturation.

| Field | Meaning |
|---|---|
| `corner_radius` | Per-corner radii. |
| `border_color`, `border_width` | Per-side border colour and width. |
| `backdrop_blur` | Blur radius of the content behind a glass box. |
| `optics.refraction`, `optics.dispersion` | Rim bend and colour split. |
| `optics.fresnel`, `optics.saturation` | Rim light and backdrop saturation. |
| `shadow_color`, `shadow_size`, `shadow_offset` | Shadow colour, blur and offset. |
| `shadow_spread` | How far an outer shadow grows past the box, or an inset shadow starts inside it. |
| `shadow_inset` | Draw the shadow inside the box. |

An outer shadow is drawn under the box; an inset shadow is drawn after the border and before the content. Clipping is opt-in with `clip_contents = .On`, but scroll containers, tab hosts, the chat input and the node graph enable it themselves. `Texture_Rect` draws with the corners of its style box; `Draw_Quad_Rounded` exposes the same path for custom drawing.
