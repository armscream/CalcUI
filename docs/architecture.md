# CalcUI Architecture

CalcUI is a retained-mode GUI toolkit written in Odin. It maintains a persistent widget tree, performs incremental layout, routes input, manages text and resources, and builds retained draw lists for rendering.

This document describes its main packages, runtime architecture, rendering and layout systems, extensibility, memory ownership, and testing.

## 1. Architecture Overview

CalcUI is organized into four main layers:

- **GUI Core** — Widget management, layout, input, text, themes, atlas, scene support, and draw-list construction.
- **Rendering Backends** — Consume draw lists and render them using the available graphics API.
- **Window and Platform Layer** — Window creation, platform events, coordinate conversion, cursors, clipboard, and floating panels.
- **Runa** — Text shaping, line breaking, and glyph rasterization.

The core is independent of SDL and other windowing libraries. It communicates with rendering backends through a function-pointer interface and receives platform input through CalcUI's own event types.

## 2. Package Structure

| Directory | Responsibility |
|---|---|
| `src/GUI` | Public facade. Exposes the API and coordinates Core, Widgets, and Animation. |
| `src/GUI/Core` | Widget tree, layout, input, drawing, atlas, text, fonts, styles, themes, popups, docking, and core widget systems. |
| `src/GUI/Widgets` | Built-in widgets and scene loading, saving, and reporting. |
| `src/GUI/Animation` | Tweening, easing, interpolation, and animation updates. |
| `src/Backend` | SDL3 renderer, SDL3 GPU, and headless software renderer. |
| `src/Platform` | SDL3 windows, event translation, coordinate conversion, floating windows, cursors, and clipboard. |
| `src/GUI/Accessibility` | Native accessibility integrations. Generic accessibility metadata lives in Core. |
| `src/App` | Shared application setup and platform/backend wiring. |
| `src/GUI/dependencies/Runa` | Text shaping and rasterization dependency. |
| `examples` | Standalone example applications. |
| `assets` | Fonts and example resources. |
| `tools` | Shaders and development utilities. |

Examples share application and window setup through `examples/common`.

### 2.1 Backend Interface

The core communicates with renderers through `Backend`, defined in `src/GUI/Core/types.odin`.

Its function pointers cover:

- Backend creation, destruction, and resizing.
- Texture upload, region updates, and destruction.
- Draw-list submission.
- Releasing rendering resources associated with a window before that window is destroyed.

Two capability flags describe optional rendering features:

- `supports_shapes` — Allows rounded shapes and related effects to be rendered through shader parameters instead of CPU-generated geometry.
- `supports_backdrop_blur` — Allows the backend to sample and blur previously rendered content behind glass widgets.

Window handles are opaque `rawptr` values, keeping platform-specific types out of Core.

The software backend in `src/Backend/software.odin` implements the same interface without a window or GPU. It renders into CPU-side RGBA pixels and supports shape and backdrop effects. It is primarily used for correctness testing and visual verification, not performance comparison with GPU backends.

The application defaults to SDL3 GPU. `--gpu` forces GPU creation, while `--renderer` selects the SDL3 renderer. Automatic GPU creation falls back to the renderer if initialization fails.

### 2.2 Platform Integration

`src/Platform` translates SDL events into `GUI.Event` values. The core processes these through `GUI.Handle_Events` and never directly handles SDL events.

CalcUI separates logical UI coordinates from physical rendering pixels:

- Window dimensions and input positions use logical coordinates.
- The GUI applies `GUI.scale` when producing physical pixel geometry.

On resize, the platform updates the logical window size, the GUI recalculates its viewport, and affected layout and drawing are invalidated.

Other platform integrations can provide their own windows and event translation as long as they follow the same coordinate contract.

## 3. Widget Tree and Identity

CalcUI maintains a persistent widget tree. Widgets retain their identity and state between frames.

### 3.1 Widget Handles

Widgets are identified by `Widget_ID`:

```odin
Widget_ID :: struct {
    index:      u32,
    generation: u32,
}
```

The index identifies a slot in `g.widgets`; the generation identifies the widget currently occupying that slot.

When a widget is destroyed, its slot can be reused with a new generation. This prevents stale handles from referring to newly created widgets.

Use `Widget_Get` to retrieve a validated pointer or `Widget_Alive` to check whether a handle is valid. Handles are preferred for references that must survive structural changes.

### 3.2 Creation and Hierarchy

`New_Widget` is the generic constructor:

```odin
New_Widget :: proc(
    g: ^GUI,
    type: Widget_Type,
    parent: Widget_ID,
    opts: Widget_Opts = {},
) -> Widget_ID
```

Built-in `Make_<Name>` functions provide convenient typed constructors.

Children are linked through an intrusive sibling list:

```odin
first_child:  Widget_ID,
last_child:   Widget_ID,
prev_sibling: Widget_ID,
next_sibling: Widget_ID,
```

`Widget_Attach`, `Widget_Detach`, and `Widget_Insert_At` update these relationships without rebuilding child arrays.

Detaching does not destroy a widget or change its identity, allowing runtime reparenting and docking.

### 3.3 Destruction

`Widget_Free` destroys a widget and its descendants:

```odin
Widget_Free :: proc(g: ^GUI, id: Widget_ID) -> bool
```

Destruction:

- Removes the widget and descendants from the tree.
- Clears references held by focus, hover, pointer capture, dragging, resizing, floating panels, and tooltips.
- Updates affected focus relationships.
- Releases widget-owned dynamic data.
- Returns slots to the free list.

The root cannot be destroyed.

### 3.4 Docking and Floating Panels

Docking separates planning from application. `dock_plan` determines where a dragged panel would be placed; `dock_apply` performs the tree changes. Preview and drop use the same plan.

Detached panels become floating panels stored in `g.floats`. Each has its own draw list and platform window.

The core manages widget content, while the platform layer manages the window. Before a floating window is destroyed, `Backend.release_target` releases its associated rendering resources, such as swapchains, buffers, textures, or renderer instances.

## 4. Frame Lifecycle

`Frame` lives in `src/GUI/api.odin` and coordinates the per-frame work across Core, Widgets, and Animation.

The simplified sequence is:

1. **Begin frame** — Process pending frame bookkeeping and reclaim temporary allocations.
2. **Update time** — Calculate `g.dt` from the GUI clock, clamping large frame deltas to 0.25 seconds.
3. **Widget update** — Run visible widgets' `kind.update` hooks before layout.
4. **Animation** — Advance tweens and apply animated property changes.
5. **Layout** — Measure and arrange invalidated widgets.
6. **Post-layout updates** — Reposition menus, update resize hover, and run `kind.post_update`.
7. **Build draw lists** — Rebuild the main and floating-panel lists when invalidated.
8. **Flush atlas** — Upload modified texture regions and advance atlas bookkeeping.

Both widget update passes first collect visible handles, then validate each handle before calling its hook. This allows callbacks to destroy widgets safely.

`update` runs before layout, so changes affect the current frame. `post_update` runs after layout, making it suitable for logic that needs current geometry.

### 4.1 Application Loop and Frame Scheduling

`Frame` builds rendering data but does not present it. `Core.App_Run` owns the shared event and application loop.

It uses `Core.App_Platform` callbacks for clock access, event polling, waiting, popup synchronization, cursor updates, and clipboard synchronization.

The platform layer supplies SDL3 implementations, while `src/App` connects the window, backend, fonts, and callbacks.

The application loop also processes accessibility actions and submits the main and floating-panel draw lists.

CalcUI uses demand-driven frame scheduling:

- `GUI_Needs_Frame` reports whether another frame is needed.
- `GUI_Request_Frame` explicitly requests one.
- Input, resize, and window exposure events request frames automatically.
- Animations, style transitions, wake timers, invalidated draw lists, and pending atlas uploads also request frames.

`GUI_Tick(g, dt)` is the only way time enters the core. Widgets can register wake times through `Core.wake_at`.

`GUI_Next_Frame_Delay_MS` reports the time until the next wake timer, allowing the platform to sleep instead of continuously polling.

### 4.2 Retained Draw Lists

Draw lists persist between frames.

- `g.draw_valid` indicates whether the retained list is current.
- `g.draw_epoch` tracks invalidation.
- `draw_invalidate` marks the list stale when relevant widget, pointer, focus, hover, font, texture, or other visual state changes.

An unchanged frame skips draw-list construction and reuses the cached scene.

Visual-only changes can produce a physical `dirty_rect`, allowing capable backends to redraw only the affected region. Layout, theme, hit-test, or other structural changes invalidate this optimization and require a full rebuild.

The atlas also tracks regions referenced by retained draw lists. Eviction skips regions still referenced by the current retained frame, preventing images or glyphs from disappearing between rebuilds.

## 5. Rendering Architecture

The core builds a backend-independent `Draw_List`. Backends consume its vertices, indices, commands, and clipping information.

### 5.1 Texture Atlas

Each GUI instance owns a shared `UI_Atlas`, normally made of 1024 x 1024 RGBA pages (4 MiB each). The first page covers a light application; a request that does not fit any page opens another one, so a light window does not pay for a large texture it never fills.

It stores:

- A white texel for solid-colour primitives.
- Rasterized glyphs.
- Images and other atlas-managed textures.

The atlas maintains CPU-side pixels for each page and tracks modified regions. The first flush uploads a complete page; subsequent flushes upload only changed regions. Each page is its own texture (`atlas_texture_of_page`), and a draw command names the texture of the page its region lives on.

Atlas regions use generation-based handles to prevent stale references after reuse.

Allocation uses shelves. Glyphs and images can be evicted when they are no longer pinned or referenced by retained draw lists. Evicted glyphs are rasterized again when needed.

### 5.2 Draw List

`Draw_List`, defined in `src/GUI/Core/draw.odin`, contains:

- Shared vertex and index buffers.
- An ordered command list.
- Clip-stack and current clipping state.
- A revision counter used by the GPU backend to detect geometry changes.

Vertices carry position, texture coordinates, colour, shape parameters, corner radii, border information, and opacity.

The GPU backend packs the CPU vertex format into a smaller 60-byte `Packed_Vertex` format before upload. Packing and unpacking are implemented in `pack_vertex` and `unpack_vertex`.

A `Draw_Command` identifies an index range, texture, bounds, and optional glass information.

Adjacent commands using the same texture are merged unless a command break is required. Glass commands remain separate because they need to capture the rendered scene at their position in the command stream.

### 5.3 Drawing and Clipping

Core drawing primitives include:

| Operation | Purpose |
|---|---|
| `draw_quad` | Textured quads for images and glyphs. |
| `draw_quad_rounded` | Textured quads with rounded corners. |
| `draw_rect` | Solid-colour rectangles and rounded shapes. |
| `draw_glass` | Frosted surfaces over previously rendered content. |
| `draw_text` | Text shaping and glyph rendering through Runa and the atlas. |

Rounded shapes use shader-based SDF rendering when supported. Otherwise, the core generates CPU geometry.

Clipping is applied while geometry is added to the draw list. Widgets can push rectangular or rounded clips and restore the previous state afterward.

Nested clips are intersected. Primitives entirely inside the safe clip region are emitted unchanged; primitives crossing rounded boundaries are clipped as polygons using Sutherland-Hodgman. Completely clipped primitives produce no geometry.

Clipping is opt-in through `clip_contents`, although scroll containers and other widgets enable it as needed.

### 5.4 Shapes, Borders, and Shadows

Style boxes are drawn in this order:

1. Outer shadow.
2. Background or glass.
3. Border.
4. Inset shadow.

Uniform borders use a single shaped quad when supported. Different border colours use separate strips following the rounded outline.

Outer shadows expand the shape and use softness for blur. Inset shadows use negative softness and are drawn inside the border.

Without shader shape support, the core generates fallback geometry on the CPU.

### 5.5 Backdrop Glass

A style box with `backdrop_blur` becomes a glass command rather than a normal solid fill.

The SDL3 GPU backend renders into an offscreen scene and captures the backdrop for groups of compatible glass commands.

It uses a half-resolution backdrop texture with a five-level mip chain. Blur selects an appropriate mip level, reducing sampling cost for larger blur radii. Refraction, dispersion, Fresnel, and saturation are optional optical effects encoded in the vertex data.

Glass commands remain ordered in the draw list because each capture must reflect the scene rendered before that command.

The software backend implements the same general optical model for visual verification. Backends without backdrop support render a tinted rounded surface without blur, allowing the same application to run across backends.

### 5.6 Partial Redraw

For eligible visual-only changes, the GPU backend can replay the retained command stream inside a dirty rectangle.

Partial redraw is disabled when the change affects layout, arrangement, theme, hit testing, or other state that could invalidate geometry. It is also disabled for unsuitable dirty regions, transparent root backgrounds, glass-containing lists, and invalidated scene caches.

The software backend mirrors partial redraw and includes tests verifying that pixels outside the dirty rectangle remain unchanged.

Backend statistics track scene updates, partial redraws, backdrop captures, mip generation, glass sampling cost, and wake timers.

## 6. Layout Engine

Layout lives in `src/GUI/Core/layout.odin` and runs in two stages:

1. **Measurement** — Determine the minimum size each widget requires.
2. **Arrangement** — Assign final rectangles and position descendants.

The system is incremental. Widgets track their own invalidation state and aggregate invalidation from descendants, allowing unaffected branches to be skipped.

### 6.1 Invalidation

The main invalidation flags are:

| Flag | Meaning |
|---|---|
| `Measure` | Measured size is stale. |
| `Arrange` | Assigned geometry is stale. |
| `Visual` | Rendered appearance is stale. |
| `Hit` | Hit-test geometry or state is stale. |
| `Theme` | Theme-derived styling is stale. |

Invalidation propagates according to dependencies. For example, a measurement change also invalidates arrangement and hit testing.

Use the public setters whenever possible:

```odin
GUI.Widget_Set_Text(g, label, "Updated text")
GUI.Widget_Set_Visible(g, panel, false)
GUI.Widget_Set_Style(g, button, style)
GUI.Widget_Set_Offsets(g, bar, offsets)
```

Setters apply the appropriate invalidation. Direct field changes require manual invalidation. `GUI_Invalidate_All` provides a full-tree fallback.

### 6.2 Measurement and Arrangement

Measurement accounts for:

- Base and custom minimum sizes.
- Text dimensions.
- Style padding.
- Widget-specific measurement behavior.
- Content dimensions where applicable.

Text measurement uses the same layout as drawing and is cached in `g.measure_cache`.

Scrollable widgets maintain viewport size, content size, and scroll offset separately. Virtualized widgets can report their logical content size through the `content_size` kind hook without creating a widget for every item.

Arrangement assigns final rectangles and calculates clipping from the widget bounds and inherited parent clip.

Container widgets position children according to their layout rules. Other widgets use anchors and offsets.

### 6.3 Anchors and Offsets

Widgets position themselves relative to their parent using four normalized anchors and four UI-unit offsets.

```odin
Anchor :: struct {
    left, top, right, bottom: f32
}

Offset :: struct {
    left, top, right, bottom: f32
}
```

`resolve_rect` combines them to calculate the final rectangle.

Available presets include `Fill`, the four corners, `Center`, `Left`, `Right`, `Top`, `Bottom`, and `Custom`. `Fill` is the default.

### 6.4 Containers and Sizing

Built-in containers include:

| Container | Behaviour |
|---|---|
| `VBox` / `HBox` | Vertical or horizontal child arrangement. |
| `Split` | Resizable sections. |
| `Tabs` / `TabContainer` | Displays one child page at a time. |
| `GridContainer` | Row-and-column arrangement. |
| `MarginContainer` | Adds space around content. |
| `CenterContainer` | Centres child content. |
| `PanelContainer` | Places content inside an available area. |
| `ScrollContainer` / `ScrollArea` | Viewport over larger content. |
| `FlowContainer` | Sequential arrangement with wrapping. |
| `AspectRatioContainer` | Maintains an aspect ratio. |

A `Layout_Constraint` describes a widget's minimum, preferred, and maximum sizes.

Important sizing properties include:

- `min_size`: Preferred size from measurement.
- `custom_min_size`: Additional minimum requested by the application.
- `custom_max_size`: Maximum size; zero means unlimited.
- `fixed`: Prevents sharing surplus space.
- `weight`: Determines the share of available surplus space.
- `shrink_weight`: Determines the share of a space deficit.
- `absolute`: Removes the widget from container flow.
- `manual_size`: Preserves manually adjusted panel dimensions.

Box containers distribute surplus space by stretch weight and redistribute space when children reach their maximum. When children do not fit, shrink weights determine how space is reclaimed.

Absolute children do not participate in flow allocation and are positioned using anchors and offsets. Inactive tab pages are neither drawn nor hit-tested.

## 7. Input and Interaction

Input types are defined in `src/GUI/Core/input.odin`.

`GUI.Event` represents platform-independent mouse, keyboard, text, IME, resize, and quit events.

Mouse events contain:

- `pos`: Position relative to the originating window.
- `global`: Position relative to the screen.

The distinction supports interaction with floating panels outside the main window.

The platform layer translates native events into CalcUI events and places them in `g.events`. `GUI.Handle_Events` processes the queue. Events added during dispatch are handled in the next processing pass.

### 7.1 Hit Testing and Routing

`collect_hits` gathers eligible widgets under the pointer, ordered from topmost to bottommost. Child ordering and `z_index` determine which widgets receive priority.

`Mouse_Filter` controls pointer participation:

| Filter | Behaviour |
|---|---|
| `Stop` | Receives the event and prevents propagation behind it. |
| `Pass` | Receives the event while allowing propagation. |
| `Ignore` | Does not participate in pointer interaction. |

Disabled widgets do not receive pointer interaction, allowing eligible widgets behind them to receive events.

### 7.2 Focus

Widgets can receive keyboard focus according to their `focus_mode`, visibility, and enabled state.

Focus changes are handled through `focus_set` and emit the appropriate signals. Focus is cleared when a widget becomes hidden, disabled, destroyed, or detached.

Tab navigation uses `tab_index`, with tree order breaking ties. Directional navigation prioritizes explicit `focus_neighbour` relationships, then spatial position.

### 7.3 Signals

Signals are implemented in `src/GUI/Core/class.odin`.

Widgets share a common signal interface, allowing applications to connect to events without depending on concrete widget types. Unconnected signals are `nil`.

See `docs/widgets.md` for the available signals.

## 8. Widget Extensibility

Custom widget behaviour is provided through the kind registry in `src/GUI/Core/kinds.odin`.

A `Widget_Kind` defines optional callbacks and default presentation:

```odin
Widget_Kind :: struct {
    draw:        proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect),
    layout:      proc(g: ^GUI, id: Widget_ID, w: ^Widget, rect: Rect),
    click:       proc(g: ^GUI, id: Widget_ID, w: ^Widget),
    key:         proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Key_Down_Event),
    update:      proc(g: ^GUI, id: Widget_ID, w: ^Widget, dt: f32),
    post_update: proc(g: ^GUI, id: Widget_ID, w: ^Widget, dt: f32),
    style:       Style,
    theme_name:  string,
}
```

Callbacks provide drawing, layout, input, and per-frame behavior. `update` runs before layout; `post_update` runs afterward.

Register kinds through `kind_register`:

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

Registration is idempotent: repeated registration does not overwrite an existing entry.

Custom widgets must invalidate the appropriate state when their data changes:

```odin
invalidate(g, id, Dirty_Flags{.Measure, .Visual})
```

### 8.1 Scene Constructors

The kind registry defines widget behavior. The scene constructor registry defines how scene files instantiate widgets.

`Scene_Register_Constructor` registers a constructor for a widget type. Constructor registrations belong to individual GUI instances.

Unsupported scene node types are reported as loader errors. `Image` and `ScrollArea` currently have no built-in scene constructors.

See `docs/extending.md` and `docs/scene-format.md` for extension and scene-loading details.

## 9. Memory and Resource Ownership

CalcUI primarily uses two arenas:

| Arena | Contents | Lifetime |
|---|---|---|
| `g.arena` | Widgets, long-lived widget data, font files, and font instances. | GUI lifetime. |
| `g.frame_arena` | Temporary per-frame allocations, including text-shaping data. | Reset at the beginning of the next frame. |

Widgets are allocated from `g.arena`. Since arena allocations are not automatically zeroed, `New_Widget` initializes new widgets explicitly.

Widgets with substantial dynamic data keep it outside the widget struct, such as virtual-list storage, table data, and node-graph state.

### 9.1 Fonts and Themes

Font resources are tracked through:

- `g.font_files`: Parsed font files.
- `g.font_families`: Font families and fallback relationships.
- `g.fonts`: Font instances configured for specific sizes.

Font instances are cached by font file and requested size.

The active theme is stored in `g.theme`. `GUI_Set_Theme` replaces and releases the previous theme; the active theme is also released during GUI shutdown.

### 9.2 Ownership Rules

CalcUI distinguishes three ownership models:

- **Individually owned allocations:** Cloned strings and other individually allocated resources are released with `delete`.
- **GUI-owned allocations:** Data allocated through `g.arena` remains valid until GUI shutdown.
- **Borrowed data:** Application-owned strings must remain alive while CalcUI references them.

`widget_release_data` releases individually owned widget resources but does not free GUI-arena allocations.

Destroying a widget releases its owned resources. `Shutdown_GUI` releases remaining widgets and GUI resources.

## 10. Testing and Benchmarks

CalcUI uses a headless backend for GUI tests, so most tests require no window or physical display.

Shared helpers in `src/Tests/test_helpers.odin` create and destroy GUI instances. The mock backend records texture uploads, allowing atlas behavior to be tested without a real renderer.

### 10.1 Test Coverage

| File | Coverage |
|---|---|
| `font_test.odin` | Glyph positioning and pixel alignment. |
| `frame_lifecycle_test.odin` | Update ordering and destruction from hooks. |
| `interaction_state_test.odin` | Hover and pressed states and clicks. |
| `layout_solver_test.odin` | Constraints, growth, shrink, and absolute children. |
| `packed_vertex_test.odin` | Vertex layout, quantization, and draw revision. |
| `scene_style_test.odin` | Shape and shadow fields through a scene save and load. |
| `NodeGraph/node_graph_test.odin` | Node graph model, geometry, regions, and serialization. |

`src/GUI/NodeGraph` is optional and does not form part of the core GUI dependency chain.

### 10.2 Benchmarks

`src/Tests/bench_test.odin` covers:

- Draw-list construction, text, and rounded shapes.
- Frame construction.
- Style and colour processing.
- Layout.
- Atlas operations.
- Virtualized lists and data tables.

Results are reported through test output.

### 10.3 Running Tests

```sh
odin check src/GUI/NodeGraph -no-entry-point
odin test src/GUI/NodeGraph

odin check src/Tests -no-entry-point
odin test src/Tests
```

For more consistent benchmark measurements, run tests with a single test thread:

```sh
odin test src/Tests -o:speed -define:ODIN_TEST_THREADS=1
```

Odin tests may otherwise execute concurrently, introducing measurement noise.
