# CalcUI

[![Tests](https://github.com/armscream/CalcUI/actions/workflows/test.yml/badge.svg)](https://github.com/armscream/CalcUI/actions/workflows/test.yml)
[![License](https://img.shields.io/badge/license-LGPL--3.0-blue)](LICENSE)
[![Language](https://img.shields.io/badge/language-Odin-orange)](https://odin-lang.org/)
[![Sponsor](https://img.shields.io/badge/Sponsor-GitHub%20Sponsors-pink?logo=github-sponsors)](https://github.com/sponsors/armscream)

CalcUI is a retained-mode GUI toolkit written in [Odin](https://odin-lang.org/), built around SDL3 and the [Runa](src/GUI/dependencies/Runa) text engine.

It uses a persistent widget tree with independent widget identities and state. Layout, rendering and input are handled by the toolkit, with support for custom widgets, dockable panels, multiple windows and scene-based interfaces.

Rendering is batched through a shared texture atlas for rectangles, text and images, with clipping handled during draw-list construction.

## Screenshots

<p align="center">
  <img src="assets/calcdock.png" alt="CalcUI docking system" width="100%">
</p>

<p align="center">
  <img src="assets/widgetgallery.png" alt="CalcUI widget gallery" width="100%">
</p>

## Features

- **Retained-mode widget tree** – Persistent widget identities, state and hierarchical layout.
- **Batched rendering** – Shared texture atlas for text, images and primitives.
- **Text rendering** – Font families, glyph fallback, measurement and DPI-aware rasterization.
- **Docking** – Movable panels, split layouts and detachable windows.
- **Widgets** – Buttons, text boxes, sliders, lists, trees, tables, charts, node graphs and more.
- **Custom widgets** – Register custom drawing, measurement, input and lifecycle callbacks.
- **Theming** – Widget styles, default themes and style variations.
- **Scene files** – Load widget trees from serialized scene descriptions.
- **Multiple backends** – SDL3 renderer and SDL3 GPU backends.
- **Headless testing** – Test widget and GUI logic without creating a window.

## Quick Start

```odin
import GUI "calcui/src/GUI"

g := GUI.Init_GUI(width, height, backend)
defer GUI.Shutdown_GUI(g)

family := GUI.Font_Family_Add(g, "Roboto", FONT_DATA)

GUI.Make_Label(g, g.root, GUI.Label_Opts{
    Base_Opts = GUI.Base_Opts{name = "title"},
    text = "Hello, CalcUI",
})

GUI.Make_Button(g, g.root, GUI.Button_Opts{
    Base_Opts = GUI.Base_Opts{name = "ok"},
    text = "OK",
    on_pressed = on_ok,
})
```

`calcui\src\App.odin` is pre-setup and wired to SDL3 for an easy start.  

## Display Scaling

CalcUI uses logical units for widget geometry, padding, borders, font sizes and image dimensions.

The renderer converts these values into physical pixels using `GUI.scale`. Pointer positions and window dimensions are also expressed in logical units.

```odin
g := GUI.Init_GUI(logical_width, logical_height, backend)
GUI.GUI_Set_Scale(g, pixel_density)
```

Call `GUI_Set_Scale` when a window moves between displays with different pixel densities. Glyphs are rasterized again at the new physical size to maintain sharp text.

## Fonts

Font families support fallback chains. When a family does not contain a requested glyph, CalcUI searches its fallback families.

```odin
family := GUI.Font_Family_Add(g, "Roboto", FONT_DATA)
GUI.Font_Family_Set_Fallback(g, family, symbol_family)
```

`GUI.Font_Has_Glyph` checks whether a family or its fallbacks contain a particular codepoint.

## Example widget : Text Boxes

CalcUI uses a single `TextBox` widget for both single-line and multiline input.

Supported features include:

- Caret positioning and text selection.
- Mouse selection, double-click selection and select all.
- Cut, copy and paste.
- Undo and redo.
- Character filtering and length limits.
- Single-line submission callbacks.
- Multiline wrapping, scrolling and indentation.

Input rules are configured per instance.

```odin
GUI.Make_Text_Box(g, g.root, GUI.Text_Box_Opts{
    Base_Opts = GUI.Base_Opts{name = "amount"},
    rules = GUI.Text_Rules{
        max_length = 6,
        allowed = "0123456789",
    },
})
```

Use the `Multiline` flag for multiline input:

```odin
GUI.Make_Text_Box(g, g.root, GUI.Text_Box_Opts{
    Base_Opts = GUI.Base_Opts{name = "notes"},
    flags = GUI.Text_Box_Flags{.Multiline},
    text = "A multiline text box.",
})
```

See [docs/widgets.md](docs/widgets.md) for widget details.

## Custom Widgets

Custom widgets are registered as classes. Each class defines callbacks for drawing, measurement and input, with optional lifecycle and layout hooks.

```odin
class := GUI.Widget_Register_Class(g, GUI.Widget_Class_Desc{
    name = "Gauge",
    kind = GUI.Widget_Kind{
        draw = gauge_draw,
        measure = gauge_measure,
        click = gauge_click,
    },
})

id := GUI.Make_Custom_Widget(
    g,
    parent,
    class,
    GUI.Base_Opts{name = "gauge"},
)
```

Custom classes can also define signals, default styles and scene-file constructors.

See [docs/extending.md](docs/extending.md).

## Examples

The `examples` directory contains standalone applications demonstrating CalcUI's features.

| Example | Description |
|---|---|
| `00_hello` | Basic window, label, button and text field. |
| `01_gallery` | Widget gallery, toolbar, docking and text showcase. |
| `02_docking` | Docking, panel movement and drag-and-drop. |
| `03_text` | Text sizing, colours, alignment and wrapping. |
| `04_overlays` | Detached panels and multiple windows. |
| `05_theming` | Themes and widget styles. |
| `06_data` | Checkboxes, sliders, progress bars, lists and trees. |
| `07_widgets` | Inputs, pickers, chat, tables and command palette. |
| `08_heavy` | Charts, node graphs, canvas and editor widgets. |
| `09_scene` | Scene loading and default themes. |

## Building

CalcUI requires the [Odin compiler](https://odin-lang.org/).

Build the examples:

```sh
# Windows
examples\build.bat

# Linux and macOS
./examples/build.sh
```

Or build an individual example:

```sh
odin build examples/01_gallery -out:gallery.exe
odin run examples/01_gallery
```

The SDL3 renderer is used by default. Pass `--gpu` to use the SDL3 GPU backend:

```sh
odin run examples/01_gallery -- --gpu
```

## Tests

Tests use a headless backend, so GUI logic can be tested without opening a window.

```sh
odin test src/GUI
odin check src/GUI -no-entry-point
```

Tests also run through GitHub Actions on pushes and pull requests.

## Project Structure

| Directory | Description |
|---|---|
| `src/GUI` | Widget tree, layout, rendering, text, atlas and themes. |
| `src/Backend` | SDL3 renderer and SDL3 GPU backends. |
| `src/Window` | Window management, events, popups, cursor and clipboard. |
| `examples` | Example applications. |
| `assets` | Fonts, images and other example assets. |
| `tools` | Development tools, shaders and frame capture utilities. |

## Documentation

| Document | Description |
|---|---|
| [docs/Usage.md](docs/Usage.md) | Getting started and API overview. |
| [docs/widgets.md](docs/widgets.md) | Widget behaviour and available options. |
| [docs/extending.md](docs/extending.md) | Creating custom widgets. |
| [docs/scene-format.md](docs/scene-format.md) | Scene format and loading. |

## Shaders

Compiled shaders are included in the repository, so a shader compiler is not needed to build CalcUI.

To rebuild them:

```sh
# Windows
src\Backend\build_shaders.bat

# Linux and macOS
src/Backend/build_shaders.sh
```

Shader compilation requires `glslc`, available through the Vulkan SDK.

## License

CalcUI is licensed under [LGPL-3.0](LICENSE).

Third-party components retain their respective licenses:

- SDL3 and Runa: zlib.
- Ported Skald code: BSD-2-Clause.

See [NOTICE](NOTICE) for third-party attributions.