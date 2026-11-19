# Accessibility

CalcUI widgets are drawn, so they must also expose accessibility information to assistive technology. Each widget can describe its role, name, value, states, and relationships.

The core stores accessibility metadata and provides a platform-independent accessibility tree. Native integrations live in `src/GUI/Accessibility`; the core never calls platform accessibility APIs directly.

## Widget Metadata

Retrieve a widget's accessibility information with:

```odin
info := GUI.Widget_Access_Info(g, id)
```

`Access_Info` contains:

| Field | Description |
|---|---|
| `role` | Widget type. |
| `name` | Accessible name. |
| `description` | Additional descriptive text. |
| `value` | Current widget value. |
| `states` | Current accessibility states. |
| `relations` | References to related widgets. |

### Roles

CalcUI provides standard roles including `Button`, `Check_Box`, `Label`, `Text_Input`, `Slider`, `Progress_Bar`, `List`, `Tree`, `Table`, `Dialog`, `Window`, `Image`, `Link`, `Group`, `Panel`, and `Custom`.

Built-in widgets receive matching roles automatically. Custom classes can declare their role and provide additional metadata through an `access` hook:

```odin
class := GUI.Widget_Register_Class(g, GUI.Widget_Class_Desc{
    name = "Gauge",
    access_role = GUI.Custom,
    kind = GUI.Widget_Kind{
        access = gauge_access,
    },
})

gauge_access :: proc(
    g: ^GUI,
    id: GUI.Widget_ID,
    w: ^^GUI.Widget,
    info: ^GUI.Access_Info,
) {
    info.value = GUI.Access_Value{
        number = gauge_value(g, id),
        min = 0,
        max = 1,
    }
}
```

### Names and Values

A widget uses its text as its accessible name unless explicitly overridden.

```odin
GUI.Widget_Set_Access_Name(g, id, "Save the file")
GUI.Widget_Set_Access_Value(g, id, value)
```

Names can also be assigned through `Base_Opts`:

```odin
GUI.Make_Button(g, parent, GUI.Button_Opts{
    Base_Opts = GUI.Base_Opts{
        access_name = "Save the file",
    },
    text = "Save",
})
```

Widgets and custom classes can supply their current value through `Access_Info`.

### States

Available states include:

`Disabled`, `Hidden`, `Focused`, `Selected`, `Expanded`, `Checked`, `Pressed`, `Required`, `Read_Only`, `Multiline`, `Has_Popup`, `Editable`, `Busy`, and `Invalid`.

The core maintains states it can determine itself:

- `Disabled`
- `Hidden`
- `Focused`

Programs and custom widgets manage the remaining states:

```odin
GUI.Widget_Set_Access_State(g, id, state, on)
```

### Relations

Relations describe associations between widgets:

| Relation | Purpose |
|---|---|
| `Labelled_By` | Identifies the widget's label. |
| `Described_By` | Identifies its description. |
| `Controls` / `Controlled_By` | Describes control relationships. |
| `Flow_To` / `Flow_From` | Describes interaction order. |
| `Required_By` / `Required_For` | Describes required relationships. |
| `Details` / `Details_For` | Links additional information. |

Set or clear relations with:

```odin
GUI.Widget_Set_Access_Relation(g, id, kind, target)
GUI.Widget_Clear_Access_Relation(g, id, kind, target)
```

Each widget supports up to eight relations.

## Accessibility Tree

Collect the accessibility tree with:

```odin
nodes: [dynamic]GUI.Access_Node
GUI.Access_Collect(g, &nodes)
defer delete(nodes)
```

Each `Access_Node` contains the widget handle, metadata, parent handle, tree depth, and relations.

Hidden widgets and their descendants are excluded.

Floating panels have independent trees:

```odin
GUI.Access_Collect_Float(g, float_index, &nodes)
```

## Platform Integration

Platforms receive accessibility updates through a bridge registered with the GUI:

```odin
GUI.GUI_Set_Access_Bridge(g, GUI.Access_Bridge{
    ctx = platform,
    node_changed = platform_node_changed,
    focus_changed = platform_focus_changed,
})
```

The bridge supports five callbacks:

- `node_added`
- `node_changed`
- `node_removed`
- `focus_changed`
- `frame`

All callbacks are optional. The core batches metadata changes and reports them at the end of the frame. A bridge installed after widgets already exist receives the existing nodes as well.

The `frame` callback runs after layout, allowing the platform to refresh widget geometry and structure.

Synchronize updates manually with:

```odin
GUI.Access_Sync(g)
```

Without a bridge, applications can poll the accessibility epoch:

```odin
GUI.GUI_Access_Epoch(g)
```

The epoch increments whenever accessibility metadata changes.

## Native Accessibility

The `src/GUI/Accessibility` package connects CalcUI to the host platform's native accessibility system.

```odin
GUI.Access_Install(g, window_handle)
GUI.Access_Apply_Actions(g)
```

- `Access_Install` connects the GUI and exposes existing widgets.
- `Access_Apply_Actions` processes actions requested by assistive technology.

The shared application loop in `Core.App_Run` handles both when platform accessibility is available.

The application's accessibility setting controls integration:

- `Default`: Use platform accessibility when available.
- `On`: Request platform accessibility.
- `Off`: Keep accessibility data inside the application.

Retrieve a widget's tree information with:

```odin
node := GUI.Access_Node_Info(g, id)
```

### Windows

The Windows integration uses UI Automation, exposing one system object per widget. These objects provide widget roles, values, states, and supported interactions.

Core roles map to Windows control types:

| CalcUI roles | Windows control |
|---|---|
| `Button`, `Toggle_Button` | Button |
| `Check_Box` | CheckBox |
| `Text_Input`, `Password_Input`, `Search_Input`, `Number_Input` | Edit |
| `Slider` | Slider |
| `Spin_Box` | Spinner |
| `Progress_Bar` | ProgressBar |
| `Combo_Box` | ComboBox |
| `List`, `List_Item` | List, ListItem |
| `Tree`, `Tree_Item` | Tree, TreeItem |
| `Menu`, `Menu_Bar`, `Menu_Item` | Menu, MenuBar, MenuItem |
| `Tab`, `Tab_List` | TabItem, Tab |
| `Dialog`, `Window` | Window |
| `Tooltip` | ToolTip |
| `Image` | Image |
| `Link` | Hyperlink |
| `Separator` | Separator |
| `Scroll_Bar` | ScrollBar |
| `Label`, `Heading`, `Status` | Text |
| `Group` | Group |
| `Panel` | Pane |
| `Table` | Table |
| `Canvas`, `Chart`, `Custom` | Custom |

The bridge raises native accessibility events when widget metadata changes, including name, value, selection, toggle, and focus changes.

Supported interaction patterns include:

- **Value:** Read or update text fields.
- **Toggle:** Change check boxes and switches.
- **Invoke:** Activate buttons, links, and menu items.
- **Range value:** Read or change sliders and numeric fields.

Platforms without native accessibility can still collect and expose the same platform-independent accessibility tree.

## Design Rules

- **Platform separation:** Core accessibility metadata contains no native platform dependencies.
- **Consistent metadata:** Widgets expose the same roles, names, values, states, and relations across platforms.
- **Core-owned states:** The core maintains `Disabled`, `Hidden`, and `Focused`.
- **Visibility:** Hidden widgets and their descendants are excluded.
- **Batched updates:** Accessibility changes are reported once per frame.
- **Deferred actions:** Platform requests are applied on the application thread, where widgets can safely be accessed.
- **Independent lifetime:** Native objects copy the metadata they need rather than retaining pointers into widget storage.
- **Graceful fallback:** Platforms without native accessibility can still use the accessibility tree.
