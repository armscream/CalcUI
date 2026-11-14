# CalcUI widgets

The catalogue: every widget kind, its options, how it is changed, and what it reports. Every kind has an options struct, and every options struct embeds `Base_Opts`. A constructor returns a `Widget_ID`; everything afterwards is a getter or setter on that id.

## Shared options

```odin
Base_Opts :: struct {
	name:       string,
	preset:     Anchor_Preset,
	anchors:    Anchor,
	offsets:    Offset,
	min_size:   Vec2,
	max_size:   Vec2,
	weight:     f32,
	fixed:      bool,
	separation: f32,
	draggable:  bool,
	style:      Style,
	use_theme:  bool,
	variation:  string,
	hidden:     bool,

	//* The control features.
	mouse_filter:  Mouse_Filter,
	focus_mode:    Focus_Mode,
	tab_index:     int,
	size_flags_h:  Size_Flags,
	size_flags_v:  Size_Flags,
	stretch_ratio: f32,
	layout_direction: Layout_Direction,
	clip_contents: Clip_Contents,
	tooltip:       string,
	z_index:       int,

	//* What the widget reports to an accessibility reader.
	access_role:        Access_Role,
	access_name:        string,
	access_description: string,
}
```

A constructor takes the options of its kind, so a program names only the fields it changes.

## Changing a widget

A widget is a struct with open fields, so a program may write to it directly. The setters are the safe path: each marks only the measurements it affects as stale, so the tree is re-measured and re-arranged where needed.

| Setter | What it changes |
|---|---|
| `Widget_Set_Text` | Text of a label, button or text field. Text buffers are owned by the widget: the new text is copied before the old is released, so the caller's string may be reused. |
| `Widget_Set_Text_Rules` | Length and character rules of a text box. |
| `Widget_Set_Visible` | Show/hide. A hidden widget is neither drawn nor hit and occupies no layout space; toggling visibility does not dirty layout. |
| `Widget_Set_Enabled` | Enable/disable. |
| `Widget_Set_Name` | Widget name. |
| `Widget_Set_Style` | Box and text style. |
| `Widget_Set_Variation` | Theme variation. |
| `Widget_Set_Use_Theme` | Whether the theme applies at all. |
| `Widget_Set_Min_Size` | Minimum size the widget asks for. |
| `Widget_Set_Custom_Min_Size` | Minimum size the program insists on. |
| `Widget_Set_Max_Size` | Maximum size. |
| `Widget_Set_Weight` | Share of the parent's space. |
| `Widget_Set_Size_Flags` | Fill/expand behaviour per axis. Expand takes a share of leftover space; fill takes the room it is given; shrink takes the minimum size and centres. Default is `.Fill` and `.Expand` on both axes. |
| `Widget_Set_Stretch_Ratio` | Share multiplier: weight x ratio. A ratio of 0 leaves only the minimum size. |
| `Widget_Set_Layout_Direction` | Growth direction, left-to-right or right-to-left. Reverses child order in an HBox; does not change the allotted room. |
| `Widget_Set_Separation` | Gap between the children of a box. |
| `Widget_Set_Anchors` | Position within the parent. |
| `Widget_Set_Offsets` | Distance from the anchors. |
| `Widget_Set_Mouse_Filter` | How the widget handles the mouse. |
| `Widget_Set_Tooltip` | Text shown while the pointer rests on the widget. |
| `Widget_Set_Focus_Mode` | Kind of focus the widget accepts. |
| `Widget_Set_Tab_Index` | Position in the tab order. |
| `Widget_Set_Grow` | Growth direction per axis when given extra room. |
| `Widget_Set_Z_Index` | Draw order. The highest value is drawn last, on top, and receives the mouse; tree order is unchanged. |
| `Widget_Set_Clip_Contents` | Clip children to the widget rect. |
| `Widget_Set_Manual_Size` | Size imposed by the program. A zero axis is not fixed. |
| `Widget_Set_Draggable` | Drag by the title bar. |
| `Widget_Set_Focus_Neighbour` | Arrow-key neighbour per direction: 0 left, 1 up, 2 right, 3 down. A widget may name itself. Resolved when a key is pressed. |
| `Widget_Set_Focus_Next` | Tab-order successor. Resolved when a key is pressed. |
| `Widget_Set_Focus_Previous` | Tab-order predecessor. Resolved when a key is pressed. |
| `Widget_Children` | Children in tree order. The caller owns the slice and frees it with `delete(children, allocator)`. |
| `Widget_Set_Parent` | Reparent. The id is preserved. An invalid parent is refused and the tree is left as it was; `Widget_Detach` removes a widget instead. |
| `Widget_Reparent` | Old name for `Widget_Set_Parent`. |

The framework owns `id`, `type`, `class`, `parent`, `freeing`, `first_child`, `last_child`, `prev_sibling`, `next_sibling`, `data`, `min_size`, `rect`, `clip`, `manual_size`, `manual_w`, `manual_h`, `dirty`, `subtree_dirty` and `style_cache`. Change the parent with `Widget_Set_Parent`, widget data through its kind's setter, and the cached size with `Widget_Set_Manual_Size`.

`rotation`, `scale`, `pivot_offset` and `content` are unused by the toolkit; a program may read and write them. Transforms are not supported by the draw list, the hit test or the clip stack.

The tree is changed with `Widget_Attach`, `Widget_Insert_At`, `Widget_Detach` and `Widget_Free`, which also mark the affected measurements stale. Writing fields without a setter requires `GUI_Invalidate_All` to re-measure the whole tree; `GUI_Invalidate_Theme` does the same for themed widgets.

## Keyboard and pointer

The rules are in `docs/events-focus.md`. These are the calls a program makes:

| Call | What it does |
|---|---|
| `Focus_Set(g, id)` | Gives the keyboard to a widget. False when the widget cannot take it. |
| `Focus_Clear(g)` | Removes keyboard focus. |
| `Focused_Widget(g)` | The widget with keyboard focus. |
| `Widget_Has_Focus(g, id)` | Whether a widget has keyboard focus. |
| `Widget_Capture_Pointer(g, id)` | Gives the pointer to a widget. |
| `Widget_Release_Pointer(g)` | Releases the pointer. |
| `Pointer_Captured(g)` | The widget holding the pointer. |
| `Event_Handled(g)` | Marks the event dealt with so it does not reach widgets behind. |
| `Event_Is_Handled(g)` | Whether the event was dealt with. |

## Catalogue

| Group | Kinds |
|---|---|
| Layout and containers | `Panel`, `VBox`, `HBox`, `GridContainer`, `MarginContainer`, `CenterContainer`, `PanelContainer`, `ScrollContainer`, `ScrollArea`, `ScrollBar`, `FlowContainer`, `AspectRatioContainer`, `Split`, `Tabs`, `TabContainer`, `TabBar`, `HSeparator`, `VSeparator`, `ReferenceRect` |
| Basic controls | `Button`, `Label`, `Image`, `TextBox`, `RichTextLabel`, `RichTextEditor`, `CheckBox`, `ToggleSwitch`, `LinkButton` |
| Selection and input | `OptionButton`, `MenuButton`, `ComboBox`, `ItemList`, `Tree`, `VirtualList`, `DataTable`, `Rating`, `Segmented`, `HSlider`, `VSlider`, `SpinBox`, `ProgressBar`, `SearchField`, `ChatInput`, `NumberInput`, `DatePicker`, `TimePicker`, `ColorPicker`, `EmojiPicker` |
| Menus and overlays | `MenuBar`, `PopupMenu`, `PopupPanel`, `ContextMenu`, `CommandPalette`, `Tooltip`, `Toast`, `AcceptDialog`, `ConfirmationDialog`, `FileDialog`, `Accordion` |
| Display and media | `ColorRect`, `TextureRect`, `NinePatchRect`, `Chart`, `NodeGraph`, `Canvas`, `VectorDrawing`, `FileViewer`, `AudioPlayer` |

## Layout and core controls

### Panel, VBox, HBox, Split, Tabs

```odin
Panel_Opts :: struct { Base_Opts: Base_Opts }
Make_Panel :: proc(g: ^GUI, parent: Widget_ID, opts: Panel_Opts) -> Widget_ID

Box_Opts :: struct { Base_Opts: Base_Opts }
Make_VBox :: proc(g: ^GUI, parent: Widget_ID, opts: Box_Opts) -> Widget_ID
Make_HBox :: proc(g: ^GUI, parent: Widget_ID, opts: Box_Opts) -> Widget_ID

Split_Opts :: struct {
	Base_Opts: Base_Opts,
	direction: Split_Direction,
}
Make_Split :: proc(g: ^GUI, parent: Widget_ID, opts: Split_Opts) -> Widget_ID

Tabs_Opts :: struct { Base_Opts: Base_Opts }
Make_Tabs :: proc(g: ^GUI, parent: Widget_ID, opts: Tabs_Opts) -> Widget_ID
```

`Panel` is an empty box. `VBox` and `HBox` stack children vertically and horizontally, with `Base_Opts.separation` as the gap. `Split` divides its space among children along `.Horizontal` or `.Vertical`, with draggable edges. `Tabs` hosts tabs as children and shows one at a time.

### Button

```odin
Button_Align :: enum { Theme, Left, Center, Right }

Button_Opts :: struct {
	Base_Opts:  Base_Opts,
	text:       string,
	on_pressed: proc(g: ^GUI, id: Widget_ID),
	text_align: Button_Align,
}

Make_Button :: proc(g: ^GUI, parent: Widget_ID, opts: Button_Opts) -> Widget_ID
```

The text lives in the widget data and is centred by default. `text_align` writes the alignment into the style, overriding the theme; `.Theme` keeps the theme value. The button fires `on_pressed` when the pointer is released over it.

### Label

```odin
Label_Opts :: struct {
	Base_Opts: Base_Opts,
	text: string,
}

Make_Label :: proc(g: ^GUI, parent: Widget_ID, opts: Label_Opts) -> Widget_ID
```

### TextBox

```odin
Text_Box_Flag :: enum { Multiline }
Text_Box_Flags :: bit_set[Text_Box_Flag]

Text_Box_Opts :: struct {
	Base_Opts:   Base_Opts,
	text:        string,
	rules:       Text_Rules,
	flags:       Text_Box_Flags,
	shown_chars: int,
}

Make_Text_Box :: proc(g: ^GUI, parent: Widget_ID, opts: Text_Box_Opts) -> Widget_ID
```

One widget covers single-line fields and multiline boxes; the `Multiline` flag selects the latter. The box owns a cloned buffer and takes focus when clicked.

Both forms share the editing model: a click places the caret, a drag selects, a double click selects a word and a second double click selects all, `Ctrl+A` selects all, and `Ctrl+Z` / `Ctrl+Y` undo and redo with the caret restored. The caret flashes while the widget has focus.

A single-line field ignores line breaks: Enter fires `on_submitted` and Tab moves focus. It shows at most `shown_chars` characters (50 by default) or as many as fit, scrolls sideways on the wheel, and shows a horizontal scroll bar when text is hidden. The field stays one line tall.

A multiline box wraps at word boundaries, grows with its lines, scrolls when the lines overflow, and shows a vertical scroll bar. Enter inserts a newline and Tab inserts four spaces.

```odin
Text_Rules :: struct {
	max_length: int,
	min_length: int,
	allowed:    string,
	pattern:    string,
}
```

| Field | What it does |
|---|---|
| `max_length` | Maximum characters; 0 means unlimited. |
| `min_length` | Minimum characters; the text never goes below it. |
| `allowed` | Characters that may be typed; empty allows all. |
| `pattern` | Per-character pattern; empty allows all. |

Rules apply to typing and pasting, not to text set by the program. The pattern is a small regex matched one character at a time: literals, bracket sets, `.` as any character, the quantifiers `|`, `*`, `+`, `?` and `{n,m}`, and the classes `\d`, `\w` and `\s`.

```odin
GUI.Make_Text_Box(g, g.root, GUI.Text_Box_Opts{
	Base_Opts = GUI.Base_Opts{name = "amount"},
	rules = GUI.Text_Rules{
		max_length = 6,
		allowed = "0123456789",
	},
})
```

For a multiline box, add `flags = GUI.Text_Box_Flags{.Multiline}`.

### Containers

The containers in `src/GUI/widget_containers.odin` lay their children out themselves.

| Constructor | Options | What it does |
|---|---|---|
| `Make_Grid_Container` | `Grid_Opts{Base_Opts, columns, h_separation, v_separation, margin, show_lines, line_colour}` | Places children row by row, left to right. `columns = 0` gives one column per child. Zero separations use the theme; `margin` is left, top, right, bottom; `show_lines` draws cell borders. |
| `Make_Margin_Container` | `Margin_Opts{Base_Opts, margin: [4]f32}` | Keeps its child away from the edges; margin is left, top, right, bottom. |
| `Make_Center_Container` | `Center_Opts{Base_Opts}` | Centres its child at the size the child asks for. |
| `Make_Panel_Container` | `Panel_Container_Opts{Base_Opts}` | Gives its child the whole area. |
| `Make_Scroll_Container` | `Scroll_Container_Opts{Base_Opts, scroll_bar}` | Shows part of an oversized child. The wheel scrolls; `scroll_bar` is `.Right`, `.Left`, `.Top`, `.Bottom` or `.None`. |
| `Make_Scroll_Area` | `Scroll_Container_Opts` | Another name for `Make_Scroll_Container`. |
| `Make_Flow_Container` | `Flow_Container_Opts{Base_Opts}` | Places children in a row and wraps when there is no room. |
| `Make_Aspect_Container` | `Aspect_Container_Opts{Base_Opts, ratio: f32}` | Keeps its child's aspect ratio; `ratio = 0` means 1. |
| `Make_Tab_Container` | `Tab_Container_Opts{Base_Opts}` | Children are tabs; one is shown at a time. |

| Function | What it does |
|---|---|
| `Scroll_Container_Set_Offset(g, id, offset)` | Scrolls to an offset, clamped to the content. |
| `Scroll_Container_Get_Offset(g, id)` | Current scroll offset. |
| `Scroll_Container_Set_Bar(g, id, side)` | Moves or removes the scroll bar. |
| `tab_container_set_active(g, id, index)` | Shows a tab by index. |

### Simple controls

The widgets in `src/GUI/widget_simple.odin` show something.

| Constructor | Options | What it does |
|---|---|---|
| `Make_Color_Rect` | `Color_Rect_Opts{Base_Opts, colour}` | A rectangle of one colour. |
| `Make_Texture_Rect` | `Texture_Rect_Opts{Base_Opts, texture}` | Shows an atlas texture. |
| `Make_Nine_Patch_Rect` | `Nine_Patch_Opts{Base_Opts, texture, patch}` | Shows a texture with fixed-size edges. `patch` is the margin on the left, top, right and bottom, in pixels. |
| `Make_Reference_Rect` | `Reference_Rect_Opts{Base_Opts}` | An invisible layout placeholder. Takes no mouse. |
| `Make_Rich_Text_Label` | `Rich_Text_Opts{Base_Opts, text}` | A label for text of any length. |
| `Make_Item_List` | `Item_List_Opts{Base_Opts, items: []string}` | A list with one selectable item. |
| `Make_Tree` | `Tree_Opts{Base_Opts}` | A tree; items are added one by one. |
| `Make_Tab_Bar` | `Tab_Bar_Opts{Base_Opts}` | One tab per child. |
| `Make_Menu_Bar` | `Menu_Bar_Opts{Base_Opts}` | A strip of menus. |

`Texture_Rect` and `Nine_Patch_Rect` take an atlas `Texture`, not a backend texture id. Load a PNG into the atlas with:

```odin
Texture_Load_File :: proc(g: ^GUI, path: string) -> (texture: Texture, ok: bool)
```

The call returns `false` and an empty texture for a missing or non-PNG file; an empty texture draws nothing.

A separator is made by direction rather than an options struct:

```odin
Make_Separator :: proc(g: ^GUI, parent: Widget_ID, vertical: bool) -> Widget_ID
```

A horizontal separator lies across; a vertical one stands up.

| Function | What it does |
|---|---|
| `rich_text_label_text(g, id)` | Text of a rich text label. |
| `rich_text_label_set_text(g, id, text)` | Sets the text. Fires `on_text_changed`. |
| `text_edit_text(g, id)` | Text of a text edit. |
| `text_edit_set_text(g, id, text)` | Sets the text. Fires `on_text_changed`. |
| `text_edit_set_rules(g, id, rules)` | Sets the text rules. |
| `item_list_count(g, id)` | Number of items. |
| `item_list_text(g, id, index)` | Text of an item. |
| `item_list_add(g, id, text)` | Adds an item. |
| `item_list_remove(g, id, index)` | Removes an item. |
| `item_list_select(g, id, index)` | Selects an item. Fires `on_item_selected`. |
| `tree_add_item(g, id, text, parent)` | Adds an item under `parent` (or at the top for -1). Returns the new index. |
| `tree_item_count(g, id)` | Number of items. |
| `tree_item_text(g, id, index)` | Text of an item. |
| `tree_select_item(g, id, index)` | Selects an item. Fires `on_item_selected`. |
| `tree_set_expanded(g, id, index, expanded)` | Opens or closes an item. |

A tree is as wide as its widest item and asks for that as its minimum size. It fills the height its parent gives, scrolls overflowing rows with the wheel, scrolls the selected row into view, and moves the selection with the arrow keys.

### Buttons

The widgets in `src/GUI/widget_buttons.odin`.

| Constructor | Options | What it does |
|---|---|---|
| `Make_Check_Box` | `Check_Box_Opts{Base_Opts, text, on}` | A box with a tick. |
| `Make_Option_Button` | `Option_Button_Opts{Base_Opts, items}` | Shows the selected item and opens a list when clicked. |
| `Make_Menu_Button` | `Menu_Button_Opts{Base_Opts, text, items}` | Opens a menu of its items below when clicked. |
| `Make_Link_Button` | `Link_Button_Opts{Base_Opts, text, link}` | Looks like a link. Fires `on_link_activated`, and opens the link in the system browser when no handler takes it. |

| Function | What it does |
|---|---|
| `check_box_set(g, id, on)` | Turns a check box on or off. Fires `on_toggled`. |
| `check_box_is_on(g, id)` | Whether a check box is on. |
| `option_button_text(g, id)` | Selected item text. |
| `option_button_select(g, id, index)` | Selects an item. Fires `on_item_selected`. |

The menu button's menu is a toolkit popup: it opens below the button, as wide as its widest item, flips above the button when there is no room below, and never leaves the window bounds. It follows the button when the window or button moves, opens in the panel's window when the button is in a floating panel, and closes on selection, on a second click, on Escape or when the pointer moves elsewhere. The button hears the pick through `on_item_selected`.

### Ranges

The number widgets in `src/GUI/widget_range.odin`.

| Constructor | Options | What it does |
|---|---|---|
| `Make_H_Slider` | `Slider_Opts{Base_Opts, value, min, max, step: f32}` | A horizontal slider. |
| `Make_V_Slider` | `Slider_Opts` | A vertical slider. |
| `Make_Spin_Box` | `Spin_Box_Opts{Base_Opts, value, min, max, step: f32}` | A number with two arrows. |
| `Make_Progress_Bar` | `Progress_Bar_Opts{Base_Opts, value, max: f32}` | A progress bar. |

```odin
Make_Slider :: proc(g: ^GUI, parent: Widget_ID, kind: Widget_Type, opts: Slider_Opts) -> Widget_ID
```

A slider clamps its value to the bounds and snaps to `step`; a step of 0 means one hundredth of the range. A spin box clamps but leaves stepping to the arrows. A progress bar clamps between 0 and its maximum.

| Function | What it does |
|---|---|
| `slider_value(g, id)` | Current slider value. |
| `slider_set_value(g, id, value)` | Sets the value. Fires `on_value_changed`. |
| `spin_box_value(g, id)` | Current spin box value. |
| `spin_box_set_value(g, id, value)` | Sets the value. Fires `on_value_changed`. |
| `spin_box_step(g, id, direction)` | Steps by `direction` (negative steps back) through the setter. |
| `spin_box_data(g, id)` | Spin box data: value, bounds, step and editing state. |
| `progress_bar_set_value(g, id, value)` | Sets the progress. Fires `on_value_changed`. |

Clicking an arrow steps once; clicking the field takes focus. Up/Down step once, Page Up/Page Down or Ctrl+Up/Down step ten, and Home/End jump to the bounds.

### Popups

The overlays in `src/GUI/widget_popups.odin`.

| Constructor | Options | What it does |
|---|---|---|
| `Make_Popup_Menu` | `Popup_Menu_Opts{Base_Opts, items}` | A menu, hidden until opened. |
| `Make_Popup_Panel` | `Popup_Panel_Opts{Base_Opts}` | A panel over the rest of the UI, hidden until opened. |
| `Make_Accept_Dialog` | `Accept_Dialog_Opts{Base_Opts, text}` | A dialog with an accept button. |
| `Make_Confirmation_Dialog` | `Accept_Dialog_Opts` | A dialog with accept and cancel buttons. |
| `Make_File_Dialog` | `File_Dialog_Opts{Base_Opts, mode}` | A file picker; `mode` is `.Open_File`, `.Save_File` or `.Open_Folder`. |

| Function | What it does |
|---|---|
| `Popup_Attach_To_Root(g, id)` | Moves a popup under the root so it draws above scroll containers and the rest of the UI. The id is preserved. |
| `Popup_Open(g, id)` | Opens a popup. Kind-specific opens also reset their state (a palette gets commands and a filter; a dialog is reset). |
| `Popup_Menu_Add_Item(g, id, text)` | Adds a menu item. |
| `Popup_Menu_Open(g, id)` | Opens a popup menu. A menu button's menu opens at the button; a free menu opens at the pointer. |
| `Popup_Menu_Close(g, id)` | Closes a popup menu. |
| `Popup_Menu_Select(g, id, index)` | Selects an item and closes. Fires `on_item_selected` on the menu and on its menu button. |
| `Popup_Panel_Open(g, id)` | Opens a popup panel. |
| `Popup_Panel_Close(g, id)` | Closes a popup panel. |
| `Dialog_Open(g, id)` | Opens a dialog. |
| `Dialog_Close(g, id)` | Closes a dialog. |
| `Dialog_Accept(g, id)` | Accepts and closes a dialog. |
| `Dialog_Was_Accepted(g, id)` | Whether the dialog was accepted the last time it closed. |
| `File_Dialog_Open(g, id)` | Opens a file dialog. |
| `File_Dialog_Close(g, id)` | Closes a file dialog. |
| `File_Dialog_Path(g, id)` | Current path. |
| `File_Dialog_Set_Path(g, id, path)` | Sets the current path. |

An open popup takes the pointer, takes focus when it can, and returns focus to the previous widget when it closes. Escape closes the topmost popup; the rules are in `docs/events-focus.md`.

A popup menu draws its own opaque plate, which a theme or the program may recolour. Overlays draw their own plate, so the theme gives them no background. The file dialog shows the folder path and its entries; clicking a folder descends into it.

## Additional widgets

Every widget below registers its hooks in the kind registry and keeps its data in `src/GUI/widget_data.odin`, with one source file per widget in `src/GUI`.

### Toast

```odin
Toast_Opts :: struct {
	Base_Opts: Base_Opts,
	text:      string,
	kind:      Toast_Kind,
	duration:  f32,
}

Make_Toast :: proc(g: ^GUI, parent: Widget_ID, opts: Toast_Opts) -> Widget_ID
```

A message in a corner that hides itself. `kind` is `.Info`, `.Success`, `.Warning` or `.Error` and sets the colour. It takes no mouse or keyboard.

| Function | What it does |
|---|---|
| `Toast_Show(g, id, text, kind, duration)` | Shows a toast for `duration` seconds; 0 means three. |
| `Toast_Is_Visible(g, id)` | Whether the toast is on screen. |

### Command palette

```odin
Command_Palette_Opts :: struct { Base_Opts: Base_Opts }
Make_Command_Palette :: proc(g: ^GUI, parent: Widget_ID, opts: Command_Palette_Opts) -> Widget_ID
```

A filterable command list, hidden until opened, near the top of its parent unless placed otherwise.

| Function | What it does |
|---|---|
| `Command_Palette_Open(g, id)` | Opens the palette. |
| `Command_Palette_Close(g, id)` | Closes the palette. |
| `Command_Palette_Is_Open(g, id)` | Whether the palette is on screen. |
| `Command_Palette_Text(g, id)` | Current filter text. |
| `Command_Palette_Set_Text(g, id, text)` | Sets the filter text and refilters. |
| `Command_Palette_Add(g, id, label, action, keywords)` | Adds a command with filter keywords. |
| `Command_Palette_Count(g, id)` | Number of available commands. |
| `command_palette_move(g, id, delta)` | Moves the selection. |
| `command_palette_run(g, id)` | Runs the selected command. |
| `command_palette_reset(g, id)` | Clears the filter. |

Commands are shared with shortcuts:

```odin
Command_Add :: proc(g: ^GUI, name: string, shortcut: Shortcut, action: proc(g: ^GUI, id: Widget_ID)) -> int
```

### Rating

```odin
Rating_Opts :: struct {
	Base_Opts: Base_Opts,
	value:     f32,
	max:       f32,
	mark:      string,
}

Make_Rating :: proc(g: ^GUI, parent: Widget_ID, opts: Rating_Opts) -> Widget_ID
```

A row of selectable marks. `mark` is any character (a star by default), and marks sit in fixed-width slots.

| Function | What it does |
|---|---|
| `rating_value(g, id)` | Current value. |
| `rating_set(g, id, value)` | Sets the value, clamped to 0..max. Fires `on_value_changed`. |

### Segmented

```odin
Segmented_Opts :: struct {
	Base_Opts: Base_Opts,
	items:     []string,
}

Make_Segmented :: proc(g: ^GUI, parent: Widget_ID, opts: Segmented_Opts) -> Widget_ID
```

A row of buttons with one selected.

| Function | What it does |
|---|---|
| `segmented_count(g, id)` | Number of segments. |
| `segmented_select(g, id, index)` | Selects a segment. Fires `on_item_selected`. |
| `segmented_text(g, id)` | Text of the selected segment. |

### Toggle switch

```odin
Toggle_Switch_Opts :: struct {
	Base_Opts: Base_Opts,
	text:      string,
	on:        bool,
}

Make_Toggle_Switch :: proc(g: ^GUI, parent: Widget_ID, opts: Toggle_Switch_Opts) -> Widget_ID
```

| Function | What it does |
|---|---|
| `toggle_switch_set(g, id, on)` | Turns the switch on or off. Fires `on_toggled`. |
| `toggle_switch_is_on(g, id)` | Whether the switch is on. |

### Combo box

```odin
Combo_Box_Opts :: struct {
	Base_Opts: Base_Opts,
	items: []string,
}

Make_Combo_Box :: proc(g: ^GUI, parent: Widget_ID, opts: Combo_Box_Opts) -> Widget_ID
```

A field that opens a list of selectable items when clicked. The field is as wide as the widest item and no wider; size flags still apply.

| Function | What it does |
|---|---|
| `combo_box_add_item(g, id, text, icon)` | Adds an item; the icon is optional. |
| `combo_box_count(g, id)` | Number of items. |
| `combo_box_item_text(g, id, index)` | Text of an item. |
| `combo_box_selected(g, id)` | Selected index, or -1. |
| `combo_box_text(g, id)` | Text of the selected item. |
| `combo_box_select(g, id, index)` | Selects an item. Fires `on_item_selected`. |
| `combo_box_is_open(g, id)` | Whether the list is open. |
| `combo_box_set_open(g, id, open)` | Opens or closes the list. |

### Virtual list

```odin
Virtual_List_Opts :: struct {
	Base_Opts:  Base_Opts,
	source:     List_Source,
	row_height: f32,
}

Make_Virtual_List :: proc(g: ^GUI, parent: Widget_ID, opts: Virtual_List_Opts) -> Widget_ID
```

A list of any size that draws only the visible rows. Rows come from the program:

```odin
List_Source :: struct {
	count:  proc(ctx: rawptr) -> int,
	text:   proc(ctx: rawptr, index: int) -> string,
	key:    proc(ctx: rawptr, index: int) -> u64,
	height: proc(ctx: rawptr, index: int) -> f32,
	ctx:    rawptr,
}
```

`ctx` is passed to every callback. `key` defaults to the row index; `height` is only needed for rows of varying height. `List_Source_Texts` builds a source from strings, and `List_Texts_Add` appends one.

The widget requests one row at a time and never creates a widget per row. Selection is stored by key, so it survives reordering; call `virtual_list_refresh` after the source changes.

The list takes focus: arrow keys move the cursor, Shift extends the selection, Ctrl moves a screen at a time, Home/End jump to the ends, and the wheel scrolls.

| Function | What it does |
|---|---|
| `virtual_list_count(g, id)` | Number of rows. |
| `virtual_list_row_height(g, id)` | Row height. |
| `virtual_list_set_row_height(g, id, height)` | Sets the row height; 0 restores the default of 22. |
| `virtual_list_scroll(g, id)` | Current scroll offset. |
| `virtual_list_set_scroll(g, id, scroll)` | Scrolls to an offset, clamped. |
| `virtual_list_first_row(g, id)` | First visible row. |
| `virtual_list_set_first_row(g, id, first)` | Scrolls so `first` is the top row. |
| `virtual_list_visible_rows(g, id)` | Visible range as first row and one past the last. |
| `virtual_list_refresh(g, id)` | Reports a changed source; selections are restored by key. |
| `virtual_list_key(g, id, index)` | Key of a row. |
| `virtual_list_selected(g, id)` | Selected row, or -1. |
| `virtual_list_is_picked(g, id, index)` | Whether a row is selected. |
| `virtual_list_select(g, id, index)` | Selects one row, replacing the selection. Fires `on_item_selected`. |
| `virtual_list_toggle(g, id, index)` | Toggles a row in the selection. Fires `on_item_selected`. |
| `virtual_list_clear_selection(g, id)` | Clears the selection. |

### Data table

```odin
Data_Table_Opts :: struct {
	Base_Opts:     Base_Opts,
	source:        Table_Source,
	row_height:    f32,
	header_height: f32,
}

Make_Data_Table :: proc(g: ^GUI, parent: Widget_ID, opts: Data_Table_Opts) -> Widget_ID
```

A table with a sortable header. Cell values are strings. Rows come from the program:

```odin
Table_Source :: struct {
	count:  proc(ctx: rawptr) -> int,
	values: proc(ctx: rawptr, index: int) -> []string,
	key:    proc(ctx: rawptr, index: int) -> u64,
	ctx:    rawptr,
}
```

`key` defaults to the row index. `Table_Source_Rows` builds a source from program rows, and `Table_Rows_Add` appends one.

Columns belong to the table:

```odin
Data_Table_Column :: struct {
	title: string,
	width: f32,
	//* How the column gets its width.
	size: Data_Table_Column_Size,
	//* The width the column does not go below.
	min_width: f32,
	//* How the values of the column are put in order.
	sort: Data_Table_Sort,
	//* The order of two values, for the columns whose values are not
	//: in the order of the text.
	compare: proc(a, b: string) -> int,
}
```

`Data_Table_Column_Size` is `.Fixed` or `.Stretch` (a share of leftover width). `Data_Table_Sort` is `.None`, `.Ascending` or `.Descending`. `compare` overrides text ordering.

Only visible rows are drawn. The sort order is recomputed when the sort or filter changes, not per frame; a filter runs once over the source. Selection is stored by key, so it survives sorting and filtering. `data_table_selected_row` returns the visible row, `data_table_selected_source` the source row, and `on_item_selected` fires with the visible row.

The table takes focus: Up/Down move the selected row, Ctrl moves a screen, Left/Right move the selected column, Home/End jump to the ends. The wheel scrolls down; Shift+wheel scrolls sideways.

| Function | What it does |
|---|---|
| `data_table_add_column(g, id, title, width)` | Adds a column; width is in logical units. |
| `data_table_column_count(g, id)` | Number of columns. |
| `data_table_column(g, id, index)` | Column at an index. |
| `data_table_set_column(g, id, index, column)` | Replaces a column. |
| `data_table_column_width(g, id, index)` | On-screen column width. |
| `data_table_add_row(g, id, values)` | Adds a row to the table's own rows (unused when a source is set). |
| `data_table_set_row(g, id, index, values)` | Replaces a row of the table's own rows. |
| `data_table_set_source(g, id, source)` | Sets the row source; rows are not copied. |
| `data_table_row_count(g, id)` | Number of visible rows. |
| `data_table_source_row_count(g, id)` | Number of source rows before filtering. |
| `data_table_row_source(g, id, view)` | Source row for a visible row. |
| `data_table_cell(g, id, view, column)` | Cell value at a visible row. |
| `data_table_refresh(g, id)` | Reports a changed source; selection is restored by key. |
| `data_table_sort_by(g, id, column)` | Sorts by a column, ascending by default. |
| `data_table_sort_header(g, id, column)` | Sorts by a column; repeating the column reverses it. |
| `data_table_sort(g, id, column, direction)` | Sorts by a column in a given direction. |
| `data_table_set_filter(g, id, text)` | Filters rows by text. |
| `data_table_set_filter_fn(g, id, filter)` | Sets a row filter called for every source row. |
| `data_table_filter_text(g, id)` | Current filter text. |
| `data_table_selected_row(g, id)` | Selected visible row, or -1. |
| `data_table_selected_source(g, id)` | Selected source row, or -1. |
| `data_table_selected_key(g, id)` | Selected row key, or 0. |
| `data_table_selected_column(g, id)` | Selected column, or -1 for a whole-row selection. |
| `data_table_select_row(g, id, view)` | Selects a row and fires `on_item_selected`. |
| `data_table_select_cell(g, id, view, column)` | Selects a cell; column -1 selects the row. Fires `on_item_selected`. |
| `data_table_clear_selection(g, id)` | Clears the selection. |
| `data_table_scroll(g, id)` | Vertical scroll offset. |
| `data_table_set_scroll(g, id, scroll)` | Sets the vertical offset, clamped. |
| `data_table_h_scroll(g, id)` | Horizontal scroll offset. |
| `data_table_set_h_scroll(g, id, scroll)` | Sets the horizontal offset, clamped. |
| `data_table_visible_rows(g, id)` | Visible range as first row and one past the last. |

### Date picker

```odin
Date_Picker_Opts :: struct {
	Base_Opts: Base_Opts,
	year:      int,
	month:     int,
	day:       int,
}

Make_Date_Picker :: proc(g: ^GUI, parent: Widget_ID, opts: Date_Picker_Opts) -> Widget_ID
```

A field with a calendar; January is month 1.

| Function | What it does |
|---|---|
| `date_picker_date(g, id)` | Year, month and day. |
| `date_picker_text(g, id)` | Displayed date. |
| `date_picker_set_date(g, id, year, month, day)` | Sets the date. Fires `on_text_changed`. |
| `date_picker_is_open(g, id)` | Whether the calendar is open. |
| `date_picker_set_open(g, id, open)` | Opens or closes the calendar. |

### Time picker

```odin
Time_Picker_Opts :: struct {
	Base_Opts: Base_Opts,
	hour:      int,
	minute:    int,
}

Make_Time_Picker :: proc(g: ^GUI, parent: Widget_ID, opts: Time_Picker_Opts) -> Widget_ID
```

| Function | What it does |
|---|---|
| `time_picker_time(g, id)` | Hour and minute. |
| `time_picker_text(g, id)` | Displayed time. |
| `time_picker_set_time(g, id, hour, minute)` | Sets the time. Fires `on_text_changed`. |
| `time_picker_add_minutes(g, id, minutes)` | Advances the time. |
| `time_picker_is_open(g, id)` | Whether the list is open. |
| `time_picker_set_open(g, id, open)` | Opens or closes the list. |

### Color picker

```odin
Color_Picker_Opts :: struct {
	Base_Opts: Base_Opts,
	colour:    Colour,
}

Make_Color_Picker :: proc(g: ^GUI, parent: Widget_ID, opts: Color_Picker_Opts) -> Widget_ID
```

A colour field with a hue strip and a saturation/value square. Pressing either and dragging updates the colour live.

The `#RRGGBB` code is editable: a click places the caret, dragging selects, a double click selects a word, and the text box keys apply (`Ctrl+A`, `Ctrl+C`, `Ctrl+X`, `Ctrl+V`, `Ctrl+Z`, `Ctrl+Y`). Enter commits the code and Escape discards the edit; only hex digits and `#` are accepted.

| Function | What it does |
|---|---|
| `color_picker_colour(g, id)` | Selected colour. |
| `color_picker_set(g, id, colour)` | Sets the colour. Fires `on_colour_changed`. |
| `color_picker_set_hsv(g, id, hue, saturation, value)` | Sets the colour by HSV. Fires `on_colour_changed`. |
| `color_picker_is_open(g, id)` | Whether the picker is open. |
| `color_picker_set_open(g, id, open)` | Opens or closes the picker. |
| `color_picker_is_editing(g, id)` | Whether the colour code is being edited. |
| `color_picker_edit_text(g, id)` | The colour code being edited. |

### Emoji picker

```odin
Emoji_Picker_Opts :: struct {
	Base_Opts: Base_Opts,
	emoji:     string,
	group:     int,
}

Make_Emoji_Picker :: proc(g: ^GUI, parent: Widget_ID, opts: Emoji_Picker_Opts) -> Widget_ID
```

A field with an emoji picker. Groups are defined in `src/GUI/emoji_data.odin`. An emoji is an ordinary glyph, so the UI family needs it; without a fallback the picker still opens and reports picks but draws nothing, and `Font_Has_Glyph` confirms the gap. Set a colour emoji family as fallback:

```odin
emoji := GUI.Font_Family_Load(g, "assets/fonts/Twemoji-Mozilla.ttf")
GUI.Font_Family_Set_Fallback(g, family, emoji)
```

`assets/fonts/Twemoji-Mozilla.ttf` ships with the repository (Apache-2.0 and CC-BY-4.0, licence included). Runa reads COLR table version 0 layers only, so a COLRv1-only font such as Noto Color Emoji loads but draws nothing.

| Function | What it does |
|---|---|
| `emoji_picker_emoji(g, id)` | Selected emoji. |
| `emoji_picker_set(g, id, emoji)` | Sets the emoji. Fires `on_text_changed`. |
| `emoji_picker_group(g, id)` | Shown group. |
| `emoji_picker_set_group(g, id, group)` | Shows another group. |
| `emoji_picker_is_open(g, id)` | Whether the picker is open. |
| `emoji_picker_set_open(g, id, open)` | Opens or closes the picker. |

### Accordion

```odin
Accordion_Opts :: struct { Base_Opts: Base_Opts }
Make_Accordion :: proc(g: ^GUI, parent: Widget_ID, opts: Accordion_Opts) -> Widget_ID
```

A stack of sections (its children) with at most one open.

| Function | What it does |
|---|---|
| `accordion_open(g, id, index)` | Opens a section, or closes it when it is already open. |
| `accordion_open_section(g, id)` | Open section, or -1 when all are closed. |

### Context menu

```odin
Context_Menu_Opts :: struct {
	Base_Opts: Base_Opts,
	items:     []Context_Menu_Item,
}

Make_Context_Menu :: proc(g: ^GUI, parent: Widget_ID, opts: Context_Menu_Opts) -> Widget_ID
```

A menu that opens at the pointer. An item has text, an icon, the flags `separator`, `disabled` and `checked`, and an `action` run on selection.

| Function | What it does |
|---|---|
| `Context_Menu_Open(g, id, pos)` | Opens at a position in the parent's coordinates, sized to its content and kept inside the window. |
| `Context_Menu_Close(g, id)` | Closes the menu. |
| `Context_Menu_Is_Open(g, id)` | Whether the menu is on screen. |
| `Context_Menu_Add_Item(g, id, item)` | Adds an item. |

### Chat input

```odin
Chat_Input_Opts :: struct { Base_Opts: Base_Opts }
Make_Chat_Input :: proc(g: ^GUI, parent: Widget_ID, opts: Chat_Input_Opts) -> Widget_ID
```

A field with a transcript of lines above it. A line has `who`, `text` and a `system` flag marking program lines. The field supports `Ctrl+Z` and `Ctrl+Y`.

| Function | What it does |
|---|---|
| `chat_input_text(g, id)` | Current field text. |
| `chat_input_set_text(g, id, text)` | Sets the field text. |
| `chat_input_add_line(g, id, who, text, system)` | Adds a line above the field. |
| `chat_input_line_count(g, id)` | Number of lines. |
| `chat_input_line_text(g, id, index)` | Text of a line. |
| `chat_input_clear_lines(g, id)` | Removes all lines. |
| `chat_input_submit(g, id)` | Sends the field text as a line. Fires `on_submitted`. |

### Search field

```odin
Search_Field_Opts :: struct {
	Base_Opts:    Base_Opts,
	text:         string,
	placeholder:  string,
	hide_icon:    bool,
	max_width:    f32,
	on_submitted: proc(g: ^GUI, id: Widget_ID, text: string),
}

Make_Search_Field :: proc(g: ^GUI, parent: Widget_ID, opts: Search_Field_Opts) -> Widget_ID
```

A field with a magnifier and a clear button. The placeholder shows while the field is empty.

The field is as wide as its text, or as wide as the placeholder when empty, capped at `max_width` (default `SEARCH_FIELD_MAX_WIDTH`, 240). It is always one line: text never wraps, and Enter submits to `on_submitted` instead of inserting a newline. A click places the caret, arrow keys move it, Backspace deletes, and `Ctrl+Z` / `Ctrl+Y` undo and redo.

| Function | What it does |
|---|---|
| `search_field_text(g, id)` | Current text. |
| `search_field_set_text(g, id, text)` | Sets the text. Fires `on_text_changed`. |
| `search_field_clear(g, id)` | Clears the text. Fires `on_text_changed`. |
| `search_field_is_empty(g, id)` | Whether the field is empty. |
| `search_field_placeholder(g, id)` | Placeholder text. |
| `search_field_max_width(g, id)` | Maximum width. |
| `search_field_caret(g, id)` | Caret position as a byte offset. |
| `search_field_set_caret(g, id, offset)` | Places the caret. |

### Number input

```odin
Number_Input_Opts :: struct {
	Base_Opts: Base_Opts,
	value: f32,
	min:   f32,
	max:   f32,
	step:  f32,
}

Make_Number_Input :: proc(g: ^GUI, parent: Widget_ID, opts: Number_Input_Opts) -> Widget_ID
```

A numeric field with two arrows. The text is editable and the arrows step the value; `Ctrl+Z` and `Ctrl+Y` undo and redo.

| Function | What it does |
|---|---|
| `number_input_value(g, id)` | Current value. |
| `number_input_set(g, id, value)` | Sets the value, clamped. Fires `on_value_changed`. |
| `number_input_step_by(g, id, delta)` | Steps by `delta` x step through the setter. |
| `number_input_increment(g, id)` | Steps once. |
| `number_input_decrement(g, id)` | Steps back once. |
| `number_input_is_editing(g, id)` | Whether the text is being edited. |

### Tooltip

```odin
Tooltip_Opts :: struct {
	Base_Opts: Base_Opts,
	text:      string,
	target:    Widget_ID,
}

Make_Tooltip :: proc(g: ^GUI, parent: Widget_ID, opts: Tooltip_Opts) -> Widget_ID
```

The styled overlay that describes a control. It takes no mouse or keyboard and does not clip its children, because it is drawn next to the pointer, possibly outside its own rect.

The GUI creates one tooltip under the root at startup, so it is never clipped by a scroll container. A widget with `Base_Opts.tooltip` shows its text on hover. To use a custom tooltip, disable the built-in one with `Set_Tooltip_Enabled(g, false)` and take the widget with `Tooltip_Widget(g)`.

| Function | What it does |
|---|---|
| `Tooltip_Widget(g)` | The GUI's tooltip widget. |
| `Set_Tooltip_Enabled(g, enabled)` | Enables or disables the GUI tooltip. |
| `Tooltip_Enabled(g)` | Whether the GUI tooltip is enabled. |
| `Tooltip_Show(g, id, target, text)` | Shows a tooltip for a target. |
| `Tooltip_Hide(g, id)` | Hides a tooltip. |
| `Tooltip_Is_Visible(g, id)` | Whether a tooltip is on screen. |

## Heavy widgets

Application-grade widgets whose data lives behind a pointer, so the widget stays small however large its contents are.

### Chart

```odin
Chart_Opts :: struct {
	Base_Opts: Base_Opts,
	kind:      Chart_Kind,
}

Make_Chart :: proc(g: ^GUI, parent: Widget_ID, opts: Chart_Opts) -> Widget_ID
```

Bar, line and pie charts. `kind` is `.Bar`, `.Line` or `.Pie`; series are added one by one.

| Function | What it does |
|---|---|
| `chart_add_series(g, id, name, values, colour)` | Adds a series and returns its index. |
| `chart_set_kind(g, id, kind)` | Changes the chart kind. |
| `chart_series_count(g, id)` | Number of series. |
| `chart_point_count(chart)` | Number of points in a series. |
| `chart_set_labels(g, id, labels)` | Sets the point labels. |
| `chart_value_at(g, id, index)` | Value of a point. |
| `chart_point_at(g, id, pos)` | Point under a position. |

### Node graph

```odin
Node_Graph_Opts :: struct { Base_Opts: Base_Opts }
Make_Node_Graph :: proc(g: ^GUI, parent: Widget_ID, opts: Node_Graph_Opts) -> Widget_ID
```

Nodes with ports and wires. The wheel zooms and the middle button pans, keeping the graph anchored on screen.

| Function | What it does |
|---|---|
| `node_graph_add_node(g, id, title, pos)` | Adds a node and returns its index. |
| `node_graph_add_port(g, id, node, name, direction)` | Adds a port (`.Input`, `.Output` or `.Both`) and returns its index. |
| `node_graph_connect(g, id, from_node, from_port, to_node, to_port)` | Connects two ports, returning the wire index or -1 when a port is missing. |
| `node_graph_node_count(g, id)` | Number of nodes. |
| `node_graph_wire_count(g, id)` | Number of wires. |
| `node_graph_node_at(g, id, pos)` | Node under a position. |
| `node_graph_move_node(g, id, node, pos)` | Moves a node. |
| `node_graph_zoom(g, id)` | Current zoom; 1 is the constructed size. |
| `node_graph_set_zoom(g, id, zoom)` | Sets the zoom, clamped to the allowed range. |
| `node_graph_pan(g, id)` | Current pan within the widget. |
| `node_graph_set_pan(g, id, pan)` | Sets the pan. |
| `node_graph_reset_view(g, id)` | Resets zoom and pan. |

### Canvas

```odin
Canvas_Opts :: struct { Base_Opts: Base_Opts }
Make_Canvas :: proc(g: ^GUI, parent: Widget_ID, opts: Canvas_Opts) -> Widget_ID
```

A widget the program draws itself, either by filling its state with `Canvas_Item` values (`.Rect`, `.Circle`, `.Line` or `.Text`) or by supplying a paint callback.

| Function | What it does |
|---|---|
| `canvas_set_paint(g, id, paint)` | Installs a draw callback, called every frame. |
| `canvas_add_item(g, id, item)` | Adds an item. |
| `canvas_clear(g, id)` | Removes all items. |
| `canvas_item_count(g, id)` | Number of items. |
| `canvas_add_rect(g, id, pos, size, colour)` | Adds a rectangle. |
| `canvas_add_circle(g, id, pos, size, colour)` | Adds a circle. |
| `canvas_add_line(g, id, from, to, colour)` | Adds a line. |
| `canvas_add_text(g, id, pos, text, colour)` | Adds text. |

### File viewer

```odin
File_Viewer_Opts :: struct { Base_Opts: Base_Opts }
Make_File_Viewer :: proc(g: ^GUI, parent: Widget_ID, opts: File_Viewer_Opts) -> Widget_ID
```

A directory listing. The program supplies the loader; the widget reloads when the path changes.

| Function | What it does |
|---|---|
| `file_viewer_set_load(g, id, load)` | Installs the loader, called with the widget state. |
| `file_viewer_set_path(g, id, path)` | Sets the directory and reloads. |
| `file_viewer_path(g, id)` | Current directory. |
| `file_viewer_entry_count(g, id)` | Number of entries. |
| `file_viewer_selected(g, id)` | Selected entry, or -1. |
| `file_viewer_entry_name(g, id, index)` | Entry name. |
| `file_viewer_add_entry(g, id, name, size, directory)` | Adds an entry. |
| `file_viewer_clear(g, id)` | Removes all entries. |
| `file_viewer_select(g, id, index)` | Selects an entry. Fires `on_item_selected`. |

### Rich text editor

```odin
Rich_Text_Editor_Opts :: struct {
	Base_Opts: Base_Opts,
	text:      string,
	wrap:      bool,
	rules:     Text_Rules,
}

Make_Rich_Text_Editor :: proc(g: ^GUI, parent: Widget_ID, opts: Rich_Text_Editor_Opts) -> Widget_ID
```

Multi-style text with multiple cursors held in the editor state. Editing follows the text box model: drag selects, a double click selects a word, `Ctrl+A` selects all, `Ctrl+Z` / `Ctrl+Y` undo and redo, and `rules` limit input.

| Function | What it does |
|---|---|
| `rich_text_editor_text(g, id)` | Current text. |
| `rich_text_editor_set_text(g, id, text)` | Sets the text. Fires `on_text_changed`. |
| `rich_text_editor_is_wrapped(g, id)` | Whether the text wraps. |
| `rich_text_editor_set_wrap(g, id, wrap)` | Turns wrapping on or off. |
| `rich_text_editor_scroll(g, id, delta)` | Scrolls the text. |
| `rich_text_editor_cursor_count(g, id)` | Number of cursors. |
| `rich_text_editor_add_cursor(g, id, offset)` | Adds a cursor and returns its index. |
| `rich_text_editor_remove_cursor(g, id, index)` | Removes a cursor and returns the index now at that position. |
| `rich_text_editor_cursor(g, id, index)` | A cursor's caret and selection. |
| `rich_text_editor_set_caret(g, id, offset, extend)` | Places a cursor's caret at an offset. |
| `rich_text_editor_move_caret(g, id, forward, extend)` | Moves a cursor's caret. |
| `rich_text_editor_select_all(g, id)` | Selects all text. |
| `rich_text_editor_insert(g, id, text)` | Inserts text at the cursors. Fires `on_text_changed`. |
| `rich_text_editor_backspace(g, id)` | Deletes before the cursors. Fires `on_text_changed`. |
| `rich_text_editor_delete(g, id)` | Deletes after the cursors. Fires `on_text_changed`. |

### Vector drawing

```odin
Vector_Drawing_Opts :: struct { Base_Opts: Base_Opts }
Make_Vector_Drawing :: proc(g: ^GUI, parent: Widget_ID, opts: Vector_Drawing_Opts) -> Widget_ID
```

Editable lines and shapes. A shape is `.Line`, `.Rect`, `.Ellipse` or `.Polygon`.

| Function | What it does |
|---|---|
| `vector_drawing_add_shape(g, id, shape)` | Adds a shape and returns its index. |
| `vector_drawing_shape_count(g, id)` | Number of shapes. |
| `vector_drawing_shape_at(g, id, pos)` | Shape under a position. |
| `vector_drawing_move_shape(g, id, index, delta)` | Moves a shape. |
| `vector_drawing_selected(g, id)` | Selected shape, or -1. |
| `vector_drawing_zoom(g, id)` | Current zoom. |
| `vector_drawing_set_zoom(g, id, zoom)` | Sets the zoom. |
| `vector_drawing_add_line(g, id, a, b, colour, width)` | Adds a line. |
| `vector_drawing_add_rect(g, id, top_left, bottom_right, colour, width)` | Adds a rectangle. |
| `vector_drawing_add_ellipse(g, id, centre, radii, colour, width)` | Adds an ellipse. |
| `vector_drawing_add_polygon(g, id, points, colour, width)` | Adds a polygon. |

### Audio player

```odin
Audio_Player_Opts :: struct {
	Base_Opts: Base_Opts,
	path:      string,
	volume:    f32,
	loops:     bool,
}

Make_Audio_Player :: proc(g: ^GUI, parent: Widget_ID, opts: Audio_Player_Opts) -> Widget_ID
```

Plays audio through the GUI audio binding. The core never touches a sound card: a backend installs the binding, and without one the player still shows the file and its buttons but plays nothing. The SDL3 backend reads 16-bit WAV files. The player shows the file, the position and play/stop buttons. A volume of 0 keeps the GUI volume unchanged.

```odin
import Backend "../../src/Backend"

//* False when there is no sound card: the GUI stays usable without it.
Backend.sdl3_audio_install(app.gui)
```

| Function | What it does |
|---|---|
| `audio_play(g, path)` | Plays a file, or restarts it from the beginning. |
| `audio_stop(g)` | Stops playback. |
| `audio_position(g)` | Position in seconds. |
| `audio_length(g)` | Length in seconds. |
| `audio_is_playing(g)` | Whether audio is playing. |
| `audio_set_volume(g, volume)` | Sets volume from 0 to 1. |
| `audio_volume(g)` | Current volume. |
| `audio_player_path(g, id)` | The file being played. |
| `audio_player_set_path(g, id, path)` | Sets the file. |
| `audio_player_is_playing(g, id)` | Whether the player is playing. |
| `audio_player_position(g, id)` | Position in seconds. |
| `audio_player_length(g, id)` | Length in seconds. |

## Signals

Every widget has the same signal set, so a program can connect to any widget without knowing its kind. They are declared in `src/GUI/signal.odin`:

```odin
Signals :: struct {
	//* The widget was pressed. A button fires it when the pointer is
	//* let go over it.
	on_pressed: proc(g: ^GUI, id: Widget_ID),
	//* The widget was turned on or off.
	on_toggled: proc(g: ^GUI, id: Widget_ID, on: bool),
	//* The link of the widget was activated. It gives true back when
	//* the program took the link.
	on_link_activated: proc(g: ^GUI, id: Widget_ID, link: string) -> bool,
	//* The value of the widget changed.
	on_value_changed: proc(g: ^GUI, id: Widget_ID, value: f32),
	//* The colour of the widget changed.
	on_colour_changed: proc(g: ^GUI, id: Widget_ID, colour: Colour),
	//* The text of the widget changed.
	on_text_changed: proc(g: ^GUI, id: Widget_ID, text: string),
	//* An item of the widget was picked.
	on_item_selected: proc(g: ^GUI, id: Widget_ID, index: int),
	//* The widget was submitted: the enter key in a text field, or a
	//* double click in a list.
	on_submitted: proc(g: ^GUI, id: Widget_ID, text: string),
	//* The widget got the keyboard focus.
	on_focus_entered: proc(g: ^GUI, id: Widget_ID),
	//* The widget lost the keyboard focus.
	on_focus_exited: proc(g: ^GUI, id: Widget_ID),
	//* The widget was dragged.
	on_dragged: proc(g: ^GUI, id: Widget_ID, delta: Vec2),
	//* The widget was resized.
	on_resized: proc(g: ^GUI, id: Widget_ID, size: Vec2),
}
```

An unconnected signal is nil, and firing it costs only the nil check. Each widget section names the signals it fires; `on_dragged` and `on_resized` are currently unfired. Connect a signal by assigning it on the widget:

```odin
w := GUI.Widget_Get(g, id)
w.signals.on_pressed = on_pressed
```

## Writing a widget

The smallest program is in the README. This example shows options, a signal and a runtime change; widgets are created once and then found again by id.

```odin
counter: GUI.Widget_ID
presses: int

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

	counter = GUI.Make_Button(g, box, GUI.Button_Opts{
		Base_Opts = GUI.Base_Opts{name = "counter"},
		text = "Press me",
		on_pressed = on_pressed,
	})
}

on_pressed :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) {
	presses += 1
	w := GUI.Widget_Get(g, id)
	w.style.box.bg_color = GUI.RGBA(0.20, 0.60, 1.00, 1)
}

update :: proc(g: ^GUI.GUI, id: GUI.Widget_ID, value: f32) {
	GUI.slider_set_value(g, id, value)
	w := GUI.Widget_Get(g, id)
	w.style.box.bg_color = GUI.RGBA(0.20, 0.60, 1.00, 1)
}
```

Widget state lives in the widget. `Widget_Get` returns a pointer, so the program writes fields directly instead of calling a setter. Kind-specific data is in `w.data`, a tagged union read with a switch:

```odin
#partial switch &d in w.data {
case GUI.Button_Data:
	d.text = "Pressed"
}
```

## Removing a widget

`Widget_Free` destroys a widget and everything under it:

```odin
Widget_Free :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) -> bool
```

The handle survives but names nothing, and a widget recreated in the same place gets a fresh handle, so a stale handle is never mistaken for a new widget. Check with `Widget_Alive`:

```odin
if GUI.Widget_Alive(g, id) {
    //* The widget is still there.
}
```

Freeing releases everything that refers to the widget: focus, pointer capture, drag, resize, its floating panel and references from other widgets. It also releases owned buffers, such as a text field's buffer or a data table's rows.

A widget can be moved instead of destroyed. `Widget_Attach` and `Widget_Insert_At` reparent it, preserving its handle so existing references stay valid:

```odin
GUI.Widget_Attach(g, other_box, panel)
```

Widgets can also be created by kind:

```odin
New_Widget :: proc(g: ^GUI, type: Widget_Type, parent: Widget_ID, opts: Widget_Opts = {}) -> Widget_ID
```

`Image` has no data and is not drawn. A scene node of a kind without a constructor, such as `Image`, is reported as an error and skipped by the loader; see [docs/scene-format.md](scene-format.md).
