# Extending CalcUI

Custom widgets are registered as classes. A class defines the widget's behavior, signals, default style, and optional scene-file constructor.

## Register a Class

```odin
class := GUI.Widget_Register_Class(g, GUI.Widget_Class_Desc{
    name = "Gauge",
    kind = GUI.Widget_Kind{
        construct = gauge_construct,
        destroy   = gauge_destroy,
        measure   = gauge_measure,
        draw      = gauge_draw,
        click     = gauge_click,
        pointer   = gauge_pointer,
        key       = gauge_key,
        text_input = gauge_text_input,
        style = GUI.Style{
            box = GUI.StyleBox{
                bg_color = GUI.RGBA(0.15, 0.16, 0.20, 1),
                content_margin = {6, 4, 6, 4},
                corner_radius = {4, 4, 4, 4},
            },
        },
    },
    signals = {"value_changed"},
})

id := GUI.Make_Custom_Widget(g, parent, class, GUI.Base_Opts{name = "gauge"})
```

`Widget_Class_Desc` supports:

| Field | Purpose |
|---|---|
| `name` | Class name used by themes and scene files. |
| `type` | Base widget type. Defaults to `.Panel`. |
| `kind` | Behavior hooks and default style. |
| `constructor` | Creates the widget when loading a scene. |
| `signals` | Additional signals emitted by the class. |

Registering an existing name updates the class. Omitted hooks are preserved.

## Widget Hooks

All hooks are optional. CalcUI uses its default behavior when a hook is not provided.

| Hook | Purpose |
|---|---|
| `construct` | Initialize the widget when added to the tree. |
| `destroy` | Release widget resources before user-data cleanup. |
| `measure` | Calculate minimum size. |
| `measure_width` | Measure content whose height depends on available width. |
| `content_size` | Report logical content size, useful for virtualized widgets. |
| `layout` | Position the widget's children. |
| `draw` | Draw custom widget content. |
| `update` | Update state before layout. |
| `post_update` | Process interaction after layout. |
| `click` | Handle a completed button press. |
| `pointer` | Handle pointer and wheel events. |
| `key` | Handle keyboard input while focused. |
| `text_input` | Handle text input while focused. |

`update` runs before layout, so changes are reflected in the current frame. `post_update` runs after layout and can access current geometry; layout changes take effect next frame.

Both run once per visible widget per frame and may destroy the widget.

Two flags modify hook behavior:

| Flag | Purpose |
|---|---|
| `owns_children` | The draw hook handles child drawing. |
| `uses_arrow_keys` | The widget handles arrow keys instead of focus navigation. |

### Widget Data

Allocate user data in `construct` and attach it with `Widget_Set_User_Data`:

```odin
gauge_construct :: proc(g: ^GUI, id: GUI.Widget_ID, w: ^GUI.Widget) {
    data := new(Gauge_Data)
    GUI.Widget_Set_User_Data(g, id, cast(rawptr)data, gauge_free)
}
```

CalcUI treats user data as opaque. Its cleanup procedure runs when the widget is destroyed, after the `destroy` hook.

### Measurement and Layout

`measure` adds the widget's sizing requirements without shrinking a larger requested or explicit minimum size:

```odin
gauge_measure :: proc(g: ^GUI, id: GUI.Widget_ID, w: ^GUI.Widget) -> GUI.Vec2 {
    size := GUI.Measure_Text(g, GUI.Widget_Style(g, id).text, "100%", 0)
    return GUI.Vec2{size.x + 24, size.y + 8}
}
```

Use `measure_width` when content height depends on available width. The hook receives the widget's outer width and provides a minimum measured size.

Use `content_size` when a widget manages its own items instead of creating a widget for each one. Scroll containers use this size to determine the logical content extent, making it useful for virtualized lists.

When `layout` is provided, the class positions its children. Otherwise, CalcUI uses their anchors.

### Drawing

The `draw` hook receives the content rectangle, excluding style margins. CalcUI draws the background and border beforehand.

```odin
gauge_draw :: proc(g: ^GUI, id: GUI.Widget_ID, w: ^GUI.Widget, content: GUI.Rect) {
    ink := GUI.Widget_Text_Colour(g, id)
    filled := content.w * clamp(gauge_value(g, id), 0, 1)
    GUI.Draw_Rect(g, GUI.Rect{x = content.x, y = content.y, w = filled, h = content.h}, ink, 2)
}
```

Children are drawn afterward unless `owns_children` is enabled. Custom drawing uses CalcUI's normal atlas, clipping, and batching pipeline.

Available drawing and measurement helpers:

| Procedure | Purpose |
|---|---|
| `Draw_Rect` / `Draw_Solid` | Draw rectangles. |
| `Draw_Text` | Draw styled text. |
| `Draw_Quad` / `Draw_Quad_Rounded` | Draw textured rectangles. |
| `Draw_Line` | Draw a line. |
| `Draw_Polygon` | Draw a polygon. |
| `Measure_Text` | Measure text. |
| `Widget_Measure_At_Width` | Measure a widget at a specified width. |

Geometry and style helpers:

| Procedure | Purpose |
|---|---|
| `Widget_Style` | Get resolved style. |
| `Widget_Background` | Get current background colour. |
| `Widget_Text_Colour` | Get current text colour. |
| `Widget_Rect` | Get window-space rectangle. |
| `Widget_Content_Rect` | Get content rectangle. |

## Input

### Pointer

Pointer events provide GUI, widget-local, and screen coordinates:

```odin
Pointer_Event :: struct {
    kind:   Pointer_Event_Kind, // .Down, .Up, .Move, .Wheel
    pos:    GUI.Vec2,
    local:  GUI.Vec2,
    global: GUI.Vec2,
    button: GUI.Mouse_Button,
    clicks: int,
    amount: f32,
}
```

Down and wheel events go to the widget under the pointer. A widget receiving a down event captures the pointer for subsequent move and up events, even outside its bounds.

Capture can also be controlled directly:

```odin
GUI.Widget_Capture_Pointer(g, id)
GUI.Widget_Release_Pointer(g)
```

Events propagate through widgets beneath the pointer. Call `GUI.Event_Handled(g)` to stop propagation.

`click` handles completed presses and runs when the pointer is released over the widget that received the press. CalcUI then emits its `pressed` signal.

### Keyboard

`key` and `text_input` run while the widget has focus. Set `focus_mode` to `.All` to enable keyboard focus and Tab navigation:

```odin
GUI.Make_Custom_Widget(g, parent, class, GUI.Base_Opts{focus_mode = .All})
```

Set `uses_arrow_keys` when the widget handles arrow keys itself.

## Signals and Invalidation

Widgets share built-in signals for presses, toggles, values, colours, text, selection, submission, focus, dragging, and resizing. Classes can declare additional signals:

```odin
// Declare the signal.
signals = {"value_changed"}

// Emit it.
GUI.Signal_Emit(g, id, "value_changed", value)

// Connect a handler.
GUI.Widget_Connect(g, id, "value_changed", gauge_on_value_changed)

gauge_on_value_changed :: proc(g: ^GUI, id: GUI.Widget_ID, value: any) {
    if v, ok := value.(f32); ok {
        // Use v.
    }
}
```

Signal payloads use `any`. After changing widget state, invalidate the affected work:

```odin
GUI.Widget_Invalidate(g, id, GUI.Dirty_Flags{.Measure, .Visual})
```

## Styling and Themes

Styles are resolved in this order, with later entries taking precedence:

1. Global default style.
2. Class style.
3. Theme style.
4. Widget-specific style.

Set a class's default style through `Widget_Kind.style`:

```odin
kind = GUI.Widget_Kind{
    style = GUI.Style{
        box = GUI.StyleBox{
            bg_color = GUI.RGBA(0.15, 0.16, 0.20, 1),
            content_margin = {6, 4, 6, 4},
            corner_radius = {4, 4, 4, 4},
        },
    },
}
```

Themes can override styles by class name:

```odin
theme := GUI.Theme_Make()
GUI.Theme_Set_Class(theme, "Gauge", GUI.Style{
    box = GUI.StyleBox{bg_color = GUI.RGBA(0.9, 0.2, 0.1, 1)},
})
GUI.GUI_Set_Theme(g, theme)
```

Theme lookup checks the class name before the base widget type. Widgets use themes when created with `use_theme = true`; scene-loaded widgets use them by default.

Additional theme helpers:

| Procedure | Purpose |
|---|---|
| `Theme_Set_Class` | Set class style. |
| `Theme_Set_Class_State` | Set class state style. |
| `Theme_Set_Class_Color` | Set a named colour. |
| `Theme_Set_Class_Constant` | Set a named constant. |

## Scene Files

Register a constructor to create custom widgets from scene files:

```odin
constructor = gauge_scene_constructor,

gauge_scene_constructor :: proc(
    g: ^GUI,
    parent: GUI.Widget_ID,
    name: string,
    text: string,
) -> GUI.Widget_ID {
    return GUI.Make_Custom_Widget(g, parent, gauge_class(g), GUI.Base_Opts{name = name})
}
```

Then reference the class by name:

```text
[node name="Root" type="Panel"]
    [node name="Gauge" type="Gauge" parent="Root"]
        anchors = {0, 0, 1, 0}
        offsets = {0, 0, 0, 40}
```

Register classes before loading scenes.

## Built-in Widgets

Built-in widgets use the same class system, although unconverted widgets continue using the core's switch-based behavior.

To migrate a built-in widget:

1. Move its behavior into class hooks.
2. Define and register its class beside its implementation.
3. Remove its cases from the central drawing, layout, and input switches.
4. Preserve existing behavior.

Migration is incremental; unconverted widgets continue working.
