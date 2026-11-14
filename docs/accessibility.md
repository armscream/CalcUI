# Accessibility

CalcUI widgets are drawn, but a GUI must also describe itself to people who cannot see the screen. Accessibility metadata tells assistive technologies what a widget is, what it is called, what value it holds, which states it is in, and how it relates to other widgets.

The metadata lives in the core toolkit (`src/GUI/accessibility.odin`). The core stores and exposes it without depending on a platform. Platform-specific accessibility bridges live outside `src/GUI`, keeping the toolkit portable and platform integration in one place.

## Widget Metadata

Retrieve a widget's accessibility information with:

```odin
info := GUI.Widget_Access_Info(g, id)
```

`Access_Info` contains:

| Field | Description |
|---|---|
| `role` | What kind of widget it is. |
| `name` | The widget's accessible name. |
| `description` | Additional text describing the widget. |
| `value` | The value the widget holds. |
| `states` | The widget's current accessibility states. |
| `relations` | References to related widgets. |

### Role

`Access_Role` describes the widget type using roles recognized by assistive technologies.

Built-in roles include:

`Button`, `Toggle_Button`, `Check_Box`, `Label`, `Heading`, `Text_Input`, `Password_Input`, `Search_Input`, `Number_Input`, `Slider`, `Spin_Box`, `Progress_Bar`, `Combo_Box`, `List`, `List_Item`, `Tree`, `Tree_Item`, `Table`, `Menu`, `Menu_Bar`, `Menu_Item`, `Tab`, `Tab_List`, `Dialog`, `Window`, `Tooltip`, `Status`, `Image`, `Link`, `Separator`, `Scroll_Bar`, `Canvas`, `Chart`, `Group`, `Panel` and `Custom`.

Built-in widgets use their corresponding roles: a button is a `Button`, a text field is a `Text_Input`, and a toast is a `Status`.

Custom widget classes can declare their own role:

```odin
class := GUI.Widget_Register_Class(g, GUI.Widget_Class_Desc{
    name = "Gauge",
    access_role = GUI.Custom,
    kind = GUI.Widget_Kind{
        draw = gauge_draw,
        measure = gauge_measure,
    },
})
```

A class can also provide accessibility metadata through its `access` hook:

```odin
kind = GUI.Widget_Kind{
    access = gauge_access,
}

// The hook receives the widget's metadata and may update it.
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

### Name

A widget's accessible name comes from its text when available, or from an explicitly assigned name.

Set the name directly:

```odin
GUI.Widget_Set_Access_Name(g, id, "Save the file")
```

Or provide it when creating the widget:

```odin
GUI.Make_Button(g, parent, GUI.Button_Opts{
    Base_Opts = GUI.Base_Opts{
        access_name = "Save the file",
    },
    text = "Save",
})
```

An explicit name lets a program provide meaningful accessibility text when the visible content alone is insufficient.

### Value

The value describes what the widget currently holds: text in a text field, a slider's number, or a progress bar's current progress.

Set it with:

```odin
GUI.Widget_Set_Access_Value(g, id, value)
```

Widgets and custom classes can provide their current values through the accessibility metadata.

### States

Accessibility states describe conditions that apply to a widget.

CalcUI supports:

`Disabled`, `Hidden`, `Focused`, `Selected`, `Expanded`, `Checked`, `Pressed`, `Required`, `Read_Only`, `Multiline`, `Has_Popup`, `Editable`, `Busy` and `Invalid`.

The core maintains states it can determine directly:

- `Disabled` reflects whether the widget is enabled.
- `Hidden` reflects whether the widget is shown.
- `Focused` reflects keyboard focus.

Programs and custom widgets can set additional states:

```odin
GUI.Widget_Set_Access_State(g, id, state, on)
```

The core-owned states remain authoritative. Custom state updates should describe conditions that the core cannot determine itself.

### Relations

Relations connect widgets and describe how they are associated.

| Relation | Description |
|---|---|
| `Labelled_By` | The widget that labels this widget. |
| `Described_By` | The widget that describes this widget. |
| `Controls` | The widget controlled by this widget. |
| `Controlled_By` | The widget that controls this widget. |
| `Flow_To` | The widget that follows this widget in the interaction flow. |
| `Flow_From` | The widget that precedes this widget in the interaction flow. |
| `Required_By` | The widget that requires this widget. |
| `Required_For` | The widget this widget is required for. |
| `Details` | The widget containing additional details for this widget. |
| `Details_For` | The widget whose details this widget provides. |

Set and clear relations with:

```odin
GUI.Widget_Set_Access_Relation(g, id, kind, target)

GUI.Widget_Clear_Access_Relation(g, id, kind, target)
```

Each widget can hold up to eight relations. The active relations occupy the first `relation_count` entries of `relations`.

## Accessibility Tree

Collect accessibility metadata for the widget tree with:

```odin
nodes: [dynamic]GUI.Access_Node
GUI.Access_Collect(g, &nodes)
defer delete(nodes)
```

Each `Access_Node` contains:

- The widget handle.
- Its role, name, description, value and states.
- Its parent handle.
- Its depth in the tree.
- Its accessibility relations.

Widgets that are not shown are excluded from the tree, along with their descendants.

Floating panels have independent accessibility trees:

```odin
GUI.Access_Collect_Float(g, float_index, &nodes)
```

This allows platform integrations to expose each floating panel separately from the main GUI tree.

## Platform Integration

Platform accessibility is implemented through a bridge registered with the GUI:

```odin
GUI.GUI_Set_Access_Bridge(g, GUI.Access_Bridge{
    ctx = platform,
    node_changed = platform_node_changed,
    focus_changed = platform_focus_changed,
})
```

The bridge provides four hooks:

- `node_added`
- `node_changed`
- `node_removed`
- `focus_changed`

The platform supplies the callbacks it needs. A platform without accessibility support can leave them nil.

The core reports metadata changes through the bridge. Platform code is responsible for translating those updates into the native accessibility system.

A platform without a bridge can instead monitor:

```odin
GUI.GUI_Access_Epoch(g)
```

The epoch increments when accessibility metadata changes. A platform can compare the epoch against its last observed value and rebuild its accessibility tree when necessary.

## Design Rules

1. **Platform independence:** The core stores accessibility metadata. Platform integrations handle native accessibility APIs. Nothing in `src/GUI` communicates directly with a platform accessibility system.
2. **Built-in roles:** Built-in widgets use their corresponding accessibility roles unless the program explicitly overrides them.
3. **Accessible names:** A widget uses its text or an explicitly assigned name.
4. **Values:** Accessibility values describe what the widget currently holds.
5. **Core-owned states:** States the core can determine are maintained by the core.
6. **Relations:** Programs and widget classes define the relationships between widgets.
7. **Visibility:** Hidden widgets and their descendants are excluded from the accessibility tree.
8. **Lifecycle:** Accessibility metadata belongs to its widget and is removed when that widget is destroyed.