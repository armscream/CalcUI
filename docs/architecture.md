# CalcUI Architecture

An overview of CalcUI's internal architecture: its packages, widget tree, frame lifecycle, rendering pipeline, layout engine, input system, extensibility, memory ownership, and tests.

## 1. Architecture Overview

CalcUI is a retained-mode GUI toolkit written in Odin. Its core maintains a persistent widget tree, performs incremental layout, routes input, manages text and resources, and builds draw lists for rendering.

The architecture separates GUI logic from platform integration:

- **GUI Core** — Widget management, layout, input routing, text, themes, atlas management, scene loading, and draw-list construction.
- **Rendering Backends** — Translate the core's draw lists into rendering operations.
- **Window Layer** — Manages windows, platform events, coordinate conversion, cursors, clipboard access, and floating panels.
- **Runa** — Provides text shaping, line breaking, and glyph rasterization.

The core does not depend directly on SDL. Instead, it communicates with a rendering backend through a function-pointer interface and receives platform events through CalcUI's own event types.

## 2. Package Structure

| Directory | Responsibility |
|---|---|
| `src/GUI` | GUI core: widget tree, layout, input, drawing, text, atlas, themes, and scene loading. |
| `src/Backend` | Rendering implementations: SDL3 Renderer and SDL3 GPU. |
| `src/Window` | SDL3 windows, event translation, coordinate conversion, floating windows, cursor, and clipboard integration. |
| `src/GUI/dependencies/Runa` | Text engine: shaping, line breaking, and rasterization. |
| `examples` | Standalone example applications. |
| `assets` | Fonts and other example resources. |
| `tools` | Shaders and development utilities. |

The examples share application and window setup through `examples/common`.

### 2.1 Rendering Backend Interface

The GUI core communicates with a backend through `Backend`, defined in `src/GUI/types.odin`.

```odin
Backend :: struct {
    ctx:                    rawptr,
    create:                 proc(ctx, window: rawptr, w, h: i32) -> bool,
    destroy:                proc(ctx: rawptr),
    resize:                 proc(ctx: rawptr, w, h: i32) -> bool,
    upload_texture:         proc(ctx: rawptr, id: Texture_ID, pixels: []u8, w, h: i32) -> bool,
    upload_texture_regions: proc(ctx: rawptr, id: Texture_ID, regions: []Texture_Upload) -> bool,
    destroy_texture:        proc(ctx: rawptr, id: Texture_ID),
    submit:                 proc(ctx: rawptr, dl: ^Draw_List),
    submit_target:           proc(ctx: rawptr, dl: ^Draw_List, window: rawptr),
    supports_shapes:        bool,
}
```

The interface provides:

- Backend initialization, shutdown, and resizing.
- Texture creation, updates, and destruction.
- Draw-list submission.
- Optional support for shader-based shape rendering.

The window handle is an opaque `rawptr`, preventing SDL-specific types from leaking into the GUI core.

`supports_shapes` indicates whether the backend can render shape effects, such as rounded corners, through its shader. Backends without this capability use CPU-generated geometry instead.

The complete backend requirements are documented in [`docs/contracts.md`](contracts.md).

### 2.2 Platform Integration and Coordinate Spaces

`src/Window` is responsible for translating SDL events into `GUI.Event` values.

The GUI core never processes SDL events directly. Events are placed into `g.events` and consumed by `GUI.Handle_Events`.

The Window layer works with logical window dimensions and input coordinates. The GUI core converts these dimensions and positions into its physical pixel-space geometry using `GUI.scale`.

This separates application-facing layout dimensions from the pixel dimensions required for rendering.

On a resize event:

1. The Window layer obtains the updated logical window dimensions.
2. The GUI updates its logical dimensions and recalculates its pixel-space viewport using the current scale.
3. Layout and drawing are invalidated as required.
4. The next frame rebuilds the affected geometry using the updated dimensions and screen ratios.

This allows the interface to maintain the correct proportions when window dimensions or display scaling change.

An alternative platform integration can provide its own window management and translate input into CalcUI's event types, provided it follows the same coordinate-space contract.

## 3. Widget Tree and Identity

CalcUI uses a retained-mode widget tree. Widgets persist between frames and maintain their own identity and state.

### 3.1 Widget Handles

Each widget is identified by a `Widget_ID`:

```odin
Widget_ID :: struct {
    index:      u32,
    generation: u32,
}
```

The index identifies a slot in `g.widgets`. The generation identifies the particular widget occupying that slot.

When a widget is destroyed, its slot can be reused, but its generation changes. This prevents stale handles from accidentally referring to newly created widgets.

`Widget_Get` validates the handle and returns the corresponding widget pointer, or `nil` if the handle is invalid. `Widget_Alive` provides a convenient validity check.

Widgets are allocated from the GUI's arena. A returned widget pointer therefore remains valid while its allocation remains alive; widget handles should be preferred for references that must survive structural changes.

### 3.2 Widget Creation

`New_Widget` is the generic creation function:

```odin
New_Widget :: proc(
    g: ^GUI,
    type: Widget_Type,
    parent: Widget_ID,
    opts: Widget_Opts = {},
) -> Widget_ID
```

The `Make_<Name>` functions provide convenient constructors for built-in widgets. The generic function also allows widgets to be created by type when a dedicated constructor is unavailable.

### 3.3 Child Relationships

Widgets store their parent-child relationships using an intrusive sibling list:

```odin
first_child:  Widget_ID,
last_child:   Widget_ID,
prev_sibling: Widget_ID,
next_sibling: Widget_ID,
```

`Widget_Attach` and `Widget_Detach`, implemented in `src/GUI/widget.odin`, update these relationships without rebuilding a separate child array. Their link operations are O(1).

`Widget_Insert_At` supports insertion at a specific position.

Detaching a widget does not destroy it or change its identity. This makes detachment a useful primitive for operations such as docking and reparenting.

### 3.4 Docking and Runtime Reparenting

The widget tree can be rearranged at runtime.

The docking system separates planning from application:

- `dock_plan` determines where a dragged panel would be placed.
- `dock_apply` performs the resulting tree changes.

The preview and final operation use the same plan, keeping the visual docking preview consistent with the actual result.

### 3.5 Widget Destruction

`Widget_Free` destroys a widget and its descendants:

```odin
Widget_Free :: proc(g: ^GUI, id: Widget_ID) -> bool
```

Destruction is responsible for maintaining the integrity of the tree and releasing resources owned by the affected widgets.

This includes:

- Removing the widget and its descendants from the tree.
- Clearing references held by focus, pointer capture, hover, drag-and-drop, resizing, floating panels, and tooltips.
- Updating affected focus neighbours and other widget references.
- Releasing widget-owned dynamic data.
- Returning widget slots to the free list for reuse.

The root widget cannot be destroyed.

A destroyed widget's old handle remains invalid even if its slot is reused. Its generation prevents the old handle from identifying the new widget.

### 3.6 Floating Panels

A panel detached from the main window is represented as a floating panel in `g.floats`.

Each floating panel has its own draw list and platform window. The GUI core manages the panel's widget content, while `src/Window` creates and manages its SDL window.

The main window and floating panels are therefore rendered as separate targets.

**Lifecycle status:** Floating-panel ownership and cleanup are not yet fully resolved. Detaching a panel, destroying its widget tree, and closing its platform window must have a consistent lifecycle so that neither GUI resources nor platform windows are left behind. This remains an area requiring implementation work.

## 4. Frame Lifecycle

`Frame`, implemented in `src/GUI/gui.odin`, performs the core's per-frame work.

```odin
Frame :: proc(g: ^GUI) {
    virt.arena_free_all(&g.frame_arena)
    g.dt = frame_time(g)
    layout_pass(g)
    update_resize_hover(g)
    build_draw_list(g)
    atlas_flush(g.atlas, g.backend, g.atlas_texture)
    atlas_next_frame(g.atlas)
}
```

The frame proceeds through the following stages:

1. **Reset frame memory** — Reclaim temporary allocations from the previous frame.
2. **Update frame time** — Calculate `g.dt`, the elapsed time used by time-dependent widgets.
3. **Run layout** — Measure and arrange widgets whose layout state has been invalidated.
4. **Update resize hover** — Determine resize interactions using the current widget geometry.
5. **Build draw lists** — Generate the main window's draw list and separate lists for floating panels.
6. **Flush the atlas** — Upload modified texture regions to the backend and advance atlas frame bookkeeping.

The frame function builds rendering data but does not itself present it.

The application loop handles events, runs the frame, synchronizes platform state, and submits the resulting draw lists.

The shared example loop is in `examples/common/bootstrap.odin`:

```odin
GUI.Handle_Events(app.gui)
GUI.Frame(app.gui)

plat.Sync_Popups(&app.window, app.gui.floats[:])
plat.Set_Cursor(&app.window, app.gui.cursor)
plat.Sync_Clipboard(app.gui)

app.backend.submit(app.backend.ctx, &app.gui.draw)

for i in 0 ..< len(app.gui.floats) {
    if i >= len(app.window.popups) {
        break
    }

    app.backend.submit_target(
        app.backend.ctx,
        &app.gui.floats[i].draw,
        cast(rawptr)app.window.popups[i],
    )
}
```

This keeps application-level event processing and presentation separate from the GUI core's frame construction.

## 5. Rendering Architecture

CalcUI uses a shared texture atlas and a batched draw-list representation.

The GUI core builds geometry and rendering commands without issuing backend-specific drawing operations. The backend consumes the resulting `Draw_List`.

### 5.1 Texture Atlas

The GUI uses a shared `UI_Atlas`, stored in `g.atlas`.

The default atlas is `ATLAS_DEFAULT_SIZE` (2048 × 2048), using RGBA pixels. At four bytes per pixel, this occupies 16 MiB. Applications can request a different size through `Init_GUI_With_Atlas`.

The atlas contains:

- A white texel used by solid-colour primitives.
- Rasterized glyphs from loaded fonts.
- Images and other textures managed through the atlas.

The atlas maintains its own CPU-side pixel data. Updates modify this copy and mark the affected regions dirty.

On its first flush, the atlas uploads the complete texture. Subsequent flushes upload only modified regions, grouped into a backend upload operation.

```odin
atlas_flush :: proc(
    a: ^UI_Atlas,
    backend: Backend,
    texture: Texture_ID,
)
```

### 5.2 Atlas Allocation and Eviction

Atlas regions are allocated using a shelf allocator.

New allocations are placed into available shelf space. The allocator can create additional shelves as space is consumed.

Glyphs are pinned so that their atlas entries remain available once allocated. Images are evictable and can be reclaimed when space is needed.

Atlas regions use generation-based handles. When a region is released and its slot reused, the generation changes. Stale handles therefore cannot identify newly allocated regions.

The atlas reserves a 4 × 4 white region near the top-left corner. Solid quads sample its centre through `g.atlas.white_uv`, avoiding filtering into neighbouring texels.

### 5.3 Draw List

The draw list is the rendering contract between the GUI core and its backend. It is defined in `src/GUI/draw.odin`.

```odin
Draw_List :: struct {
    vertices:     [dynamic]Draw_Vertex,
    indices:      [dynamic]u32,
    commands:     [dynamic]Draw_Command,
    clip_stack:   [dynamic]Rect,
    base_clip:    Rect,
    current_clip: Rect,
}
```

It contains shared vertex and index buffers, an ordered command list, and clipping state.

A vertex contains:

```odin
Draw_Vertex :: struct {
    pos:    [2]f32,
    uv:     [2]f32,
    colour: Colour,
    shape:  [4]f32,
    local:  [2]f32,
}
```

The vertex stores its position, texture coordinates, colour, shape parameters, and local quad coordinates.

A draw command describes a range of indices and the texture used to render them:

```odin
Draw_Command :: struct {
    texture:    Texture_ID,
    idx_count:  u32,
    idx_offset: u32,
}
```

This representation allows the core to batch compatible geometry before it reaches the backend.

### 5.4 CPU Clipping

Clipping is performed while geometry is added to the draw list.

A widget that clips its children pushes a clip with `draw_push_clip` and restores the previous state with `draw_pop_clip`.

Each pushed rectangle is intersected with the active clip. Nested clipping therefore produces the intersection of all active clip rectangles.

Quads are clipped against the active rectangle when they are added. Their texture coordinates are adjusted to preserve the original texture mapping.

Completely clipped quads are discarded, producing no vertices or indices.

Polygons are clipped against the four sides of the active rectangle. Since the clip region is rectangular and convex, clipping a convex polygon this way preserves the visible polygon region.

### 5.5 Drawing Primitives

The core provides three primary drawing operations:

| Operation | Purpose |
|---|---|
| `draw_quad` | Draws a textured quad, used for images and glyphs. |
| `draw_rect` | Draws a solid-colour rectangle, including supported rounded shapes. |
| `draw_text` | Shapes and lays out text through Runa, then emits glyph quads from the atlas. |

`draw_rect` uses the backend's shape capability when available.

A shader-capable backend renders rounded corners using fragment-shader shape parameters. Otherwise, the core generates polygon geometry on the CPU.

Both paths use the same draw-list interface.

### 5.6 Command Batching

`draw_command` merges adjacent commands when they use the same texture, unless an explicit command break is requested.

Built-in widgets generate their visual geometry programmatically. They do not introduce independent textures into the draw list; their primitives, glyphs, and atlas-managed image content use the shared atlas.

As a result, normal built-in GUI content can be batched into a single command per rendering target. This is the intended rendering path: one shared atlas, one ordered geometry stream, and minimal command overhead.

Floating panels have independent draw lists and are submitted separately, so each window has its own batching scope.

The test `test_a_whole_scene_is_one_command` in `src/GUI/draw_call_test.odin` verifies the single-command case for its test scene.

## 6. Layout Engine

The layout engine is implemented in `src/GUI/layout.odin`.

It uses two main stages:

1. **Measurement** — Determine the minimum size required by each widget.
2. **Arrangement** — Assign final rectangles to widgets and lay out their descendants.

The engine is incremental: changes invalidate specific layout state, allowing unaffected branches to retain their cached results.

### 6.1 Invalidation

Invalidation flags are defined in `src/GUI/invalidation.odin`.

| Flag | Meaning |
|---|---|
| `Measure` | The widget's measured size is stale. |
| `Arrange` | The widget's assigned geometry is stale. |
| `Visual` | The widget's rendered appearance is stale. |
| `Hit` | The widget's hit-test geometry or state is stale. |
| `Theme` | The widget's theme-derived styling is stale. |

Invalidation propagates where dependencies require it. For example, changing a measured size also invalidates arrangement and hit testing. Changing arrangement invalidates hit testing.

Each widget tracks its own invalidation state and aggregated state for its descendants. The layout passes use the aggregated flags to skip unaffected branches.

Setters in `src/GUI/setter.odin` provide the preferred way to modify widget properties:

```odin
GUI.Widget_Set_Text(g, label, "Updated text")
GUI.Widget_Set_Visible(g, panel, false)
GUI.Widget_Set_Style(g, button, style)
GUI.Widget_Set_Offsets(g, bar, offsets)
```

These setters apply the appropriate invalidation.

Widget fields are accessible directly, so callers that modify fields themselves must ensure that the corresponding state is invalidated. `GUI_Invalidate_All` provides a full-tree fallback when the affected dependencies are not known.

`GUI_Invalidate_Theme` invalidates theme-derived styling.

### 6.2 Measurement

`measure_pass` determines the minimum size of each widget.

The measured size accounts for:

- The widget's base minimum size.
- Text dimensions.
- Style padding.
- The program-specified custom minimum size.
- Widget-specific measurement behaviour.

Text dimensions are based on the same text layout used for drawing. Transformed text therefore reserves space for its transformed dimensions.

Wrapped text accounts for its available width and word boundaries.

Widgets that contain collections may derive their size from their contents. For example, a combo box or tree can account for the width of its entries, while scrollable content can extend beyond the visible viewport.

Text measurements are cached in `g.measure_cache`. Cached results are reused until their relevant inputs change. Measurement is therefore driven by invalidation rather than repeatedly shaping and measuring every widget every frame.

### 6.3 Arrangement

`layout_node` assigns a widget its final rectangle and calculates its clipping rectangle.

A widget's clip is the intersection of its own bounds and the clip inherited from its parent.

Container widgets arrange their children according to their layout rules. Other widgets use their anchor and offset configuration.

If a widget's geometry, clipping, and descendants remain valid, the layout engine can skip the corresponding work.

### 6.4 Anchors and Offsets

Widgets can position themselves relative to their parent using four anchors and four offsets.

```odin
Anchor :: struct {
    left, top, right, bottom: f32
}

Offset :: struct {
    left, top, right, bottom: f32
}
```

Anchors are normalized fractions of the parent bounds, while offsets are expressed in UI units.

`resolve_rect` combines them to calculate the widget's final rectangle.

CalcUI provides predefined anchor presets:

```odin
Anchor_Preset :: enum {
    Fill,
    Top_Left,
    Top_Right,
    Bottom_Left,
    Bottom_Right,
    Center,
    Left,
    Right,
    Top,
    Bottom,
    Custom,
}
```

`Fill` is the default preset. Raw anchor values are used when `.Custom` is selected.

Widgets that grow beyond their minimum size follow the configured grow direction, which defaults to right and down.

### 6.5 Containers

Container widgets determine how their children use available space.

| Container | Behaviour |
|---|---|
| `VBox` | Arranges children vertically. |
| `HBox` | Arranges children horizontally. |
| `Split` | Divides available space among resizable sections. |
| `Tabs` / `TabContainer` | Displays one child at a time with a tab strip. |
| `GridContainer` | Arranges children in rows and columns. |
| `MarginContainer` | Adds space around child content. |
| `CenterContainer` | Centres its child at the child's requested size. |
| `PanelContainer` | Places its child within the available content area. |
| `ScrollContainer` / `ScrollArea` | Displays a viewport over larger content. |
| `FlowContainer` | Arranges children sequentially, wrapping when necessary. |
| `AspectRatioContainer` | Maintains an aspect-ratio constraint. |

Nested containers can be combined to construct complex layouts.

Box containers allocate each child's minimum size first, then distribute remaining space according to child weights. The separation between children is controlled by `w.separation`, which defaults to 4.

### 6.6 Sizing and Space Allocation

Widgets expose several properties that control their sizing behaviour.

| Property | Field | Behaviour |
|---|---|---|
| Measured minimum | `w.min_size` | Minimum size determined by measurement. |
| Custom minimum | `w.custom_min_size` | Additional minimum size requested by the program. |
| Custom maximum | `w.custom_max_size` | Upper size constraint. |
| Fixed sizing | `opts.fixed` | Keeps the widget at its minimum size rather than sharing surplus space. |
| Stretch weight | `w.weight` | Determines the widget's share of available surplus space. |
| Manual sizing | `w.manual_size`, `w.manual_w`, `w.manual_h` | Stores manually adjusted panel dimensions. |

A weight of zero means the widget receives no share of surplus space.

Manual panel sizes are preserved during layout and deducted from the space available to other children.

Inactive tab pages do not retain visible geometry and are neither drawn nor hit-tested.

## 7. Input and Interaction

Input events are defined in `src/GUI/events.odin`.

`GUI.Event` represents platform-independent input, including:

- Mouse movement and button events.
- Mouse wheel input.
- Keyboard input.
- Text input and IME composition.
- Window resize and quit events.

Mouse events contain both window-relative and screen-relative positions:

- `pos` — Position relative to the originating window.
- `global` — Position relative to the screen.

The distinction is important for floating panels, which may be outside the main window.

The Window layer translates platform input into CalcUI's event representation. Events are placed in `g.events` and processed by `GUI.Handle_Events`.

The event queue is detached before processing. Events added by callbacks during dispatch are therefore handled in the next event-processing pass.

### 7.1 Hit Testing and Event Routing

`collect_hits` gathers widgets under a pointer position, ordered from topmost to bottommost.

Children are considered above their parents, and sibling ordering accounts for `z_index`.

Widgets control pointer participation through `Mouse_Filter`:

```odin
Mouse_Filter :: enum {
    Stop,
    Pass,
    Ignore,
}
```

| Filter | Behaviour |
|---|---|
| `Stop` | Receives the event and prevents widgets behind it from receiving it. |
| `Pass` | Receives the event while allowing propagation to widgets behind it. |
| `Ignore` | Does not participate in pointer interaction. |

`hit_test` returns the topmost eligible widget.

`hits_that_take_the_mouse` builds the complete eligible hit list. Event dispatch proceeds through that list until a widget stops propagation or marks the event handled.

Disabled widgets do not receive pointer interaction, allowing eligible widgets behind them to be considered.

### 7.2 Focus

Widgets can receive keyboard focus when their `focus_mode` permits it and they are visible and enabled.

`focus_set` transfers focus between widgets and emits the appropriate focus signals.

Focus is cleared when a widget becomes hidden, disabled, destroyed, or detached from the tree.

CalcUI supports:

- **Tab navigation** — Widgets are ordered by `tab_index`, with tree order breaking ties. Only widgets using `.All` participate.
- **Directional navigation** — Explicit `focus_neighbour` relationships take precedence; otherwise, spatial position determines the next candidate.

The detailed focus and event rules are documented in [`docs/events-focus.md`](events-focus.md).

### 7.3 Signals

Signals are implemented in `src/GUI/signal.odin`.

Widgets share a common signal interface, allowing applications to connect to widget events without depending on the widget's concrete type.

Unconnected signals are `nil`, so emitting an unconnected signal requires only a nil check.

The available signals are documented in [`docs/widgets.md`](widgets.md).

## 8. Widget Extensibility

CalcUI supports custom widget behaviour through its kind registry, implemented in `src/GUI/kinds.odin`.

Built-in widgets may use dedicated dispatch paths in the core. The kind registry provides an extension mechanism for registering widget-specific behaviour without adding more cases to shared rendering, layout, and input code.

### 8.1 Widget Kind

A `Widget_Kind` describes the callbacks and defaults associated with a widget type.

```odin
Widget_Kind :: struct {
    draw:       proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect),
    layout:     proc(g: ^GUI, id: Widget_ID, w: ^Widget, rect: Rect),
    click:      proc(g: ^GUI, id: Widget_ID, w: ^Widget),
    key:        proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Key_Down_Event),
    update:     proc(g: ^GUI, id: Widget_ID, w: ^Widget, dt: f32),
    style:      Style,
    theme_name: string,
}
```

The callbacks provide widget-specific drawing, layout, click, keyboard, and per-frame update behaviour. The style and theme name provide default presentation information.

A widget kind is registered through `kind_register`:

```odin
Make_Chart :: proc(
    g: ^GUI,
    parent: Widget_ID,
    opts: Chart_Opts,
) -> Widget_ID {
    kind_register(g, .Chart, chart_kind())
    // ...
}
```

Registration is idempotent: an existing entry is not overwritten by repeated registration.

### 8.2 Dispatch

The core consults the kind registry at the relevant dispatch points.

| Operation | Location | Callback |
|---|---|---|
| Drawing | `src/GUI/draw_build.odin` | `kind.draw` |
| Layout | `src/GUI/layout.odin` | `kind.layout` |
| Click handling | `src/GUI/input.odin` | `kind.click` |
| Keyboard handling | `src/GUI/input.odin` | `kind.key` |
| Per-frame update | Widget update dispatch | `kind.update` |

Custom widget implementations must invalidate the appropriate state whenever they modify data that affects layout, rendering, or hit testing.

For example:

```odin
invalidate(g, id, Dirty_Flags{.Measure, .Visual})
```

The extension requirements and recommended patterns are documented in [`docs/extending.md`](extending.md).

### 8.3 Scene Constructor Registry

The kind registry and scene constructor registry have separate responsibilities:

- **Kind registry** — Defines how a widget behaves.
- **Scene constructor registry** — Defines how a scene file creates an instance of a widget.

`Scene_Register_Constructor` registers a constructor for a widget type. The constructor table belongs to the individual GUI instance, so registrations are isolated between GUI instances.

During scene loading, CalcUI resolves custom classes and registered widget constructors to create the requested nodes.

`ScrollArea` has a scene constructor. `Image` does not currently have one, so an `Image` node cannot yet be instantiated through the scene constructor registry.

Unsupported node types are reported as loader errors rather than silently instantiated.

The complete scene format and loading behaviour are documented in [`docs/scene-format.md`](scene-format.md).

## 9. Memory and Resource Ownership

CalcUI uses two primary arenas.

| Arena | Contents | Lifetime |
|---|---|---|
| `g.arena` | Widgets, long-lived widget data, font files, and font instances. | Until GUI shutdown. |
| `g.frame_arena` | Temporary per-frame data, including text-shaping allocations. | Reset at the beginning of the next frame. |

### 9.1 Widget Allocation

Widgets are allocated from `g.arena`:

```odin
w, err := virt.new(&g.arena, Widget)
```

Arena allocations are not automatically zeroed. `New_Widget` therefore initializes newly allocated widgets to a clean state.

Widgets containing substantial dynamic data keep that data separately rather than embedding large collections directly in the widget structure.

Examples include virtual-list data, table storage, node-graph state, and canvas contents.

### 9.2 Fonts

Font resources are tracked through three collections:

- `g.font_files` — Parsed font files.
- `g.font_families` — Font families and fallback relationships.
- `g.fonts` — Font instances configured for specific sizes.

The font-instance cache is keyed by the font file and requested size, allowing previously created instances to be reused.

### 9.3 Themes

The active theme is stored in `g.theme`.

`GUI_Set_Theme` replaces the current theme and releases the previous one. The active theme is released during GUI shutdown.

### 9.4 Ownership Rules

CalcUI distinguishes between borrowed strings, individually owned allocations, and arena-owned data.

- **Individually owned strings** are cloned with `strings.clone` and released with `delete`.
- **GUI-lifetime data** is allocated through `virt.arena_allocator(&g.arena)` and reclaimed when the GUI shuts down.
- **Borrowed strings** remain owned by the application, which must keep them alive for as long as CalcUI references them.

`widget_release_data` releases individually owned resources but does not attempt to free allocations belonging to the GUI arena.

For example, text-editing widgets own their editable buffers. Labels and other simple display widgets may reference application-owned strings instead.

Widget destruction releases resources owned by that widget. `Shutdown_GUI` releases the resources of remaining widgets and the GUI itself.

## 10. Testing and Benchmarks

CalcUI's GUI tests use a headless backend. They do not require a window or a physical display.

The tests construct a GUI instance, perform operations, and inspect the resulting state and draw data.

### 10.1 Test Helpers

`src/GUI/tests.odin` contains shared test helpers:

```odin
test_gui :: proc(t: ^testing.T) -> ^GUI
```

`test_gui_destroy` tears down the test GUI and ensures allocated resources are released.

The mock backend records texture uploads, allowing tests to verify atlas behaviour without a real renderer.

### 10.2 Test Organization

| File | Coverage |
|---|---|
| `widget_test.odin` | Widget behaviour. |
| `widget_field_test.odin` | Widget fields and properties. |
| `widget_collection_test.odin` | Collection widgets. |
| `draw_call_test.odin` | Draw-list and command batching. |
| `atlas_test.odin` | Atlas allocation and uploads. |
| `contract_test.odin` | Core/backend contract behaviour. |
| `scene_test.odin` | Scene loading and themes. |
| `scene_registry_test.odin` | Scene constructor registration. |

### 10.3 Benchmarks

`src/GUI/bench_test.odin` contains benchmarks for:

- Draw-list construction.
- Style processing.
- Layout.
- Atlas operations.

Benchmarks report measurements through the test output.

Run the GUI tests and checks with:

```sh
odin test src/GUI
odin check src/GUI -no-entry-point
```

Odin tests may run concurrently, which can introduce measurement noise.

For more consistent benchmark results, use:

```sh
odin test src/GUI -o:speed -define:ODIN_TEST_THREADS=1
```