# Using CalcUI

CalcUI is a retained-mode GUI toolkit. Your application owns the window, clock, and renderer. CalcUI manages the widget tree, layout, draw lists, and wake timers.

## Getting Started

Initialize CalcUI with a window size and rendering backend:

```odin
g := GUI.Init_GUI(width, height, backend)
defer GUI.Shutdown_GUI(g)
```

Create widgets under a parent using `Make_*` helpers. The root widget is `g.root`.

```odin
GUI.Make_Label(g, g.root, GUI.Label_Opts{
    Base_Opts = GUI.Base_Opts{name = "title"},
    text = "Hello, CalcUI",
})
```

## Application Loop

CalcUI does not read the system clock. Your application supplies elapsed time through `GUI_Tick` on every loop pass, including when no frame is drawn.

```odin
loop {
    GUI.GUI_Tick(g, my_clock.delta())
    GUI.Handle_Events(g)

    if GUI.GUI_Needs_Frame(g) {
        GUI.Frame(g)
        render(g)
    } else {
        wait_for_events(GUI.GUI_Next_Frame_Delay_MS(g))
    }
}
```

`GUI.Handle_Events` processes events queued by the window layer.

The shared application loop is implemented in `src/App/app.odin`:

- `App.Run` provides an update callback that runs before frame construction.
- `Core.App_Run` manages the loop and clock.
- `src/Platform` provides SDL3 clock and event callbacks.

## Frame Scheduling

CalcUI is event-driven. `GUI_Needs_Frame` returns true when work requires a new frame, including:

- An explicit frame request.
- Invalid widget layout or retained draw lists.
- Active animations or style transitions.
- Due wake timers.
- Pending atlas uploads.

Call `GUI_Request_Frame` when application-side changes require a frame but were not detected by CalcUI. Input, resize, and window exposure events request frames automatically.

### Wake Timers

`GUI_Next_Frame_Delay_MS` returns:

| Value | Meaning |
|---|---|
| Positive | Milliseconds until the next wake timer |
| `0` | A timer is due now |
| `-1` | No timer is armed; wait for an event |

Pass this value to your platform's event-wait function to avoid unnecessary polling.

## Continuous Rendering

CalcUI is always event-driven. `Frame_Mode`, `GUI_Set_Frame_Mode`, and `GUI_Frame_Mode` have been removed.

If your application needs continuous rendering, call `GUI.Frame` on every loop pass. Existing code that used `.Continuous` can simply remove the frame-mode setting if its loop already draws every pass.

## See Also

- `architecture.md` — Frame lifecycle, rendering, glass effects, and scissored replay.
- `widgets.md` — Built-in widgets and their options.
- `extending.md` — Custom widgets and classes.
- `scene-format.md` — Scene file format.
