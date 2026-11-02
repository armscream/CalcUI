//* Tests for the font family/size split and for the theme.
package GUI

import "core:testing"

FONT_PATH :: "assets/fonts/Roboto-Regular.ttf"

//* == Fonts ==

@(test)
test_font_family_serves_every_size :: proc(t: ^testing.T) {
	g := test_gui(t)

	family := font_family_load(g, FONT_PATH)
	testing.expect_value(t, family != INVALID_FONT_FAMILY_ID, true)

	small := font_at(g, family, 16)
	large := font_at(g, family, 32)
	testing.expect_value(t, small != INVALID_FONT_ID, true)
	testing.expect_value(t, large != INVALID_FONT_ID, true)
	testing.expect_value(t, small != large, true)

	//* One parsed file, two size instances, one atlas.
	testing.expect_value(t, len(g.font_files), 1)
	testing.expect_value(t, len(g.font_families), 1)
	testing.expect_value(t, len(g.fonts), 2)
	testing.expect_value(t, font_get(g, small).file == font_get(g, large).file, true)

	test_gui_destroy(g)
}

@(test)
test_font_instance_is_cached :: proc(t: ^testing.T) {
	g := test_gui(t)
	family := font_family_load(g, FONT_PATH)

	a := font_at(g, family, 16)
	b := font_at(g, family, 16)
	testing.expect_value(t, a, b)

	//* The size is rounded to a half pixel, so a size that moves a
	//* little does not make a new font.
	c := font_at(g, family, 16.2)
	testing.expect_value(t, c, a)

	//* Half a pixel more is a different size.
	d := font_at(g, family, 16.6)
	testing.expect_value(t, d != a, true)

	test_gui_destroy(g)
}

@(test)
test_font_resolve_follows_the_style :: proc(t: ^testing.T) {
	g := test_gui(t)
	family := font_family_load(g, FONT_PATH)
	g.default_font_size = 16

	//* A style that names no size gets the GUI's own.
	style := Text_Style{}
	testing.expect_value(t, font_resolve(g, style), font_at(g, family, 16))

	//* A style that names a size gets that one.
	style.size = 24
	testing.expect_value(t, font_resolve(g, style), font_at(g, family, 24))

	//* A style that names a family gets that family.
	style.family = family
	style.size = 0
	testing.expect_value(t, font_resolve(g, style), font_at(g, family, 16))

	test_gui_destroy(g)
}

@(test)
test_widget_text_size_changes_its_measure :: proc(t: ^testing.T) {
	g := test_gui(t)
	family := font_family_load(g, FONT_PATH)

	small := widget(g, .Label, g.root, Widget_Opts{
		name = "small",
		text = "Hello",
		preset = .Top_Left,
		style = Style{text = Text_Style{size = 16, family = family}},
	})
	large := widget(g, .Label, g.root, Widget_Opts{
		name = "large",
		text = "Hello",
		preset = .Top_Left,
		style = Style{text = Text_Style{size = 32, family = family}},
	})
	layout_pass(g)

	sw := widget_get(g, small)
	lw := widget_get(g, large)
	testing.expect_value(t, sw.min_size.x > 0, true)
	testing.expect_value(t, lw.min_size.x > sw.min_size.x, true)
	testing.expect_value(t, lw.min_size.y > sw.min_size.y, true)

	test_gui_destroy(g)
}

//* == The theme ==

@(test)
test_theme_styles_the_widgets_that_ask :: proc(t: ^testing.T) {
	g := test_gui(t)

	theme := theme_make()
	theme_set_type(theme, .Button, Style{bg = rgba(0.9, 0.1, 0.1, 1)})
	gui_set_theme(g, theme)

	themed := widget(g, .Button, g.root, Widget_Opts{name = "themed", use_theme = true})
	plain := widget(g, .Button, g.root, Widget_Opts{
		name = "plain",
		style = Style{bg = rgba(0.1, 0.2, 0.3, 1)},
	})

	tw := widget_get(g, themed)
	pw := widget_get(g, plain)

	//* The themed widget takes the theme's background.
	testing.expect_value(t, resolved_style(g, tw).bg, rgba(0.9, 0.1, 0.1, 1))

	//* The other one keeps the style it has.
	testing.expect_value(t, resolved_style(g, pw).bg, rgba(0.1, 0.2, 0.3, 1))

	test_gui_destroy(g)
}

@(test)
test_widget_style_wins_over_the_theme :: proc(t: ^testing.T) {
	g := test_gui(t)

	theme := theme_make()
	theme_set_type(theme, .Button, Style{bg = rgba(0.9, 0.1, 0.1, 1)})
	gui_set_theme(g, theme)

	button := widget(g, .Button, g.root, Widget_Opts{
		name = "button",
		use_theme = true,
		style = Style{bg = rgba(0.1, 0.9, 0.1, 1)},
	})
	testing.expect_value(t, resolved_style(g, widget_get(g, button)).bg, rgba(0.1, 0.9, 0.1, 1))

	test_gui_destroy(g)
}

@(test)
test_theme_state_changes_the_background :: proc(t: ^testing.T) {
	g := test_gui(t)

	theme := theme_make()
	theme_set_type(theme, .Button, Style{bg = rgba(0.2, 0.2, 0.2, 1)})
	theme_set_state(theme, .Button, .Hovered, Style{bg = rgba(0.4, 0.4, 0.9, 1)})
	gui_set_theme(g, theme)

	button := widget(g, .Button, g.root, Widget_Opts{name = "button", use_theme = true})
	w := widget_get(g, button)

	//* Without the pointer the background is the theme's.
	testing.expect_value(t, resolved_bg(g, button, w), rgba(0.2, 0.2, 0.2, 1))

	//* Under the pointer the theme says what the background is.
	g.hot = button
	testing.expect_value(t, resolved_bg(g, button, w), rgba(0.4, 0.4, 0.9, 1))

	test_gui_destroy(g)
}

@(test)
test_theme_variation_wins_over_the_type :: proc(t: ^testing.T) {
	g := test_gui(t)

	theme := theme_make()
	theme_set_type(theme, .Button, Style{bg = rgba(0.2, 0.2, 0.2, 1)})
	theme_add_variation(theme, "danger", .Button, Style{bg = rgba(0.8, 0.1, 0.1, 1)})
	gui_set_theme(g, theme)

	normal := widget(g, .Button, g.root, Widget_Opts{name = "normal", use_theme = true})
	danger := widget(g, .Button, g.root, Widget_Opts{
		name = "danger",
		use_theme = true,
		variation = "danger",
	})

	testing.expect_value(t, resolved_style(g, widget_get(g, normal)).bg, rgba(0.2, 0.2, 0.2, 1))
	testing.expect_value(t, resolved_style(g, widget_get(g, danger)).bg, rgba(0.8, 0.1, 0.1, 1))

	test_gui_destroy(g)
}

@(test)
test_theme_holds_the_text_style :: proc(t: ^testing.T) {
	g := test_gui(t)

	theme := theme_make()
	theme_set_type(theme, .Label, Style{text = Text_Style{colour = rgba(1, 0, 0, 1), size = 24}})
	gui_set_theme(g, theme)

	label := widget(g, .Label, g.root, Widget_Opts{name = "label", use_theme = true})
	style := resolved_style(g, widget_get(g, label))
	testing.expect_value(t, style.text.colour, rgba(1, 0, 0, 1))
	testing.expect_value(t, style.text.size, 24.0)
	testing.expect_value(t, resolved_text_colour(g, label, widget_get(g, label)), rgba(1, 0, 0, 1))

	test_gui_destroy(g)
}

@(test)
test_disabled_text_colour :: proc(t: ^testing.T) {
	g := test_gui(t)

	button := widget(g, .Button, g.root, Widget_Opts{
		name = "button",
		style = Style{text = Text_Style{
			colour = rgba(1, 1, 1, 1),
			disabled_colour = rgba(0.4, 0.4, 0.4, 1),
		}},
	})
	w := widget_get(g, button)
	testing.expect_value(t, resolved_text_colour(g, button, w), rgba(1, 1, 1, 1))

	//* A widget that is not enabled draws its text in the disabled
	//* colour.
	w.state -= Widget_State{.Enabled}
	testing.expect_value(t, resolved_text_colour(g, button, w), rgba(0.4, 0.4, 0.4, 1))

	test_gui_destroy(g)
}

@(test)
test_explicit_set_mask_keeps_a_transparent_background :: proc(t: ^testing.T) {
	g := test_gui(t)

	theme := theme_make()
	theme_set_type(theme, .Button, Style{bg = rgba(0.9, 0.1, 0.1, 1)})
	gui_set_theme(g, theme)

	//* A transparent background is the same as no background, unless
	//* the style says that it is set.
	button := widget(g, .Button, g.root, Widget_Opts{
		name = "button",
		use_theme = true,
		style = Style{set = bit_set[Style_Field]{.BG}, bg = rgba(0, 0, 0, 0)},
	})
	testing.expect_value(t, resolved_style(g, widget_get(g, button)).bg, rgba(0, 0, 0, 0))

	test_gui_destroy(g)
}
