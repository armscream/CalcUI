//* == The caret that flashes ==
//* The caret of a widget that has the keyboard flashes: it is there for
//* a moment and it is gone for a moment. The time of the flash is kept
//* in the GUI, and it starts again every time that something is typed or
//* that the caret moves, so that the caret is there while the person is
//* typing.
//*
//* The widgets that hold text ask whether the caret is to be shown before
//* they draw it, and the GUI tells them when the flash is over.

package GUI

import "core:math"

//* The time the caret is there, and the time it is gone.
CARET_BLINK_PERIOD :: 0.5

//* Starts the flash of the caret again: the caret is there at once.
caret_reset :: proc(g: ^GUI) {
	if g == nil {return}
	g.caret_timer = 0
}

//* Whether the caret is to be shown at this moment.
caret_visible :: proc(g: ^GUI) -> bool {
	if g == nil {return true}
	period := f32(CARET_BLINK_PERIOD)
	if g.caret_timer < period {return true}
	cycle := math.floor(g.caret_timer / (period * 2))
	phase := g.caret_timer - cycle * (period * 2)
	return phase < period
}

//* The flash of the caret goes on while a widget that holds text has the
//* keyboard. When no widget has the keyboard, there is no caret to
//* flash, and the time of the flash starts again when a widget takes
//* the keyboard.
caret_tick :: proc(g: ^GUI) {
	if g == nil {return}
	if !widget_takes_text(g, g.focused) {
		g.caret_timer = 0
		return
	}
	g.caret_timer += g.dt
}
