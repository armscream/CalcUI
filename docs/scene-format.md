# CalcUI Scene Files

Scene files define widget trees in a text format similar to Godot's. Each node has a header and optional properties.

Implementation:
- `src/GUI/scene.odin` — parser and loader.
- `src/GUI/scene_save.odin` — scene writer.
- `src/GUI/scene_report.odin` — diagnostics.

## File Format

```text
[node name="Root" type="Panel"]
    bg = {0.07, 0.08, 0.10, 1}

[node name="Title" type="Label" parent="Root"]
    text = "Hello"
```

Headers accept `name`, `type` and `parent`. Nodes without a parent attach to the GUI root. Parents are resolved by name and may appear later in the file.

Properties use one `key = value` pair per line. Blank lines, comments (`#`) and non-node sections are ignored.

Header values can be quoted or unquoted. Quoted strings support `\n`, `\t`, `\r`, `\"` and `\\`. Unknown escapes discard the backslash.

## Properties

| Category | Properties |
|---|---|
| Identity | `name`, `type`, `parent` |
| Layout | `anchors`, `offsets`, `min_size`, `custom_min_size`, `weight` |
| Visibility and input | `visible`, `interactive` |
| Text | `text`, `font`, `font_size`, `colour` |
| Box style | `bg`, `border`, `border_width`, `padding`, `corner_radius` |
| Glass effects | `backdrop_blur`, `optics_refraction`, `optics_dispersion`, `optics_fresnel`, `optics_saturation` |
| Shadows | `shadow`, `shadow_size`, `shadow_offset`, `shadow_spread`, `shadow_inset` |
| Textures | `texture`, `patch`, `source`, `tint`, `horizontal_edge`, `vertical_edge`, `centre_mode` |
| Tabs and docking | `active`, `floating`, `float_pos`, `float_size` |

Values are comma-separated, with optional braces:

```text
anchors = {0, 0, 1, 1}
offsets = 20, 20, -20, 56
colour = {0.92, 0.94, 0.98, 1}
min_size = {120, 30}
```

Four-value lists use left, top, right, bottom order. Anchors are parent-relative fractions; offsets are logical units. Colours use RGBA values from 0 to 1.

`corner_radius` accepts one value or four values in top-left, top-right, bottom-right, bottom-left order. `shadow_offset` and other two-value properties use x and y.

Malformed values and incorrect entry counts are ignored and reported.

### Widget-specific properties

- `text` applies to text-capable widgets, including `Label`, `Button`, `TextBox`, `RichTextLabel`, `NodeGraph`, `CommandPalette`, `ChatInput` and other text widgets.
- `TextInput` and `TextEdit` alias `TextBox`; `TextEdit` is multiline.
- `weight` applies to split children. `active` applies to `Tabs` and `TabContainer`.
- `floating`, `float_pos` and `float_size` apply to any node.
- `ColorRect` uses `bg` as its fill colour.
- `TextureRect` and `NinePatchRect` use `texture`. Relative texture paths resolve against the working directory.
- `NinePatchRect` additionally supports `patch`, `source`, `tint`, `horizontal_edge`, `vertical_edge` and `centre_mode`.

A texture path that cannot be read is an error and leaves the texture empty.

For `NodeGraph`, `text` contains the versioned graph data produced by `node_graph_save` and consumed by `node_graph_load`. Newlines are escaped as `\n`. Without `text`, the graph is empty.

```text
[node name="Graph" type="NodeGraph"]
    text = "graph version=1 zoom=1 pan=0,0 ..."
```

## Styling and Fonts

Scene styles override the theme. Properties not specified by the scene continue to use theme values.

- `bg`, `border`, `border_width`, `padding`, `corner_radius`, glass and shadow properties configure the box style.
- `colour` and `font_size` configure text.
- `font` selects a registered font family.

Register a font family before loading a scene:

```odin
family := GUI.Font_Family_Add(g, "Roboto", bytes)
```

The registered family name is used in the scene. A loaded font path is used as its name. Unknown families produce an error and fall back to the theme font; an empty name produces a warning and is ignored.

## Building the Widget Tree

Nodes are instantiated under the GUI root. The loader attaches each node to its resolved parent, retrying nodes whose parents have not yet been created.

- The first successfully created node is the scene root.
- A node that cannot be created is skipped, but its name is retained so its children can still attach to the intended parent.
- Duplicate names are errors. The later node is skipped, and children resolve to the first occurrence.
- Missing parents, self-parenting and cycles are errors; affected nodes attach to the GUI root.
- If nothing can be instantiated, the loader returns `INVALID_WIDGET_ID`.

## Custom Constructors

Scenes use a per-GUI constructor table:

```odin
Scene_Constructor :: proc(
    g: ^GUI,
    parent: Widget_ID,
    name: string,
    text: string,
) -> Widget_ID

Scene_Register_Constructor :: proc(
    g: ^GUI,
    widget_type: Widget_Type,
    constructor: Scene_Constructor,
) -> bool
```

Register constructors before loading. A nil constructor fails registration; registering an existing type replaces it. `Scene_Constructor_Of` retrieves a registered constructor or returns nil.

For example, a program can replace the built-in `Label` constructor:

```odin
make_my_label :: proc(
    g: ^GUI.GUI,
    parent: GUI.Widget_ID,
    name: string,
    text: string,
) -> GUI.Widget_ID {
    return GUI.Make_Button(g, parent, GUI.Button_Opts{
        Base_Opts = GUI.Base_Opts{name = name},
        text = text,
    })
}

GUI.Scene_Register_Constructor(g, .Label, make_my_label)
```

Custom widget classes are checked before the constructor table, allowing them to be used as scene node types without a `Widget_Type` value:

```odin
GUI.Widget_Register_Class(g, GUI.Widget_Class_Desc{
    name = "MyGauge",
    type = .Panel,
    kind = GUI.Widget_Kind{
        draw = my_gauge_draw,
        measure = my_gauge_measure,
    },
    constructor = make_my_widget,
})
```

```text
[node name="Gauge" type="MyGauge"]
```

A custom class without its own constructor falls back to a widget type with the same name. Built-in constructors are registered on the first scene load and preserve earlier registrations. `Image` and `ScrollArea` do not have built-in constructors.

## Loading Scenes

```odin
Scene_Load :: proc(g: ^GUI, text: string) -> Widget_ID

Scene_Load_Report :: proc(
    g: ^GUI,
    text: string,
) -> (Widget_ID, Scene_Report)
```

`Scene_Load` logs diagnostics. `Scene_Load_Report` returns them to the caller.

`Load_UI(path, g)` reads and loads a scene file, returning `INVALID_WIDGET_ID` if reading fails.

```odin
root := GUI.Load_UI("scene.txt", g)
if root == GUI.INVALID_WIDGET_ID {
    log.error("the scene did not load")
}
```

## Parsing and Reuse

Scenes can be parsed once and instantiated multiple times:

```odin
Scene_Parse :: proc(
    text: string,
    allocator: mem.Allocator,
) -> (Scene_Doc, Scene_Report)

Scene_Instantiate :: proc(
    g: ^GUI,
    doc: Scene_Doc,
) -> (Widget_ID, Scene_Report)
```

Example:

```odin
doc, parse_report := GUI.Scene_Parse(text, context.allocator)
defer GUI.Scene_Doc_Destroy(&doc)
defer GUI.Scene_Report_Destroy(&parse_report)

root, load_report := GUI.Scene_Instantiate(g, doc)
defer GUI.Scene_Report_Destroy(&load_report)
```

The caller owns the parse allocator and must destroy the document and parse report. Instantiation does not modify the document. Widget names and text are copied into the GUI arena, so the document can be destroyed immediately afterward.

A parsed document stores node names, types, parents, text, font names, properties and paths. Manually constructed documents have no allocator; their strings remain caller-owned.

## Diagnostics

Scene operations report problems using:

```odin
Scene_Severity :: enum { Note, Warning, Error }

Scene_Diagnostic :: struct {
    severity: Scene_Severity,
    line:     int,
    node:     string,
    property: string,
    message:  string,
}

Scene_Report :: struct {
    entries:   [dynamic]Scene_Diagnostic,
    allocator: mem.Allocator,
}
```

| Problem | Severity | Result |
|---|---|---|
| Unknown or unsupported property | Warning | Property ignored |
| Invalid property value | Warning | Property ignored |
| Empty font name | Warning | Property ignored |
| Unknown font family | Error | Theme font used |
| Missing or invalid widget type | Error | Node skipped |
| Missing constructor | Error | Node skipped |
| Duplicate node name | Error | Later node skipped |
| Missing parent or parent cycle | Error | Node attaches to GUI root |

Reports own their strings and must be released:

```odin
root, report := GUI.Scene_Load_Report(g, text)
defer GUI.Scene_Report_Destroy(&report)
```

Helpers:

```odin
Scene_Report_Has_Errors :: proc(report: ^Scene_Report) -> bool

Scene_Report_To_String :: proc(
    report: ^Scene_Report,
    allocator: mem.Allocator,
) -> string
```

`Scene_Report_To_String` returns allocator-owned text that must be freed with `delete`. `Scene_Parse` allocates its report from the document allocator; `Scene_Instantiate` and `Scene_Load_Report` use the GUI arena.

## Finding Widgets

`Scene_Find` searches for a widget by its path from the scene root:

```odin
Scene_Find :: proc(
    g: ^GUI,
    root: Widget_ID,
    path: string,
) -> Widget_ID
```

For example, `Root/Box/Ok` identifies the `Ok` button below `Root/Box`. It returns `INVALID_WIDGET_ID` if no match exists. Duplicate child names produce identical paths, and the first match wins. Parsed paths are also available through `doc.nodes[i].path`.

## Saving Scenes

```odin
Scene_Save :: proc(
    g: ^GUI,
    root: Widget_ID,
    allocator: mem.Allocator = context.allocator,
) -> string

Scene_Save_File :: proc(
    g: ^GUI,
    root: Widget_ID,
    path: string,
) -> bool
```

The `_With_Options` variants accept:

```odin
Scene_Save_Options :: struct {
    dock_layout: bool,
}
```

When enabled, `dock_layout` includes split weights, active tabs and floating panels. It is disabled by default.

`Scene_Save` returns allocator-owned text; free it with `delete(text, allocator)`. `Scene_Save_File` returns whether the write succeeded.

The writer:
- Makes duplicate names unique in the file (`Ok`, `Ok2`, etc.) without changing widget names.
- Generates names for unnamed widgets.
- Saves custom classes without constructors using their base widget type.
- Omits widgets without constructors while preserving their children's intended parent.
- Always writes anchors and offsets.
- Writes `interactive` only when it differs from the widget type's default.
- Saves texture paths and relevant nine-patch settings.
- Does not save runtime content such as list items, table rows, chat lines, command-palette commands or custom widget state.

## Docking Layout

With `dock_layout = true`, the writer also saves docking information:

```text
[dock]
    version = 1
    viewport = {0, 0, 1100, 700}
    window_rect = {100, 80, 1100, 700}

[node name="Inspector" type="Panel"]
    floating = true
    float_pos = {260, 140}
    float_size = {320, 220}
```

The `[dock]` section records the version, viewport and saving window rectangle. The rectangle is informational; loading does not move or resize the window.

Split weights and active tab indices are restored. Floating panels are detached after their nodes and children are created.

Invalid floating panels remain in the tree and produce diagnostics. Unsupported docking versions produce a warning and leave floating panels in the tree. Tab indices are clamped to the available tabs.

Saving the same layout produces consistent text: tree nodes follow tree order, and floating panels follow GUI list order.
