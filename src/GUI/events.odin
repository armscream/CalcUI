//* The events the window layer hands to the GUI: the pointer, the keys, the
//* text that was typed and the size of the window.
//* A position is given twice: once in the window of the GUI and once on the
//* screen.
package GUI

Mouse_Button :: enum { Left, Middle, Right }

//* Ordered so letters and digits can be mapped arithmetically from the
//* platform's key codes.
Key :: enum {
	None,
	A, B, C, D, E, F, G, H, I, J, K, L, M,
	N, O, P, Q, R, S, T, U, V, W, X, Y, Z,
	Digit0, Digit1, Digit2, Digit3, Digit4,
	Digit5, Digit6, Digit7, Digit8, Digit9,
	Space, Enter, Escape, Tab, Backspace, Delete,
	Left, Right, Up, Down, Home, End,
	Page_Up, Page_Down,
}

Mod :: enum { Shift, Ctrl, Alt }
Mods :: bit_set[Mod]

Mouse_Down_Event :: struct {
	pos:    Vec2,
	global: Vec2,
	button: Mouse_Button,
	clicks: int, // 1 for a single click, 2 for a double click
}

Mouse_Up_Event :: struct {
	pos:    Vec2,
	global: Vec2,
	button: Mouse_Button,
}

Mouse_Move_Event :: struct {
	pos:    Vec2,
	global: Vec2,
}

Wheel_Event :: struct {
	amount: f32,
}

Key_Down_Event :: struct {
	key:    Key,
	mods:   Mods,
	repeat: bool,
}

Key_Up_Event :: struct {
	key:  Key,
	mods: Mods,
}

//* A character was typed. The producer allocates `text` with the heap
//* allocator; the core frees it once it has been handled.
Text_Input_Event :: struct {
	text: string,
}

//* An IME composition in progress. The text is the pre-edit string.
Ime_Editing_Event :: struct {
	text:  string,
	start: int,
	length: int,
}

Resized_Event :: struct {
	size: Vec2,
}

Quit_Event :: struct {}

Event :: union {
	Mouse_Down_Event,
	Mouse_Up_Event,
	Mouse_Move_Event,
	Wheel_Event,
	Key_Down_Event,
	Key_Up_Event,
	Text_Input_Event,
	Ime_Editing_Event,
	Resized_Event,
	Quit_Event,
}
