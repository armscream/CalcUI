# CalcUI Architecture

How CalcUI is put together: its packages, widget tree, frame lifecycle, rendering pipeline, layout engine, input system, extensibility, memory ownership and tests.

## 1. Architecture Overview

CalcUI is a retained-mode GUI toolkit in Odin. The core keeps a persistent widget tree, lays out incrementally, routes input, manages text and resources, and builds draw lists.

The code is split into four layers:

- **GUI Core** — widget management, layout, input routing, text, themes, atlas, scene loading, draw-list construction.
- **Rendering backends** — turn the core's draw lists into rendering operations.
- **Window layer** — windows, platform events, coordinate conversion, cursors, clipboard, floating panels.
- **Runa** — text shaping, line breaking, glyph rasterization.

The core does not depend on SDL. It reaches a backend through a function-pointer interface and receives platform events as CalcUI's own event types.

## 2. Package Structure

| Directory | Responsibility |
|---|---|
| `src/GUI` | Public facade (`package GUI`). `api.odin` re-exports the public API and defines `Frame`, `Init_GUI`, `New_Widget` and `Load_UI`, delegating to `Core`, `Widgets` and `Animation`. |
| `src/GUI/Core` | Engine and core implementation (`package Core`): widget tree, layout, input, draw list, atlas, text including the text box, fonts, style and theme, undo, popups, docking and floating panels, scene support types, widget data and option type declarations, and the remaining core widget modules (audio, default theme, inspector, setters). |
| `src/GUI/Widgets` | Built-in widgets (`package Widgets`) in the `widget_*.odin` files, plus scene loading, saving and reporting in `scene.odin`, `scene_save.odin` and `scene_report.odin`. Imports `Core`; `deps.odin` aliases the `Core` names. |
| `src/GUI/Animation` | Animation and tween implementation (`package Animation`): easing, value interpolation, tween stepping, animation application. Imports `Core`; `Frame` calls `Animation.Animation_Update` before layout. |
| `src/Backend` | Rendering implementations: SDL3 renderer, SDL3 GPU, and the shared headless software rasterizer. |
| `src/Window` | SDL3 windows, event translation, coordinate conversion, floating windows, cursor and clipboard integration. |
| `src/GUI/dependencies/Runa` | Upstream dependency, unchanged: text shaping, line breaking and rasterization. |
| `examples` | Standalone example applications. |
| `assets` | Fonts and other example resources. |
| `tools` | Shaders and development utilities. |

The examples share application and window setup through `examples/common`.

### 2.1 Rendering Backend Interface

The GUI core talks to a backend through `Backend`, defined in `src/GUI/Core/types.odin`.

```odin
Backend :: struct {
    ctx:                    rawptr,
    create:                 proc(ctx, window: rawptr, w, h: i32) -> bool,
    destroy:                proc(ctx: rawptr),
    resize:                 proc(ctx: rawptr, w, h: i32) -> bool,
    upload_texture:         proc(ctx, id: Texture_ID, pixels: []u8, w, h: i32) -> bool,
    upload_texture_regions: proc(ctx, id: Texture_ID, regions: []Texture_Upload) -> bool,
    destroy_texture:        proc(ctx: rawptr, id: Texture_ID),
    submit:                 proc(ctx: rawptr, dl: ^Draw_List),
    submit_target:          proc(ctx: rawptr, dl: ^Draw_List, window: rawptr),
    release_target:         proc(ctx: rawptr, window: rawptr),
    supports_shapes:        bool,
    supports_backdrop_blur: bool,
}
```

The interface covers backend init, shutdown and resize; texture creation, update and destruction; draw-list submission; and handing a window back before the window layer destroys it, so a swapchain, renderer or GPU slot owned by that window is released in time. Two flags add optional features: shape rendering in the shader, and reading and blurring the target behind a widget.

The window handle is an opaque `rawptr`, so SDL types never leak into the core.

`supports_shapes` says whether the backend renders shape effects such as rounded corners in its shader. Without it, the core generates CPU geometry instead.

`supports_backdrop_blur` says whether the backend can sample what it has already drawn behind a widget. The draw list marks a frosted box as a standalone glass command; a backend that can read its own target captures a shared backdrop for a group of glass commands and blurs it. A backend that cannot keeps the tint and skips the blur, so the call is safe everywhere.

The shared software backend in `src/Backend/software.odin` implements the same contract with no window and no GPU. It evaluates SDF shape kinds, borders, shadows and backdrop glass on the CPU and writes RGBA pixels that `tools/shot_sdf` and `examples/08_custom_backend` consume. It is a correctness and visual verification tool: single-threaded, and not an exact match for GPU sampling. It sets both `supports_shapes` and `supports_backdrop_blur`, so the core emits the shader path rather than CPU tessellation.

`App` asks for the SDL3 GPU by default (`Backend_Choice.Auto`). `--gpu` forces it and fails when it cannot be created; `--renderer` forces the SDL3 renderer. When automatic GPU creation fails, the GPU device is released and the renderer takes its place.

### 2.2 Platform Integration and Coordinate Spaces

`src/Window` turns SDL events into `GUI.Event` values. The core never sees SDL events: they go into `g.events` and `GUI.Handle_Events` consumes them.

The Window layer works in logical window sizes and input coordinates. The core converts them into physical pixel geometry through `GUI.scale`, which keeps application-facing layout dimensions separate from render pixels.

On a resize:

1. The Window layer reads the updated logical window size.
2. The GUI updates its logical size and recomputes its pixel-space viewport from the current scale.
3. Layout and drawing are invalidated as needed.
4. The next frame rebuilds the affected geometry with the new size and screen ratios.

The interface therefore keeps its proportions when the window size or display scaling changes.

Another platform integration can manage its own windows and translate input into CalcUI event types, as long as it follows the same coordinate-space contract.

## 3. Widget Tree and Identity

CalcUI keeps a retained-mode widget tree. Widgets persist between frames with their own identity and state.

### 3.1 Widget Handles

Each widget is identified by a `Widget_ID`:

```odin
Widget_ID :: struct {
    index:      u32,
    generation: u32,
}
```

`index` is a slot in `g.widgets`; `generation` identifies the widget that occupies it. Destroying a widget frees the slot for reuse but changes the generation, so a stale handle cannot refer to a newly created widget.

`Widget_Get` validates a handle and returns the widget pointer, or `nil`. `Widget_Alive` is a convenience validity check.

Widgets come from the GUI's arena, so a returned pointer stays valid while its allocation lives. Prefer handles for references that must survive structural changes.

### 3.2 Widget Creation

`New_Widget` is the generic constructor:

```odin
New_Widget :: proc(
    g: ^GUI,
    type: Widget_Type,
    parent: Widget_ID,
    opts: Widget_Opts = {},
) -> Widget_ID
```

The `Make_<Name>` functions wrap it for built-in widgets. Use `New_Widget` by type when there is no dedicated constructor.

### 3.3 Child Relationships

Parents and children are linked with an intrusive sibling list:

```odin
first_child:  Widget_ID,
last_child:   Widget_ID,
prev_sibling: Widget_ID,
next_sibling: Widget_ID,
```

`Widget_Attach` and `Widget_Detach` in `src/GUI/Core/widget.odin` update the links in O(1) without rebuilding a child array. `Widget_Insert_At` inserts at a given position.

Detaching neither destroys a widget nor changes its identity, which makes it a useful primitive for docking and reparenting.

### 3.4 Docking and Runtime Reparenting

The tree can be rearranged at runtime. Docking splits planning from application: `dock_plan` decides where a dragged panel would go, and `dock_apply` makes the tree changes. Preview and drop use the same plan, so the preview matches the result.

### 3.5 Widget Destruction

`Widget_Free` destroys a widget and its descendants:

```odin
Widget_Free :: proc(g: ^GUI, id: Widget_ID) -> bool
```

Destruction keeps the tree consistent and releases the resources of the affected widgets:

- Removes the widget and its descendants from the tree.
- Clears references held by focus, pointer capture, hover, drag-and-drop, resizing, floating panels and tooltips.
- Updates affected focus neighbours and other widget references.
- Releases widget-owned dynamic data.
- Returns widget slots to the free list.

The root widget cannot be destroyed. An old handle stays invalid after its slot is reused, because the generation no longer matches.

### 3.6 Floating Panels

A panel detached from the main window becomes a floating panel in `g.floats`. Each float has its own draw list and platform window: the core manages the panel's widget content, `src/Window` creates and manages its SDL window. Main window and floats are therefore rendered as separate targets.

A window that stops being a float is given back through `Backend.release_target` before `src/Window` destroys it. The GPU backend releases the swapchain, buffers and textures of the panel's slot; the SDL renderer backend destroys the renderer and the window's textures. Leaving a claimed window behind makes the graphics library keep data for a window that no longer exists, and the next window that reuses its handle can fail while it is being created.

## 4. Frame Lifecycle

`Frame` lives in `src/GUI/api.odin`, the public facade. It does the shared per-frame bookkeeping and delegates engine work to `Core`, menu work to `Widgets` and tween work to `Animation` (`src/GUI/Animation/animation.odin`).

```odin
Frame :: proc(g: ^GUI) {
    Core.Frame_Begin(g)
    virt.arena_free_all(&g.frame_arena)
    dt := g.time - g.last_frame_time
    if dt < 0 { dt = 0 }
    if dt > 0.25 { dt = 0.25 }
    g.frame_time = dt
    g.dt = dt
    g.last_frame_time = g.time
    Core.caret_tick(g)
    Core.widget_update_pass(g)
    Animation.Animation_Update(g, g.dt)
    Core.layout_pass(g)
    Widgets.menu_buttons_reposition(g)
    Core.update_resize_hover(g)
    Core.widget_post_update_pass(g)
    if Core.draw_needs_rebuild(g) {
        Core.build_draw_list(g)
    }
    Core.atlas_flush(g.atlas, g.backend, g.atlas_texture)
    Core.atlas_next_frame(g.atlas)
    Core.report_atlas_failures(g)
}
```

The stages:

1. **Begin the frame** — answer the request that ran the frame, advance the frame count, reclaim the previous frame's temporary allocations.
2. **Update frame time** — derive `g.dt` from the GUI's single clock, which only `GUI_Tick` advances. A sleep longer than a quarter of a second is clamped so a tween does not jump across its range.
3. **Run the state update** — call `kind.update` for visible widgets, before layout, so state changes made there are measured and arranged in the same frame.
4. **Run the animations** — step every tween, apply a property tween's value to its widget, and invalidate only the systems that property affects. Size and position changes are seen by the layout pass of the same frame.
5. **Run layout** — measure and arrange widgets whose layout state is invalidated.
6. **Update menus and resize hover** — reposition open menus and determine resize interactions from the current geometry.
7. **Run the post update** — call `kind.post_update` for visible widgets after layout and before drawing. Interaction code that reads rectangles or the pointer belongs here.
8. **Build draw lists** — rebuild the main window's list and the float lists when the retained ones are out of date, then keep them for later frames.
9. **Flush the atlas** — upload modified texture regions, advance atlas frame bookkeeping, report atlas failures.

Both update passes first gather the visible widgets into a snapshot of handles, then look up each handle again before calling its hook. A hook may therefore destroy a widget without leaving the pass with a stale pointer.

`Frame` builds rendering data but does not present it. The application loop handles events, runs the frame, syncs platform state and submits the draw lists. The shared loop is in `src/App/app.odin`:

```odin
plat.Poll_Events(&app.window, &app.gui.events)
GUI_Tick(app.gui, plat.Clock_Delta())
input_pending := len(app.gui.events) > 0
Handle_Events(app.gui)

if GUI_Needs_Frame(app.gui) {
    if update != nil { update(app) }
    Frame(app.gui)

    plat.Sync_Popups(
        &app.window,
        app.gui.floats[:],
        app.backend.release_target,
        app.backend.ctx,
    )
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
} else if !input_pending {
    plat.Wait_Events(&app.window, &app.gui.events, GUI_Next_Frame_Delay_MS(app.gui))
}
```

That keeps application-level event processing and presentation outside the core's frame construction.

### Frame scheduling

`Frame` builds a frame; the application loop decides whether one is worth building. `GUI_Needs_Frame` reports true when a frame was requested, the retained draw lists are out of date, the tree is dirty, an animation or style transition is running, a wake timer is due, or the atlas has uploads waiting.

There is one scheduling model: the application owns the clock, the core owns the wake timers. `GUI_Tick(g, dt)` is the only way time enters the core; it adds the loop's delta to `g.time` and rejects a negative or non-finite value. A widget carrying a timer registers an absolute time with `Core.wake_at`, and that set is cleared at the start of every frame. `GUI_Next_Frame_Delay_MS` reports the milliseconds until the earliest timer, `0` when one is due, and `-1` when nothing is pending. The window layer turns that into a `Wait_Events` timeout, so an idle application sleeps until the next blink, repaint or toast instead of spinning.

`GUI_Request_Frame` asks for a frame explicitly when a program changes state the setters did not see. Input events, window resizes and window exposure ask for a frame by themselves. Continuous mode and `GUI_Set_Frame_Mode` no longer exist; an application that wants every pass calls `Frame` from its own loop.

### Draw-list retention

Draw lists are retained between frames. `g.draw_valid` says whether the list in `g.draw` still describes the tree, and `g.draw_epoch` counts the invalidations that take it away. `draw_invalidate` is called by every kind of widget invalidation, by pointer movement, by focus and hover changes, by drag and resize updates, by font and texture changes, and by `GUI_Request_Frame`. A build records the epoch when it starts; an invalidation that arrives during the walk leaves the list invalid for the next frame instead of keeping geometry that is already stale.

`draw_needs_rebuild` is the gate `Frame` uses. An unchanged frame skips the tree walk and geometry generation, and the backend presents the cached scene again. The inspector is the exception: it reports the numbers of the running frame, so it always asks for a build.

A build caused only by a `Visual` invalidation also fills `Draw_List.dirty_rect` with the physical rectangle of the changed widget, padded by its shadow and by the backdrop a glass surface reads. That rectangle is dropped by any invalidation carrying `Measure`, `Arrange`, `Theme` or `Hit`, by an explicit `GUI_Request_Frame`, and by a build where the root background is not opaque. An invalidation with no bounds behind it taints the whole build, so a theme change followed by a caption that updates its text still repaints everything instead of shrinking to the caption. Backends may replay the retained command stream inside the rectangle instead of drawing the whole scene.

Atlas regions named by a retained list must stay alive. `atlas_build_begin` records the build's atlas frame in `retained_frame`, `atlas_touch` stamps every image drawn during the walk with that frame, and `atlas_evict` skips regions whose stamp matches `retained_frame`. Glyphs are evictable like images and are rasterized again when needed; eviction picks the least recently used region that is not pinned, that the retained lists do not name, and that can hold the pending request.

## 5. Rendering Architecture

CalcUI uses one shared texture atlas and a batched draw-list representation. The core builds geometry and commands without issuing backend-specific calls; the backend consumes the resulting `Draw_List`.

### 5.1 Texture Atlas

The GUI has a single `UI_Atlas` in `g.atlas`. The default is `ATLAS_DEFAULT_SIZE` (2048 × 2048) RGBA, which is 16 MiB at four bytes per pixel. `Init_GUI_With_Atlas` lets an application request another size.

The atlas holds a white texel for solid-colour primitives, rasterized glyphs from loaded fonts, and images and other textures managed through it. It keeps its own CPU-side pixels; updates modify that copy and mark the affected regions dirty.

The first flush uploads the whole texture. Later flushes upload only modified regions, grouped into one backend upload operation.

```odin
atlas_flush :: proc(
    a: ^UI_Atlas,
    backend: Backend,
    texture: Texture_ID,
)
```

### 5.2 Atlas Allocation and Eviction

Regions are allocated with a shelf allocator: new allocations go into free shelf space, and the allocator can add shelves as space runs out.

Glyphs and images are evictable. An evicted glyph is rasterized again on the next slot lookup, and a region named by a retained draw list survives until the next build.

Regions use generation-based handles: a released and reused slot gets a new generation, so stale handles cannot identify newly allocated regions.

The atlas reserves a 4 × 4 white region near the top-left corner. Solid quads sample its centre through `g.atlas.white_uv`, avoiding filtering into neighbouring texels.

### 5.3 Draw List

The draw list is the rendering contract between core and backend, defined in `src/GUI/Core/draw.odin`.

```odin
Draw_List :: struct {
    vertices:     [dynamic]Draw_Vertex,
    indices:      [dynamic]u32,
    commands:     [dynamic]Draw_Command,
    clip_stack:   [dynamic]Clip_Shape,
    base_clip:    Rect,
    current_clip: Rect,
    clip_inner:   Rect,
    clip_rounded: bool,
    revision:     u64,
}
```

It holds shared vertex and index buffers, an ordered command list and clipping state. `clip_inner` is the intersection of the safe interior of every rounded clip, and `clip_rounded` says whether any clip has corners, so a primitive inside both skips the shape clipper. `revision` advances whenever the list is cleared or a quad or polygon is added; the GPU uses it to tell whether the geometry changed.

A vertex contains:

```odin
Draw_Vertex :: struct {
    pos:      [2]f32,
    uv:       [2]f32,
    colour:   Colour,
    shape:    [4]f32,
    local:    [2]f32,
    softness: f32,
    corners:  [4]f32,
    border:   [4]f32,
    opacity:  f32,
}
```

It stores position, texture coordinates, colour, shape parameters, per-corner radii, per-side border widths, shadow softness, local quad coordinates and the opacity of the list it came from. `shape` is `{kind, signed softness, half width, half height}`; a negative softness marks an inset shadow and its border field carries `{spread, offset x, offset y, 0}`. A glass shape reads the opacity to fade the backdrop it took, since its colour alpha is the tint, not the coverage.

The `border` field means three different things depending on the shape kind: per-side widths for a border, `{spread, offset x, offset y, 0}` for an inset shadow, and the optical stack `{refraction in pixels, dispersion in pixels, fresnel, saturation}` for glass. The draw list scales the whole field by the display scale for the kinds that carry lengths, and only the first two slots for glass, because `fresnel` and `saturation` are ratios. The software backend and the shader both read the same field.

The GPU does not upload this f32 vertex. It packs it into 60 bytes, down from 96:

```odin
Packed_Vertex :: struct {
    pos:     [2]f32,   // 8
    uv:      [2]u16,   // 4, normalized
    colour:  [4]u8,    // 4, normalized
    shape:   [4]f32,   // 16, kind, signed softness, half width, half height
    local:   [2]f32,   // 8
    corners: [4]u16,   // 8, normalized at 1/16 px
    border:  [4]i16,   // 8, normalized signed at 1/128 px
    opacity: f32,      // 4
}
```

`pack_vertex` and `unpack_vertex` are in `src/GUI/Core/draw.odin`. Packing copies `Draw_Vertex.softness` into the packed `shape.y` because the shader reads the signed softness there, while the CPU vertex keeps its radius in `shape.y` for the fallbacks. The tests pin the offsets to the attribute table of `src/Backend/sdl3_gpu.odin`.

A draw command describes an index range and the texture used to render it:

```odin
Draw_Command :: struct {
    texture:    Texture_ID,
    idx_count:  u32,
    idx_offset: u32,
    glass:      bool,
    bounds:     Rect,
    blur:       f32,
}
```

That lets the core batch compatible geometry before it reaches the backend. A glass command is never merged with its neighbours: the backend has to capture the target at that point, so the command stands alone in the stream. `bounds` and `blur` describe the physical region a glass command can read. `blur` is the read radius — the blur radius plus the refraction and dispersion of the optics — so a capture padded by it never runs out of backdrop; a glass without optics keeps the read radius equal to its blur. `Backdrop_Plan` in `src/Backend/backdrop.odin` groups the commands that can share one capture, and both the SDL3 GPU and the software backends call it.

### 5.4 CPU Clipping

Clipping happens while geometry is added to the draw list. A widget that clips its children pushes a clip with `draw_push_clip` or `draw_push_clip_radii` and restores the previous state with `draw_pop_clip`; the latter also gives the clip the corner radii of the widget's style box, so content is cut to the rounded outline. Clipping is opt-in through `clip_contents = .On`, but scroll containers, tab hosts, the chat input and the node graph ask for it themselves, so a shadow or overlay of a plain panel can reach past its box.

Each pushed shape is intersected with the active clip, so nested clipping yields the intersection of all active shapes.

A primitive whose bounds stay inside `clip_inner` is emitted unchanged. A primitive crossing a rounded corner is clipped as a convex polygon with Sutherland-Hodgman, interpolating position, texture coordinates, colour and shape attributes at every cut. The clipper reuses scratch arrays on the draw list, so clipping a glyph does not allocate. A rectangular clip keeps the cheaper path and adjusts quad texture coordinates to preserve the mapping.

Completely clipped primitives are discarded and produce no vertices or indices. This is what makes text, images and nested rounded panels stop at a rounded edge instead of its bounding rectangle.

### 5.5 Drawing Primitives

| Operation | Purpose |
|---|---|
| `draw_quad` | Draws a textured quad, used for images and glyphs. |
| `draw_quad_rounded` | Draws a textured quad with corner radii, as one SDF shape or as a CPU-cut outline. |
| `draw_rect` | Draws a solid-colour rectangle, including supported rounded shapes. |
| `draw_glass` | Draws a frosted box over what is already in the list. |
| `draw_text` | Shapes and lays out text through Runa, then emits glyph quads from the atlas. |

`draw_rect` and `draw_quad_rounded` use the backend's shape capability when available: a shader-capable backend renders rounded corners from fragment-shader shape parameters, otherwise the core generates polygon geometry on the CPU. Both paths use the same draw-list interface.

### 5.6 Command Batching

`draw_command` merges adjacent commands that use the same texture, unless an explicit command break is requested.

Built-in widgets generate their geometry programmatically and introduce no separate textures: their primitives, glyphs and atlas-managed images all use the shared atlas. Normal built-in content therefore batches into a single command per rendering target — one atlas, one ordered geometry stream, minimal command overhead.

Floating panels have independent draw lists and are submitted separately, so each window has its own batching scope.

### 5.7 Backdrop glass

A style box with `backdrop_blur` set is drawn as a glass shape instead of a solid fill. The core emits its quad with `Shape_Kind.Glass`, the tint in the vertex colour, the blur radius in the softness channel and the optical stack in the border channel, and marks the command as glass.

The SDL3 GPU backend renders every list into an offscreen scene and keeps that scene between frames. Glass commands are grouped. The plan tracks one dirty rectangle for solid content and one for glass surfaces drawn since the last capture. A glass command joins the current group when its read rectangle does not meet the solid content and its own bounds do not meet earlier glass. Side-by-side surfaces therefore share a capture even when their blur reads graze each other, while a surface inside another always starts a new one.

At the first command of a group, the pass closes. The whole scene is blitted with a linear filter into level zero of a backdrop texture at half the window resolution, and `GenerateMipmapsForGPUTexture` builds the rest of a five-level chain. The pass then resumes with that texture bound.

The backdrop texture has five levels: level zero is half the window, level four a sixteenth of it. Only level zero is written by the capture, so every level is valid.

A second sampler with a linear mip mode reads the chain trilinearly; the atlas sampler keeps its nearest mode because the atlas has one level. The glass picks its level from the blur: `lod = clamp(log2(max(blur, 1) / 2), 0, 4)`. A blur of 22 pixels therefore wants level 3.46 and costs one tap instead of twenty-five. The dispersion gradient needs a sharper picture, so it takes four taps from `max(lod - 2, 0)` and keeps the normalisation of the old kernel. A blur up to eight pixels keeps the 3 by 3 or 5 by 5 kernel, so a thin surface keeps its look and its sharp dispersion.

A uniform block carries the window metrics and the length of the chain, not a capture region. The shader mixes in the tint, a sheen down from the top edge and a light rim inside the border. The scene is blitted to the swapchain at the end. When the draw-list revision and the window size did not change, the cached scene is blitted without rendering again; a resize or an exposed window drops it through `Backend.invalidate`.

The optical stack of a glass vertex has four parts; when all four are zero, the shader takes the plain path.

- **Refraction** builds a lens band as wide as the biggest corner radius, with a floor of eight pixels and clamped to half of the smaller side. Inside the band the surface tilts by at most 0.55 radians, the outward direction comes from two extra evaluations of the rounded box distance, and the lateral part of a `refract` ray from the eye moves the sample, scaled so the rim moves exactly `refraction` pixels. Those two extra distance evaluations are skipped when neither refraction nor dispersion is set.
- **Dispersion** reads the gradient of a sharper level and moves red and blue in opposite directions by `dispersion` pixels while green stays.
- **Fresnel** uses the Schlick form with a viewer at the middle of the target and a fixed light from the top left, so the rim catches a highlight where the view is grazing. A non-zero fresnel replaces the fixed rim of the plain path, so a panel does not get two rims.
- **Saturation** pumps the backdrop colour around its own luminance, and the adaptive tint lets a bright backdrop keep less of the veil and a dark one more.

A wide glass costs one trilinear tap and four more when it uses dispersion; a glass up to eight pixels costs nine or twenty-five taps of the small kernel. The fifth and the forty-eighth powers on the Fresnel path are products rather than `pow` calls.

The shared software backend in `src/Backend/software.odin` evaluates the same optical stack on the processor, with the same band, tilt, refraction and dispersion, the same grouping rule, a half resolution backdrop and a box-downsampled pyramid of the same five levels, so the CI picture agrees with the shader closely enough to check the bend and the sign of the split.

Backends without `supports_backdrop_blur` draw the tinted, rounded fill only. The draw list is the same, so a scene runs unchanged on either kind of backend.

The benchmarks in `src/Tests/bench_test.odin` report vertex and command counts for their test scenes.

### 5.8 Shapes and Shadows

`draw_stylebox_box` draws every style box in the order shadow, background or glass, border, then inset shadow. A uniform border with corner radii is one `Shape_Kind.Border` quad on a shaped backend and a rounded CPU ring otherwise. A border whose sides have different colours is four strips that follow the rounded outline, with each corner arc split at 45 degrees between its two sides so no strip leaves the outline. A border with no radii keeps four rectangles.

The checkbox square, the tooltip, the floating overlay plate and the focus ring all use the same helper. The focus ring is a two-pixel border with the widget's radii increased by one. A draggable panel's header and the tab-container bar are drawn as the rounded top of the widget into a rectangular clip, so their top corners cannot stick out of the panel. The tooltip is the exception to the widget box: its widget keeps a full-window rectangle at the root, so it draws no box of its own and its kind paints the plate at the pointer.

An outer shadow expands the box silhouette by `shadow_spread`, grows its radii by the same amount, and uses a quad larger again by the blur; a positive softness in the vertex is the blur. An inset shadow uses the box inside the border widths, a negative softness of `-blur`, and `{spread, offset x, offset y, 0}` in the border field; it is drawn after the border and before the content. Without a shaped backend, an outer shadow is a capped stack of four grown silhouettes and an inset shadow a stack of three rounded rings.

`src/GUI/Core/shape_sdf.odin` holds the signed distance and coverage helpers that the software backend shares with the tests.

### 5.9 Scissored Replay

A frame that changed only a look, not the geometry, carries a dirty rectangle in its draw list. The GPU backend keeps the previous frame's scene texture and starts the pass with `load_op = .LOAD` and the scissor set to that rectangle, then replays the whole retained command stream with the scissor applied. Every command is drawn, so the background under the rectangle is painted again and the old glass there is replaced, but only pixels inside the rectangle are written. Each glass group captures the backdrop as usual: the scene holds fresh content inside the rectangle and previous content outside it, so the mip chain stays valid, and the glass itself is drawn scissored too. The scene is then blitted to the swapchain and the cache is marked valid for the new revision.

The replay is refused when the rectangle is empty or covers more than a third of the window, when the change carried `Measure`, `Arrange`, `Theme` or `Hit`, when the root background is not opaque, when the list contains a glass surface, or when a resize or expose dropped the scene cache. The glass rule keeps the picture clean: outside the rectangle the scene still holds the previous frame's composite, not the content under it, so a scissored capture would blur the old glass into the new. The software backend mirrors the rule: `software_draw_into` takes the rectangle, rasterises only the pixels inside it and leaves the rest of the buffer alone, which the partial redraw test asserts bit for bit.

`Backend.Stats` counts the scene writes (`full_updates`, `partial_updates`, `scene_updates`), the captures and their mip chains (`backdrop_blits`, `mip_generations`), the estimated cost of the glass (`glass_taps`) and the wake timers the last frame armed (`wake_timers`).

## 6. Layout Engine

Layout is implemented in `src/GUI/Core/layout.odin` and runs in two stages:

1. **Measurement** — determine the minimum size each widget needs.
2. **Arrangement** — assign final rectangles and lay out descendants.

The engine is incremental: changes invalidate specific layout state, so unaffected branches keep their cached results.

### 6.1 Invalidation

Flags are defined in `src/GUI/Core/invalidation.odin`.

| Flag | Meaning |
|---|---|
| `Measure` | The widget's measured size is stale. |
| `Arrange` | The widget's assigned geometry is stale. |
| `Visual` | The widget's rendered appearance is stale. |
| `Hit` | The widget's hit-test geometry or state is stale. |
| `Theme` | The widget's theme-derived styling is stale. |

Invalidation propagates where dependencies require it: a changed measured size also invalidates arrangement and hit testing, and a changed arrangement invalidates hit testing.

Each widget tracks its own invalidation state and an aggregate for its descendants, and the layout passes use the aggregate to skip unaffected branches.

Setters in `src/GUI/Core/setter.odin` are the preferred way to modify widget properties:

```odin
GUI.Widget_Set_Text(g, label, "Updated text")
GUI.Widget_Set_Visible(g, panel, false)
GUI.Widget_Set_Style(g, button, style)
GUI.Widget_Set_Offsets(g, bar, offsets)
```

They apply the matching invalidation. Widget fields are directly accessible, so callers that write fields themselves must invalidate the corresponding state. `GUI_Invalidate_All` is the full-tree fallback when the affected dependencies are not known; `GUI_Invalidate_Theme` invalidates theme-derived styling.

### 6.2 Measurement

`measure_pass` determines each widget's minimum size. The measured size accounts for:

- The widget's base minimum size.
- Text dimensions.
- Style padding.
- The custom minimum size set by the program.
- Widget-specific measurement behaviour.

Text dimensions use the same layout as drawing, so transformed text reserves space for its transformed dimensions, and wrapped text accounts for its available width and word boundaries.

Widgets that hold collections may derive their size from their contents: a combo box or tree can account for the width of its entries, and scrollable content can extend beyond the visible viewport.

A scroll container keeps its viewport size, content size and scroll offset separately. Content size comes from the measurement pass: a container child reports the sum of its children, a nested container keeps its intrinsic size, and a width-dependent container is measured at the width it asks for. A child that changes invalidates the kept content size. A virtualized child reports a logical content size through the `content_size` kind hook, so the scroll bars can describe content that was never built as widgets.

Text measurements are cached in `g.measure_cache` and reused until their relevant inputs change, so measurement follows invalidation instead of reshaping every widget every frame.

### 6.3 Arrangement

`layout_node` assigns a widget its final rectangle and calculates its clipping rectangle, which is the intersection of its own bounds and the clip inherited from its parent.

Container widgets arrange their children by their layout rules; other widgets use their anchors and offsets. When a widget's geometry, clipping and descendants are still valid, the engine skips the work.

### 6.4 Anchors and Offsets

Widgets position themselves against their parent with four anchors and four offsets.

```odin
Anchor :: struct {
    left, top, right, bottom: f32
}

Offset :: struct {
    left, top, right, bottom: f32
}
```

Anchors are normalized fractions of the parent bounds; offsets are in UI units. `resolve_rect` combines them into the final rectangle.

Predefined presets:

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

`Fill` is the default. Raw anchor values are used when `.Custom` is selected.

Widgets that grow beyond their minimum size follow the configured grow direction, which defaults to right and down.

### 6.5 Containers

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

Nested containers combine into complex layouts.

Box containers start every child at its preferred size, then distribute the leftover room by weight among the children that expand. A child that reaches its maximum stops growing, and the room it did not take is shared again among the children that can still grow. When the children do not fit, the children with a shrink weight give room back by weight until they reach their floor. `w.separation` controls the spacing and defaults to 4.

### 6.6 Sizing and Space Allocation

Along one axis a widget is described by a `Layout_Constraint` with three sizes: the floor a shrink may reach, the preferred size from the measurement pass, and the maximum a grow may reach. The constraint is normalized so that `minimum <= preferred <= maximum`, and a maximum of 0 means there is no maximum. `GUI.Widget_Layout_Constraint` reports the constraint of a widget after a measure pass.

| Property | Field | Behaviour |
|---|---|---|
| Preferred size | `w.min_size` | Size determined by measurement. |
| Custom minimum | `w.custom_min_size` | Additional floor requested by the program. |
| Custom maximum | `w.custom_max_size` | Upper size constraint; 0 means no maximum. |
| Fixed sizing | `opts.fixed` | Keeps the widget at its preferred size rather than sharing surplus space. |
| Stretch weight | `w.weight` | Determines the widget's share of available surplus space. |
| Shrink weight | `w.shrink_weight` | Determines the widget's share of a deficit when the children do not fit. |
| Absolute | `w.absolute` | Takes the widget out of the flow of its container and places it by its anchors and offsets. |
| Manual sizing | `w.manual_size`, `w.manual_w`, `w.manual_h` | Stores manually adjusted panel dimensions. |

A weight of zero means the widget receives no share of surplus space. A shrink weight of zero means the widget keeps its preferred size and the container overflows, which is the behaviour before shrink weights were added.

Manual panel sizes are preserved during layout and deducted from the space available to other children. An absolute child takes no share of its container's room and does not move the cursor that places the other children; the built-in containers place it by its anchors and offsets after the children in the flow.

Inactive tab pages keep no visible geometry and are neither drawn nor hit-tested.

## 7. Input and Interaction

Events are defined in `src/GUI/Core/events.odin`. `GUI.Event` is platform-independent input: mouse movement and buttons, mouse wheel, keyboard, text input and IME composition, and window resize and quit events.

Mouse events carry two positions: `pos` relative to the originating window and `global` relative to the screen. The distinction matters for floating panels, which may sit outside the main window.

The Window layer translates platform input into CalcUI events, places them in `g.events`, and `GUI.Handle_Events` processes them. The queue is detached before processing, so events added by callbacks during dispatch are handled in the next event-processing pass.

### 7.1 Hit Testing and Event Routing

`collect_hits` gathers the widgets under a pointer position, topmost first. Children rank above their parents, and sibling ordering accounts for `z_index`.

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

`hit_test` returns the topmost eligible widget. `hits_that_take_the_mouse` builds the complete eligible hit list, and dispatch proceeds through it until a widget stops propagation or marks the event handled.

Disabled widgets take no pointer interaction, so eligible widgets behind them are considered.

### 7.2 Focus

A widget can take keyboard focus when its `focus_mode` permits it and it is visible and enabled. `focus_set` transfers focus and emits the appropriate focus signals. Focus is cleared when a widget becomes hidden, disabled, destroyed or detached from the tree.

Tab navigation orders widgets by `tab_index`, with tree order breaking ties; only widgets using `.All` participate. Directional navigation uses explicit `focus_neighbour` relationships first, then spatial position.

### 7.3 Signals

Signals are implemented in `src/GUI/Core/signal.odin`. Widgets share a common signal interface, so applications connect to widget events without depending on the concrete widget type. Unconnected signals are `nil`, so emitting one needs only a nil check.

The available signals are documented in [`docs/widgets.md`](widgets.md).

## 8. Widget Extensibility

Custom widget behaviour goes through the kind registry in `src/GUI/Core/kinds.odin`. Built-in widgets may use dedicated dispatch paths in the core; the registry adds widget-specific behaviour without more cases in shared rendering, layout and input code.

### 8.1 Widget Kind

A `Widget_Kind` holds the callbacks and defaults of a widget type.

```odin
Widget_Kind :: struct {
    draw:       proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect),
    layout:     proc(g: ^GUI, id: Widget_ID, w: ^Widget, rect: Rect),
    click:      proc(g: ^GUI, id: Widget_ID, w: ^Widget),
    key:        proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Key_Down_Event),
    update:      proc(g: ^GUI, id: Widget_ID, w: ^Widget, dt: f32),
    post_update: proc(g: ^GUI, id: Widget_ID, w: ^Widget, dt: f32),
    style:       Style,
    theme_name:  string,
}
```

The callbacks provide drawing, layout, click, keyboard and per-frame update behaviour (`update` before layout, `post_update` after it); style and theme name provide default presentation.

Register a kind with `kind_register`:

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

| Operation | Location | Callback |
|---|---|---|
| Drawing | `src/GUI/Core/draw_build.odin` | `kind.draw` |
| Layout | `src/GUI/Core/layout.odin` | `kind.layout` |
| Click handling | `src/GUI/Core/input.odin` | `kind.click` |
| Keyboard handling | `src/GUI/Core/input.odin` | `kind.key` |
| Per-frame state update | `src/GUI/Core/update.odin`, before layout | `kind.update` |
| Per-frame interaction update | `src/GUI/Core/update.odin`, after layout | `kind.post_update` |

Custom widgets must invalidate the matching state whenever they change data that affects layout, rendering or hit testing:

```odin
invalidate(g, id, Dirty_Flags{.Measure, .Visual})
```

The extension requirements and recommended patterns are documented in [`docs/extending.md`](extending.md).

### 8.3 Scene Constructor Registry

The kind registry defines how a widget behaves; the scene constructor registry defines how a scene file creates an instance of it.

`Scene_Register_Constructor` registers a constructor for a widget type. The constructor table belongs to the individual GUI instance, so registrations are isolated between instances.

During scene loading, CalcUI resolves custom classes and registered widget constructors to create the requested nodes. `Image` and `ScrollArea` have no built-in constructor, so those nodes cannot be instantiated through the registry. Unsupported node types are reported as loader errors rather than silently instantiated.

The scene format and loading behaviour are documented in [`docs/scene-format.md`](scene-format.md).

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

Arena allocations are not automatically zeroed, so `New_Widget` initializes new widgets to a clean state.

Widgets with substantial dynamic data keep it outside the widget struct — virtual-list data, table storage, node-graph state, canvas contents.

### 9.2 Fonts

Font resources are tracked through three collections: `g.font_files` (parsed font files), `g.font_families` (families and fallback relationships) and `g.fonts` (instances configured for specific sizes). The instance cache is keyed by font file and requested size, so instances are reused.

### 9.3 Themes

The active theme is stored in `g.theme`. `GUI_Set_Theme` replaces it and releases the previous one; the active theme is released during GUI shutdown.

### 9.4 Ownership Rules

CalcUI distinguishes borrowed strings, individually owned allocations and arena-owned data:

- **Individually owned strings** are cloned with `strings.clone` and released with `delete`.
- **GUI-lifetime data** is allocated through `virt.arena_allocator(&g.arena)` and reclaimed when the GUI shuts down.
- **Borrowed strings** stay owned by the application, which must keep them alive for as long as CalcUI references them.

`widget_release_data` releases individually owned resources but never frees allocations belonging to the GUI arena. Text-editing widgets own their editable buffers; labels and other simple display widgets may reference application-owned strings.

Widget destruction releases that widget's resources. `Shutdown_GUI` releases the resources of remaining widgets and the GUI itself.

## 10. Testing and Benchmarks

GUI tests use a headless backend and need no window or physical display. They build a GUI instance, perform operations and inspect the resulting state and draw data.

### 10.1 Test Helpers

`src/Tests/test_helpers.odin` holds the shared helpers:

```odin
test_gui :: proc(t: ^testing.T) -> ^GUI.GUI
```

`test_gui_destroy` tears down the test GUI and releases its resources. The mock backend records texture uploads, so tests can verify atlas behaviour without a real renderer.

### 10.2 Test Organization

| File | Coverage |
|---|---|
| `allocation_test.odin` | Allocation-free hot paths. |
| `animation_test.odin` | Tween system: easing, values, and tween lifecycle. |
| `animation_integration_test.odin` | Frame animation ordering and invalidation. |
| `class_test.odin` | Reference custom widget through the public API. |
| `draw_shape_test.odin` | Rounded shapes in the draw list. |
| `draw_reuse_test.odin` | Draw-list retention, rebuild triggers, and atlas region protection. |
| `font_test.odin` | Glyph positioning, atlas caching, and pixel alignment. |
| `frame_lifecycle_test.odin` | Update and post-update ordering, including destruction from a hook. |
| `layout_solver_test.odin` | Layout constraints, box growth and shrink, and absolute children. |
| `measure_intrinsic_test.odin` | Intrinsic measurement of containers. |
| `measure_width_test.odin` | Height-for-width measurement. |
| `scroll_content_test.odin` | Scroll viewport, content size, and offset. |
| `scroll_wheel_test.odin` | Wheel consumption by scrollable widgets. |
| `text_undo_test.odin` | Text undo, redo, and caret blink. |
| `widget_gizmo_test.odin` | Gizmo handles, dragging, snapping, keyboard and scene loading. |
| `widget_node_graph_test.odin` | Node graph interaction and view. |

### 10.3 Benchmarks

`src/Tests/bench_test.odin` benchmarks draw-list construction (including text and rounded boxes), frame construction, style and colour processing, layout, atlas operations, and virtualized list and data-table drawing. Results are reported through the test output.

Run the tests and checks with:

```sh
odin check src/Tests -no-entry-point
odin test src/Tests
```

Odin tests may run concurrently, which adds measurement noise. For steadier benchmark results:

```sh
odin test src/Tests -o:speed -define:ODIN_TEST_THREADS=1
```
