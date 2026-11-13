# CalcUI Scene Files

Scene files describe widget trees in text. The format is similar to Godot's: each node starts with a `[node ...]` header followed by `key = value` properties.

The parser, loader, writer and diagnostics are in:

- `src/GUI/scene.odin`
- `src/GUI/scene_save.odin`
- `src/GUI/scene_report.odin`

## File format

A scene is a list of nodes:

```text
[node name="Root" type="Panel"]
[node name="Title" type="Label" parent="Root"]
    text = "Hello"
```

Headers accept `name`, `type` and `parent`. A node without a parent is attached to the GUI root. Header values may be quoted or unquoted; quoted values end at the first unescaped quote. Unquoted values end at a space or the end of the header.

Properties use one `key = value` pair per line. Blank lines and lines beginning with `#` are ignored. Non-node sections, including their properties, are skipped.

`name`, `type` and `parent` can also be set as properties. These values override the header attributes.

## Supported properties

| Property | Meaning | Value |
|---|---|---|
| `name` | Node name. | Quoted string. |
| `type` | Widget type, such as `Panel`, `Label`, `Button`, `TextBox` or `VBox`. | `Widget_Type` name. |
| `parent` | Parent node name. | Quoted string. |
| `text` | Widget text. | Quoted string. |
| `anchors` | Position relative to the parent. | Four numbers. |
| `offsets` | Offset from the anchors. | Four numbers. |
| `colour` | Text colour. | RGBA values. |
| `bg` | Background colour. | RGBA values. |
| `border` | Border colour. | RGBA values. |
| `border_width` | Border width on each side. | Number. |
| `padding` | Inner spacing. | Four numbers. |
| `font_size` | Text size. | Number. |
| `font` | GUI font-family name. | String. |
| `visible` | Widget visibility. | `true` or `false`. |
| `min_size` | Minimum size requested by the widget. | Two numbers. |
| `custom_min_size` | Minimum size imposed by the program. | Two numbers. |

All widget types use the layout, visibility, font, colour, border and background properties. Only text-capable widgets use `text`: `Button`, `Label`, `TextBox`, `CheckBox`, `MenuButton`, `LinkButton`, `RichTextLabel`, `AcceptDialog`, `ConfirmationDialog`, `Toast`, `CommandPalette`, `ToggleSwitch`, `RichTextEditor`, `ChatInput`, `SearchField`, `Tooltip` and `EmojiPicker`.

For `CommandPalette`, `text` sets the filter text; for `ChatInput`, it sets the field contents. For `SearchField`, it sets the empty-field prompt, and for `EmojiPicker`, the displayed emoji. `TextInput` and `TextEdit` remain valid aliases for `TextBox`; `TextEdit` creates a multiline box.

### Values and parsing

Number lists are comma-separated; braces are optional:

```text
anchors = {0, 0, 1, 1}
offsets = 20, 20, -20, 56
colour = {0.92, 0.94, 0.98, 1}
min_size = {120, 30}
```

Four-value lists use left, top, right, bottom order. Anchors are parent-relative fractions from 0 to 1; offsets use logical units. Colours are RGBA values from 0 to 1.

Invalid values are ignored and reported. This includes malformed numbers, lists with the wrong number of entries and invalid `visible` values.

Quoted strings support `\n`, `\t`, `\r`, `\"` and `\\`. Unknown escapes keep the character after the backslash and discard the backslash. A quote is escaped only when preceded by an odd number of backslashes. Unquoted text is taken as-is.

### Styling and fonts

`anchors` and `offsets` correspond to `Base_Opts`. `bg`, `border`, `border_width` and `padding` set the widget box; `colour` and `font_size` set its text style. Scene styles are applied over the theme, so unspecified values come from the theme.

`font` selects a font family already registered with the GUI:

```odin
family := GUI.Font_Family_Add(g, "Roboto", bytes)
```

Use the family name supplied to `Font_Family_Add`. A font loaded from a file uses its path as the family name. An unknown family is an error and the widget falls back to the theme font; an empty name is a warning and is ignored. The family belongs to the GUI, while the name stored in the scene document belongs to that document.

`ColorRect` uses `bg` as its fill colour. Scene-loaded widgets use the theme and then apply the style specified by the node:

```odin
Widget_Set_Use_Theme(g, id, true)
Widget_Set_Style(g, id, scene_style(node, family))
```

## Building the widget tree

Nodes are instantiated under the GUI root. A node attaches to its parent if that parent has already been created. If the parent appears later, the node waits; the loader retries waiting nodes until no further progress can be made.

If a node cannot be created, it is skipped, but its name is retained so its children can attach to the node's intended parent. The first node successfully created is returned as the scene root.

Parents are resolved by name. Duplicate names are errors: the later node is skipped and its children resolve to the first node with that name. Missing parents, self-parenting and parent cycles are errors; affected nodes are attached to the GUI root. A file with no instantiable nodes returns `INVALID_WIDGET_ID`.

## Diagnostics

The loader reports problems with a severity, line number, node, property and message:

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
    entries:  [dynamic]Scene_Diagnostic,
    allocator: mem.Allocator,
}
```

| Problem | Severity | Result |
|---|---|---|
| Unknown property or property unsupported by the widget type | Warning | Property ignored. |
| Invalid property value | Warning | Property ignored. |
| Empty font-family name | Warning | Property ignored. |
| Unknown font family | Error | Theme font used. |
| Missing or invalid widget type | Error | Node skipped. |
| Widget type has no constructor | Error | Node skipped. |
| Duplicate node name | Error | Later node skipped. |
| Missing parent, self-parent or parent cycle | Error | Affected node attached to GUI root. |

Unknown properties are ignored, which allows files containing properties from newer versions to remain partially loadable. Parent nodes may also appear later in the file.

`Scene_Report` owns copies of its entry strings, so it remains valid after the document is destroyed. Destroy it with `Scene_Report_Destroy`:

```odin
root, report := GUI.Scene_Load_Report(g, text)
defer GUI.Scene_Report_Destroy(&report)
```

The report allocator depends on how it was created: `Scene_Parse` uses the supplied document allocator; `Scene_Instantiate` and `Scene_Load_Report` use the GUI arena. GUI-arena allocations are reclaimed when the GUI shuts down.

Two helpers are provided:

```odin
Scene_Report_Has_Errors :: proc(report: ^Scene_Report) -> bool
Scene_Report_To_String :: proc(report: ^Scene_Report, allocator: mem.Allocator) -> string
```

`Scene_Report_Has_Errors` checks for errors. `Scene_Report_To_String` formats one diagnostic per line in the supplied allocator; release the returned string with `delete`.

## Constructors

The loader creates widgets through a constructor table stored on each GUI instance:

```odin
Scene_Constructor :: proc(g: ^GUI, parent: Widget_ID, name: string, text: string) -> Widget_ID

Scene_Register_Constructor :: proc(g: ^GUI, widget_type: Widget_Type, constructor: Scene_Constructor) -> bool
Scene_Constructor_Of :: proc(g: ^GUI, widget_type: Widget_Type) -> Scene_Constructor
```

Register constructors before loading a scene. Registering a nil constructor fails; registering an existing type replaces its constructor and reports the replacement. `Scene_Constructor_Of` returns the registered constructor or nil.

For example, a program can use a custom constructor for the built-in `Label` type:

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

Custom widget classes are checked before the constructor table. A class can therefore be used as a scene node type without adding a `Widget_Type` enum value:

```odin
class_id := GUI.Widget_Register_Class(g, GUI.Widget_Class_Desc{
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
[node name="Root" type="Panel"]
    [node name="Gauge" type="MyGauge" parent="Root"]
```

A class without its own constructor falls back to a constructor for a widget type with the same name. A custom class whose name does not match a widget type therefore needs its own constructor. Built-in constructors are registered when the first scene is loaded; constructors registered by the program beforehand are retained. `Image` and `ScrollArea` have no built-in constructor.

## Loading scenes

`Scene_Load` builds a widget tree from scene text and logs diagnostics:

```odin
Scene_Load :: proc(g: ^GUI, text: string) -> Widget_ID
Scene_Load_Report :: proc(g: ^GUI, text: string) -> (Widget_ID, Scene_Report)
```

Use `Scene_Load_Report` when the caller needs to inspect diagnostics directly:

```odin
package main

import "core:log"
import "core:os"
import GUI "calcui/src/GUI"

load_scene :: proc(g: ^GUI.GUI, path: string) -> GUI.Widget_ID {
    bytes, read_err := os.read_entire_file_from_path(path, context.allocator)
    if read_err != nil {
        log.errorf("could not read scene %s: %v", path, read_err)
        return GUI.INVALID_WIDGET_ID
    }
    defer delete(bytes)

    root, report := GUI.Scene_Load_Report(g, string(bytes))
    defer GUI.Scene_Report_Destroy(&report)
    for entry in report.entries {
        log.warnf("scene:%d: %s", entry.line, entry.message)
    }
    return root
}
```

`Load_UI(path, g)` is a convenience function that reads a file and loads it. It returns an invalid widget ID if the file cannot be read. File contents are kept in the GUI arena until shutdown:

```odin
root := GUI.Load_UI("scene.txt", g)
if root == GUI.INVALID_WIDGET_ID {
    log.error("the scene did not load")
}
```

## Parse once, instantiate more than once

Use `Scene_Parse` to create a reusable document, then `Scene_Instantiate` to create separate widget trees from it:

```odin
Scene_Parse :: proc(text: string, allocator: mem.Allocator) -> (Scene_Doc, Scene_Report)
Scene_Instantiate :: proc(g: ^GUI, doc: Scene_Doc) -> (Widget_ID, Scene_Report)
```

The document is not modified by instantiation:

```odin
doc, report := GUI.Scene_Parse(text, allocator)
defer GUI.Scene_Doc_Destroy(&doc)
defer GUI.Scene_Report_Destroy(&report)

root, tree_report := GUI.Scene_Instantiate(g, doc)
defer GUI.Scene_Report_Destroy(&tree_report)
```

The caller owns the allocator passed to `Scene_Parse` and must destroy the document and parse report. The document stores node names, types, parents, text, font-family names, property keys and values, and node paths. `Scene_Doc_Destroy` releases these strings when the document has an allocator. A document built manually has no allocator; its strings remain owned by the caller.

Widget names and text are copied into the GUI arena during instantiation. The document can be destroyed immediately afterward without invalidating the widgets:

```odin
doc, report := GUI.Scene_Parse(text, context.allocator)
defer GUI.Scene_Doc_Destroy(&doc)
defer GUI.Scene_Report_Destroy(&report)

root, _ := GUI.Scene_Instantiate(g, doc)
// The document can be released; widget names and text remain valid.
```

The font-family name belongs to the document, but the registered font family belongs to the GUI. GUI-arena allocations are reclaimed at GUI shutdown; heap-backed document allocations are released by `Scene_Doc_Destroy`.

## Finding widgets

A node's path is its name prefixed by the names of its ancestors:

```text
[node name="Root" type="Panel"]
    [node name="Box" type="VBox" parent="Root"]
        [node name="Ok" type="Button" parent="Box"]
```

The button's path is `Root/Box/Ok`. Find it with:

```odin
Scene_Find :: proc(g: ^GUI, root: Widget_ID, path: string) -> Widget_ID
```

`Scene_Find` returns the matching widget or `INVALID_WIDGET_ID`. Duplicate child names can produce identical paths; the first match is returned. Parsed documents also store each node's path in `doc.nodes[i].path`.

A scene can be embedded directly in Odin as a string:

```odin
SCENE := `
[node name="Root" type="Panel"]
    bg = {0.07, 0.08, 0.10, 1}
    [node name="Title" type="Label" parent="Root"]
        text = "A scene"
`
```

## Saving scenes

`Scene_Save` serializes a widget tree; `Scene_Save_File` writes it to disk:

```odin
Scene_Save :: proc(g: ^GUI, root: Widget_ID, allocator: mem.Allocator = context.allocator) -> string
Scene_Save_File :: proc(g: ^GUI, root: Widget_ID, path: string) -> bool
```

`Scene_Save` returns text allocated with the supplied allocator. Release it with `delete(text, allocator)`. `Scene_Save_File` returns whether the write succeeded.

The writer preserves the properties supported by the scene format, with a few adjustments:

- Duplicate names are made unique in the file (`Ok`, `Ok2`, etc.); widget names in the GUI are unchanged.
- A custom class without its own constructor is saved using its base widget type.
- Widgets without constructors are omitted. Their children are written under their intended parent.
- Unnamed widgets receive generated names such as `Label1` and `Label2`.
- Anchors and offsets are always written. Border colour is saved as one colour for all four sides.
- `ColorRect` fill is always written, including transparent black.

Widget data not represented by the scene format is not saved. This includes list items, command-palette commands, table rows, chat lines and custom widget state.

## Limitations

The loader skips unknown properties and non-node sections. Nodes with missing constructors are skipped, with their children attached to the intended parent. Missing parents are attached to the GUI root. Unknown font families are reported as errors and fall back to the theme font. Invalid number lists are ignored.

Only `\n`, `\t`, `\r`, `\"` and `\\` are recognized string escapes; other escapes keep the following character and discard the backslash.
