# CalcUI

A GUI toolkit for [Odin](https://odin-lang.org/), built on SDL3 and the
[Runa](src/GUI/dependencies/Runa) text engine.

CalcUI is a *retained* mode GUI toolkit: a program builds a tree of widgets and keeps it. The widgets have their own identity, so a thing that happens to a widget can be found again, and the tree can be rearranged without losing anything.

The whole of a window is drawn in a single draw call. Everything the GUI
draws — the solid rectangles, the glyphs of every font, the images —
comes out of one atlas, and the clip is worked out while the draw list
is built. One texture and one command.

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

## The parts

| Directory | What is in it |
|---|---|
| `src/GUI` | The toolkit itself: the widget tree, the layout, the draw pass, the text, the atlas, the theme. It knows nothing about SDL. |
| `src/Backend` | The two backends: the SDL3 renderer and the SDL3 GPU (Vulkan, D3D12, Metal). |
| `src/Window` | The window: the events, the popups, the cursor, the clipboard. |
| `examples` | The examples, one directory each. |
| `assets/fonts` | The typeface the examples use. |
| `tools` | The small tools: the shaders, the picture of one frame. |

## Building

The examples are built with [the Odin compiler](https://odin-lang.org/):

```
examples\build.bat          # on Windows
./examples/build.sh         # on Linux and macOS
```

or one at a time:

```
odin build examples\01_gallery -out:gallery.exe
odin run examples\01_gallery
```

The GPU backend is chosen with `--gpu`; without it the SDL3 renderer is
used:

```
odin run examples\01_gallery -- --gpu
```

## Tests

The toolkit has no window and no screen in its tests: they build a GUI
with a backend that does nothing, and look at what comes out.

```
odin test src\GUI
odin check src\GUI -no-entry-point
```

## A widget of your own

Every widget belongs to a *class*: the hooks that say how it is drawn,
how big it is, what it does with the mouse and the keyboard. A program registers a class of its own and makes its widgets with it, and nothing outside the class has to be changed for the widget to work:

```odin
class := GUI.Widget_Register_Class(g, GUI.Widget_Class_Desc{
	name = "Gauge",
	kind = GUI.Widget_Kind{
		draw    = gauge_draw,
		measure = gauge_measure,
		click   = gauge_click,
	},
})

id := GUI.Make_Custom_Widget(g, parent, class, GUI.Base_Opts{name = "gauge"})
```

See [docs/extending.md](docs/extending.md).

## Examples

| Example | What it shows |
|---|---|
| `00_hello` | The smallest program: a label, a button and a text field. |
| `01_gallery` | The whole toolkit: a toolbar, panels that can be docked into each other, and a showcase of the text. |
| `02_docking` | Two panels with title bars, and the dragging that docks them. |
| `03_text` | The sizes, the colours, the alignment and the wrapping of the text. |
| `04_overlays` | A panel that is torn out of the tree and gets a window of its own. |
| `05_theming` | A theme: the look of a kind of widget, and a variation of it. |
| `06_data` | The widgets that hold data: a check box, a slider, a progress bar, a list and a tree. |
| `07_widgets` | The widgets Godot does not have: the combo box, the search field, the number input, the date and the time pickers, the chat, the table, the toast and the command palette. |
| `08_heavy` | The heavy features: the chart, the node graph, the canvas, the drawing, the file viewer and the editor. |
| `09_scene` | A program that puts its widgets in a scene file, and the default theme that gives them a look. |

## The docs

| Document | What is in it |
|---|---|
| [docs/architecture.md](docs/architecture.md) | How the toolkit is put together: the tree, the frame, the atlas, the layout, the input. |
| [docs/widgets.md](docs/widgets.md) | Every widget, what it does and how a program uses it. |
| [docs/extending.md](docs/extending.md) | How a program brings a widget of its own: the class, the hooks, the signals and the theme. |
| [docs/theme.md](docs/theme.md) | The look of the widgets: the style, the style box, the theme and the default theme. |
| [docs/scene-format.md](docs/scene-format.md) | The scene file: the tree of nodes, the anchors, the styles and the signals. |
| [docs/phases-4-6.md](docs/phases-4-6.md) | The plan of the phases that are now done. |

## Shaders

The GPU backend draws with a shader that cuts the rounded corners of a
rectangle. The shader is compiled ahead of time, and the compiled file
is kept in the repository, so a build needs nothing but the compiler:

```
src\Backend\build_shaders.bat
src\Backend/build_shaders.sh
```

The script needs `glslc`, which comes with the Vulkan SDK.

## License

CalcUI is under the zlib licence, like SDL3 and Runa. The parts that
were ported from Skald are under the BSD 2-Clause licence and say so at
the top of the file. See `NOTICE`.
