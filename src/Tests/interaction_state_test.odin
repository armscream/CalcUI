//* The essential tests of interaction: widgets take the hover and pressed
//* states only when they are interactive, and a button clicks.

package Tests

import GUI "../GUI"
import "core:testing"

INTERACTION_PANEL_NORMAL :: GUI.Colour{r = 0.2, g = 0.2, b = 0.2, a = 1}
INTERACTION_PANEL_HOVER :: GUI.Colour{r = 0.6, g = 0.6, b = 0.6, a = 1}
INTERACTION_PANEL_PRESSED :: GUI.Colour{r = 0.4, g = 0.4, b = 0.4, a = 1}
INTERACTION_BUTTON_NORMAL :: GUI.Colour{r = 0.1, g = 0.2, b = 0.3, a = 1}
INTERACTION_BUTTON_HOVER :: GUI.Colour{r = 0.2, g = 0.4, b = 0.6, a = 1}
INTERACTION_BUTTON_PRESSED :: GUI.Colour{r = 0.3, g = 0.6, b = 0.9, a = 1}

interaction_button_clicks: int

interaction_button_pressed :: proc(g: ^GUI.GUI, id: GUI.Widget_ID) {
	interaction_button_clicks += 1
}

interaction_gui :: proc(t: ^testing.T) -> ^GUI.GUI {
	g := test_gui_with_font(t)

	theme := GUI.Theme_Make()
	GUI.Theme_Set_Type(
		theme,
		.Panel,
		GUI.Style {
			box = GUI.StyleBox{bg_color = INTERACTION_PANEL_NORMAL},
			text = GUI.Text_Style{colour = INTERACTION_PANEL_NORMAL},
		},
	)
	GUI.Theme_Set_Type(
		theme,
		.Button,
		GUI.Style {
			box = GUI.StyleBox{bg_color = INTERACTION_BUTTON_NORMAL},
			text = GUI.Text_Style{colour = INTERACTION_BUTTON_NORMAL},
		},
	)
	GUI.Theme_Set_State(
		theme,
		.Button,
		.Hovered,
		GUI.Style{box = GUI.StyleBox{bg_color = INTERACTION_BUTTON_HOVER}},
	)
	GUI.Theme_Set_State(
		theme,
		.Button,
		.Pressed,
		GUI.Style{box = GUI.StyleBox{bg_color = INTERACTION_BUTTON_PRESSED}},
	)
	GUI.GUI_Set_Theme(g, theme)

	interaction_button_clicks = 0
	return g
}

interaction_panel :: proc(
	g: ^GUI.GUI,
	parent: GUI.Widget_ID,
	name: string,
	offset: GUI.Offset,
) -> GUI.Widget_ID {
	return GUI.Make_Panel(
		g,
		parent,
		GUI.Panel_Opts{Base_Opts = GUI.Base_Opts{
			name = name,
			preset = .Top_Left,
			offsets = offset,
			use_theme = true,
		}},
	)
}

interaction_button :: proc(
	g: ^GUI.GUI,
	parent: GUI.Widget_ID,
	name: string,
	offset: GUI.Offset,
	on_pressed: proc(g: ^GUI.GUI, id: GUI.Widget_ID),
) -> GUI.Widget_ID {
	return GUI.Make_Button(
		g,
		parent,
		GUI.Button_Opts {
			Base_Opts = GUI.Base_Opts{
				name = name,
				preset = .Top_Left,
				offsets = offset,
				min_size = {80, 30},
				use_theme = true,
			},
			text = "Press",
			on_pressed = on_pressed,
		},
	)
}

@(test)
test_a_panel_does_not_take_the_hover_or_pressed_state :: proc(t: ^testing.T) {
	g := interaction_gui(t)
	defer test_gui_destroy(g)

	panel := interaction_panel(g, g.root, "panel", test_offset(10, 10, 210, 110))
	GUI.layout_pass(g)
	w := GUI.Widget_Get(g, panel)
	testing.expect(t, w != nil)
	if w == nil {return}

	testing.expect_value(t, w.interactive, false)
	testing.expect_value(t, GUI.Widget_Background(g, panel), INTERACTION_PANEL_NORMAL)

	append(&g.events, mouse_move({60, 60}))
	GUI.Handle_Events(g)
	testing.expect(t, .Hovered not_in w.state)
	testing.expect_value(t, GUI.Widget_Background(g, panel), INTERACTION_PANEL_NORMAL)

	append(&g.events, mouse_down({60, 60}))
	GUI.Handle_Events(g)
	testing.expect(t, .Pressed not_in w.state)
	testing.expect_value(t, GUI.Widget_Background(g, panel), INTERACTION_PANEL_NORMAL)

	append(&g.events, mouse_up({60, 60}))
	GUI.Handle_Events(g)
	testing.expect(t, .Hovered not_in w.state)
	testing.expect_value(t, GUI.Widget_Background(g, panel), INTERACTION_PANEL_NORMAL)
}

@(test)
test_a_button_takes_the_hover_and_pressed_state_and_clicks :: proc(t: ^testing.T) {
	g := interaction_gui(t)
	defer test_gui_destroy(g)

	button := interaction_button(g, g.root, "button", test_offset(10, 10, 210, 110), interaction_button_pressed)
	GUI.layout_pass(g)
	w := GUI.Widget_Get(g, button)
	testing.expect(t, w != nil)
	if w == nil {return}

	testing.expect_value(t, w.interactive, true)
	testing.expect_value(t, GUI.Widget_Background(g, button), INTERACTION_BUTTON_NORMAL)

	append(&g.events, mouse_move({60, 60}))
	GUI.Handle_Events(g)
	testing.expect(t, .Hovered in w.state)
	testing.expect_value(t, GUI.Widget_Background(g, button), INTERACTION_BUTTON_HOVER)

	append(&g.events, mouse_down({60, 60}))
	GUI.Handle_Events(g)
	testing.expect(t, .Pressed in w.state)
	testing.expect_value(t, GUI.Widget_Background(g, button), INTERACTION_BUTTON_PRESSED)

	append(&g.events, mouse_up({60, 60}))
	GUI.Handle_Events(g)
	testing.expect(t, .Pressed not_in w.state)
	testing.expect_value(t, GUI.Widget_Background(g, button), INTERACTION_BUTTON_HOVER)
	testing.expect_value(t, interaction_button_clicks, 1)
}
