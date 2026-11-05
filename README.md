# CalcUI

[![Tests](https://github.com/armscream/CalcUI/actions/workflows/test.yml/badge.svg)](https://github.com/armscream/CalcUI/actions/workflows/test.yml)
[![License](https://img.shields.io/badge/license-LGPLv3.0-blue)](LICENSE)
[![Language](https://img.shields.io/badge/language-Odin-orange)](https://odin-lang.org/)
[![GitHub](https://img.shields.io/badge/github-repo-blue?logo=github)](https://github.com/armscream/CalcUI)
[![Sponsor](https://img.shields.io/badge/Sponsor-Pink?logo=github-sponsors)](https://github.com/sponsors/armscream)

CalcUI is a retained-mode GUI toolkit written in [Odin](https://odin-lang.org/), built on SDL3 and the [Runa](src/GUI/dependencies/Runa) text engine.

The toolkit uses a persistent widget tree. Widgets have their own identities and state, and can be moved or rearranged without having to rebuild the interface.

Rendering is batched into a single draw call per window. Rectangles, text and images share a texture atlas, with clipping handled during draw-list construction.

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

## Project structure

| Directory | Description |
|---|---|
| `src/GUI` | Core toolkit: widget tree, layout, rendering, text, atlas and themes. Independent of SDL. |
| `src/Backend` | SDL3 renderer and SDL3 GPU backends (Vulkan, D3D12 and Metal). |
| `src/Window` | Window management, events, popups, cursor and clipboard. |
| `examples` | Example applications demonstrating the toolkit. |
| `assets/fonts` | Fonts used by the examples. |
| `tools` | Development tools, shaders and frame capture utilities. |

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
odin build examples\01_gallery -out:gallery.exe
odin run examples\01_gallery
```

The SDL3 renderer is used by default. Pass `--gpu` to use the SDL3 GPU backend:

```sh
odin run examples\01_gallery -- --gpu
```

## Tests

The tests use a headless backend, allowing the widget tree and GUI logic to be tested without opening a window.

```sh
odin test src\GUI
odin check src\GUI -no-entry-point
```

## Custom widgets

Custom widgets are registered as classes. A class defines the callbacks used for drawing, measurement and input, along with optional lifecycle and layout hooks.

Register a class with `Widget_Register_Class`, then create instances with `Make_Custom_Widget`:

```odin
class := GUI.Widget_Register_Class(g, GUI.Widget_Class_Desc{
    name = "Gauge",
    kind = GUI.Widget_Kind{
        draw    = gauge_draw,
        measure = gauge_measure,
        click   = gauge_click,
    },
})

id := GUI.Make_Custom_Widget(
    g,
    parent,
    class,
    GUI.Base_Opts{name = "gauge"},
)
```

Custom widgets can also define signals and default styles, and can be used in scene files when a constructor is registered.

See [docs/extending.md](docs/extending.md) for details.

## Examples

| Example | Description |
|---|---|
| `00_hello` | Basic window with a label, button and text field. |
| `01_gallery` | Widget gallery, toolbar, dockable panels and text showcase. |
| `02_docking` | Docking panels with title bars and drag-and-drop support. |
| `03_text` | Text sizing, colours, alignment and wrapping. |
| `04_overlays` | Detached panels displayed in separate windows. |
| `05_theming` | Themes, widget styles and style variations. |
| `06_data` | Checkboxes, sliders, progress bars, lists and trees. |
| `07_widgets` | Combo boxes, search fields, number inputs, date and time pickers, chat, tables, toasts and command palette. |
| `08_heavy` | Charts, node graphs, canvas, drawing, file viewer and editor widgets. |
| `09_scene` | Loading widget trees from scene files and applying a default theme. |

Some examples may not be included in the current repository state.

## Documentation

| Document | Description |
|---|---|
| [docs/Usage.md](docs/Usage.md) | Basic toolkit usage and API overview. |
| [docs/extending.md](docs/extending.md) | Creating and registering custom widgets. |
| [docs/scene-format.md](docs/scene-format.md) | Scene file format and loading. |

## Shaders

The GPU backend uses shaders for rendering, including rounded rectangle clipping.

Compiled shader files are included in the repository, so building CalcUI does not require a shader compiler.

To rebuild the shaders:

```sh
# Windows
src\Backend\build_shaders.bat

# Linux and macOS
src/Backend/build_shaders.sh
```

Shader compilation requires `glslc`, included with the Vulkan SDK.

## License

CalcUI is licensed under LGPL-3.0.

SDL and Runa are licensed under zlib. Code ported from Skald is licensed under BSD-2-Clause, with attribution included in the relevant source files.

See [NOTICE](NOTICE) for third-party notices.