# Extending CalcUI

Custom widgets are registered as classes. A class defines the widget's behavior, signals, default style and optional scene-file constructor.

## Register a class

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

`Widget_Class_Desc` contains:

| Field | Purpose |
|---|---|
| `name` | Class name used by themes and scene files. |
| `type` | Base widget type. Custom classes default to `.Panel`. |
| `kind` | Behavior hooks and default style. |
| `constructor` | Creates the widget when loading a scene. |
| `signals` | Additional signal names emitted by the class. |

Registering an existing name updates the class. Hooks you omit are kept.

## Hooks

All hooks are optional. When one is nil, CalcUI falls back to the normal control behavior where it applies.

| Hook | Called when |
|---|---|
| `construct` | The widget has been added to the tree. |
| `destroy` | The widget is being destroyed, before user-data cleanup. |
| `measure` | The core calculates the widget's minimum size. |
| `measure_width` | The core measures the widget at the width it is given. Use it when the height depends on the width. |
| `content_size` | A scroll container asks for the logical size of the widget's content. Use it for a widget that virtualizes its items. |
| `layout` | The widget lays out its children. |
| `draw` | The widget's content is drawn. |
| `update` | Each frame, before layout. State changes made here are measured and arranged in the same frame. |
| `post_update` | Each frame, after layout and before drawing. Use it for interaction that reads current geometry or the pointer. |
| `click` | A pressed button is released over the widget. |
| `pointer` | A pointer or wheel event is received. |
| `key` | A key is pressed while the widget has focus. |
| `text_input` | Text is entered while the widget has focus. |

`update` runs before layout, so a size or content change is measured and arranged in the same frame. `post_update` runs after layout, so it can read the current geometry; a change that affects layout is seen by the next frame. Both run once per visible widget per frame, and either may destroy the widget.

Two flags change hook behavior:

| Flag | Effect |
|---|---|
| `owns_children` | The draw hook draws the widget's children; CalcUI skips its own child draw pass. |
| `uses_arrow_keys` | Arrow keys are handled by the widget rather than focus navigation. |

### Data and lifetime

Allocate widget data in `construct` and attach it with `Widget_Set_User_Data`:

```odin
gauge_construct :: proc(g: ^GUI, id: GUI.Widget_ID, w: ^GUI.Widget) {
    data := new(Gauge_Data)
    GUI.Widget_Set_User_Data(g, id, cast(rawptr)data, gauge_free)
}
```

CalcUI treats user data as opaque. `Widget_Set_User_Data` returns the previous pointer and takes a cleanup procedure that runs when the widget is destroyed. `destroy` runs before that cleanup; use it to release other widget-owned resources.

### Measurement and layout

The core considers the requested size, the text content and the explicit minimum size. `measure` adds the class's sizing requirements and cannot shrink a larger size the program asked for:

```odin
gauge_measure :: proc(g: ^GUI, id: GUI.Widget_ID, w: ^GUI.Widget) -> GUI.Vec2 {
    size := GUI.Measure_Text(g, GUI.Widget_Style(g, id).text, "100%", 0)
    return GUI.Vec2{size.x + 24, size.y + 8}
}
```

Add `measure_width` when the height depends on the width. The core calls it with the widget's outer width and uses the result as a floor under the normal measurement. A wrapping label already does this, so a custom widget only needs the hook when it draws its own wrapping content.

Add `content_size` when the widget holds its items instead of one widget per item. A scroll container uses the larger of this size and the sizes of its children, so a virtualized list can report the room all its rows would take without creating them. Return a zero vector when the widget has no logical content size.

```odin
gauge_measure_width :: proc(g: ^GUI, id: GUI.Widget_ID, w: ^GUI.Widget, width: f32) -> GUI.Vec2 {
    size := GUI.Measure_Text(g, GUI.Widget_Style(g, id).text, "100%", max(width - 48, 0))
    return GUI.Vec2{0, size.y + 8}
}
```

When `layout` is set, the class positions its own children and CalcUI does not lay them out again. Without it, children use their anchors.

### Drawing

`draw` receives the content rectangle, without the style margins. CalcUI has already drawn the background and border:

```odin
gauge_draw :: proc(g: ^GUI, id: GUI.Widget_ID, w: ^GUI.Widget, content: GUI.Rect) {
    ink := GUI.Widget_Text_Colour(g, id)
    filled := content.w * clamp(gauge_value(g, id), 0, 1)
    GUI.Draw_Rect(g, GUI.Rect{x = content.x, y = content.y, w = filled, h = content.h}, ink, 2)
}
```

Children are drawn after the hook unless `owns_children` is set. Custom drawing goes through the normal atlas, clipping and batching path. It runs inside the widget's clip, so a rounded `clip_contents` widget also cuts glyphs, images and polygons at the corners.

Drawing and measurement helpers:

| Procedure | Purpose |
|---|---|
| `Draw_Rect` | Draw a rounded rectangle. |
| `Draw_Solid` | Draw a solid rectangle. |
| `Draw_Text` | Draw styled text. |
| `Draw_Quad` | Draw part of a texture. |
| `Draw_Quad_Rounded` | Draw part of a texture with per-corner radii. |
| `Draw_Line` | Draw a line between two points. |
| `Draw_Polygon` | Draw a polygon. |
| `Measure_Text` | Measure text as it would be drawn. |
| `Widget_Measure_At_Width` | Measure a widget at a given width, for content whose height depends on its width. |

Geometry and style helpers:

| Procedure | Returns |
|---|---|
| `Widget_Style` | Resolved widget style. |
| `Widget_Background` | Background colour for the current state. |
| `Widget_Text_Colour` | Text colour for the current state. |
| `Widget_Rect` | Widget rectangle in the window. |
| `Widget_Content_Rect` | Content rectangle. |

## Input

### Pointer events

The pointer hook receives coordinates in GUI, widget-local and screen space:

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

Down and wheel events go to the widget under the pointer. A widget that gets a down event captures the pointer for the matching move and up events, even outside its bounds. Capture is also available directly:

```odin
GUI.Widget_Capture_Pointer(g, id)
GUI.Widget_Release_Pointer(g)
```

Events propagate from the topmost widget through the widgets beneath it. Call `GUI.Event_Handled(g)` to stop propagation.

`click` is the older completed-press callback. It runs when the button is released over the widget that received the press; CalcUI then emits its `pressed` signal.

### Keyboard events

`key` and `text_input` run while the widget has focus. A click assigns focus according to `focus_mode`; `.All` also enables Tab navigation:

```odin
GUI.Make_Custom_Widget(g, parent, class, GUI.Base_Opts{focus_mode = .All})
```

Set `uses_arrow_keys` if the widget handles the arrow keys itself.

## Signals and invalidation

All widgets share signals for presses, toggles, value, colour and text changes, selection, submission, focus, dragging and resizing. A class can add its own:

```odin
// Declare the signal on the class.
signals = {"value_changed"}

// Emit it from the widget.
GUI.Signal_Emit(g, id, "value_changed", value)

// Connect a handler.
GUI.Widget_Connect(g, id, "value_changed", gauge_on_value_changed)

gauge_on_value_changed :: proc(g: ^GUI, id: GUI.Widget_ID, value: any) {
    if v, ok := value.(f32); ok {
        // Use v.
    }
}
```

Signal payloads are `any`; the handler interprets the value. Emitting a signal with no listeners only does the listener lookup.

After changing widget state, invalidate the affected work:

```odin
GUI.Widget_Invalidate(g, id, GUI.Dirty_Flags{.Measure, .Visual})
```

## Styling and themes

Styles apply in this order, with later entries taking precedence:

1. Global default style (`GUI_Set_Default_Style`).
2. Class style (`Widget_Kind.style`).
3. Theme style, if the widget uses the theme.
4. Widget-specific style.

Set a class's default style in `Widget_Kind`:

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

Themes can override the class by name:

```odin
theme := GUI.Theme_Make()
GUI.Theme_Set_Class(theme, "Gauge", GUI.Style{
    box = GUI.StyleBox{bg_color = GUI.RGBA(0.9, 0.2, 0.1, 1)},
})
GUI.GUI_Set_Theme(g, theme)
```

Theme lookup checks the class name first, then the base widget type. Widgets use the theme when created with `use_theme = true`; scene-loaded widgets use it by default.

Class themes also support state styles, named colours and constants:

| Procedure | Purpose |
|---|---|
| `Theme_Set_Class` | Set the class style. |
| `Theme_Set_Class_State` | Set a style for a class state. |
| `Theme_Set_Class_Color` | Set a named class colour. |
| `Theme_Set_Class_Constant` | Set a named class constant. |

## Scene files

Give a custom class a constructor to use it in a scene:

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

Then refer to the class by name:

```text
[node name="Root" type="Panel"]
    [node name="Gauge" type="Gauge" parent="Root"]
        anchors = {0, 0, 1, 0}
        offsets = {0, 0, 0, 40}
```

Register classes before loading the scene. `src/Tests/class_test.odin` has a working `Gauge` example that uses the public API.

## Built-in widgets

Built-in widgets use the same class system, with hooks kept next to each widget's implementation. Widgets that have not been converted still work through the core's switch-based behavior.

To migrate a built-in widget:

1. Move its drawing and behavior into class hooks.
2. Define the class beside the widget and register it with `kind_register`.
3. Remove its cases from the central draw, layout and input switches.
4. Keep its behavior unchanged.

Migration is incremental; unconverted widgets keep working.
