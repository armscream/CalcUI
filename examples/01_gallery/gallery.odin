//* == The gallery ==
//* The scene of the gallery: a column of sections in a scroll
//* container. Every section has a title and the widgets of one group in
//* it, and every widget is filled with something that shows what it
//* does. The wheel scrolls the column.
//*   odin run examples\01_gallery
//*   odin run tools\shot - gallery.png

package main

import GUI "../../src/GUI"
import "core:os"

GALLERY_WIDTH :: 740
GALLERY_GAP :: 12
ROW_TOP :: 44
ROW_BOTTOM :: 14
COLUMN_WIDTH :: 228
COLUMN_GAP :: 16

EMOJI_FONT_PATHS := []string{"assets/fonts/Twemoji-Mozilla.ttf"}

g: ^GUI.GUI
family: GUI.Font_Family_ID
emoji_font: bool

gallery_scroll: GUI.Widget_ID
gallery_column: GUI.Widget_ID
gallery_height: f32

//* A section has a table of rows. Every row has a height, and a row
//* starts under the row above it, so a widget never lands on another
//* widget. The height of the section comes from the same table.

//* The number of rows a section can have.
MAX_ROWS :: 8

Rows :: struct {
	heights: [MAX_ROWS]f32,
	tops:    [MAX_ROWS]f32,
	count:   int,
	total:   f32,
}

//* Makes the table of the rows of a section.
Make_Rows :: proc(heights: ..f32) -> Rows {
	rows := Rows {
		count = len(heights),
	}
	top := f32(0)
	for i in 0 ..< min(len(heights), MAX_ROWS) {
		rows.heights[i] = heights[i]
		rows.tops[i] = top
		top += heights[i]
	}
	rows.total = top
	return rows
}

//* The height of a section that holds these rows.
Rows_Height :: proc(rows: Rows) -> f32 {
	return ROW_TOP + rows.total + ROW_BOTTOM
}

//* Builds the gallery: the scroll container, the column of sections and
//* the sections themselves.
Init_Gallery :: proc(gui: ^GUI.GUI, body: GUI.Font_Family_ID) {
	g = gui
	family = body
	gallery_scroll = GUI.INVALID_WIDGET_ID
	gallery_column = GUI.INVALID_WIDGET_ID
	gallery_height = 0

	emoji_font = Load_Emoji_Font(gui, body)

	GUI.Widget_Get(g, g.root).style.box.bg_color = GUI.RGBA(0.07, 0.08, 0.10, 1)

	gallery_scroll = GUI.Make_Scroll_Container(
		g,
		g.root,
		GUI.Scroll_Container_Opts {
			Base_Opts = GUI.Base_Opts {
				name = "scroll",
				offsets = GUI.Offset{left = 16, top = 12, right = -16, bottom = -12},
			},
		},
	)

	gallery_column = GUI.Make_VBox(
		g,
		gallery_scroll,
		GUI.Box_Opts {
			Base_Opts = GUI.Base_Opts {
				name = "sections",
				min_size = GUI.Vec2{GALLERY_WIDTH, 100},
				separation = GALLERY_GAP,
			},
		},
	)

	height := f32(0)
	height += Section_Buttons(gallery_column)
	height += Section_Inputs(gallery_column)
	height += Section_Ranges(gallery_column)
	height += Section_Choices(gallery_column)
	height += Section_Popups(gallery_column)
	height += Section_Overlays(gallery_column)
	height += Section_Containers(gallery_column)
	height += Section_Drawings(gallery_column)
	height += Section_Data(gallery_column)
	height += Section_Heavy(gallery_column)

	//* The text showcase is the last section: it shows the sizes, the
	//* colours, the alignment and the wrapping of the text.
	showcase := Init_Demo_Text(g, body)
	GUI.Widget_Set_Min_Size(g, showcase, GUI.Vec2{GALLERY_WIDTH, 240})
	GUI.Widget_Attach(g, gallery_column, showcase)
	height += 240

	gallery_height = height + f32(GALLERY_GAP) * 11
	GUI.Widget_Set_Min_Size(g, gallery_column, GUI.Vec2{GALLERY_WIDTH, gallery_height})
}

//* Loads the colour emoji font and makes it the fallback of the family
//* of the interface. The gallery works without the font: the picker
//* still opens and still reports the emoji, it only draws no glyph.
Load_Emoji_Font :: proc(gui: ^GUI.GUI, body: GUI.Font_Family_ID) -> bool {
	if body == GUI.INVALID_FONT_FAMILY_ID {return false}
	for path in EMOJI_FONT_PATHS {
		if !os.exists(path) {continue}
		emoji := GUI.Font_Family_Load(gui, path)
		if emoji == GUI.INVALID_FONT_FAMILY_ID {continue}
		if GUI.Font_Family_Set_Fallback(gui, body, emoji) {return true}
	}
	return false
}

//* A section of the gallery: a panel with the title of the group in it.
//* The height of the panel comes from the table of the rows.
Section :: proc(parent: GUI.Widget_ID, title: string, rows: Rows) -> GUI.Widget_ID {
	height := Rows_Height(rows)
	panel := GUI.Make_Panel(
		g,
		parent,
		GUI.Panel_Opts {
			Base_Opts = GUI.Base_Opts {
				name = title,
				min_size = GUI.Vec2{GALLERY_WIDTH, height},
				size_flags_v = GUI.Size_Flags{.Fill},
				style = GUI.Style {
					box = GUI.StyleBox {
						bg_color = GUI.RGBA(0.11, 0.12, 0.15, 1),
						border_color = {
							GUI.RGBA(0.20, 0.22, 0.27, 1),
							GUI.RGBA(0.20, 0.22, 0.27, 1),
							GUI.RGBA(0.20, 0.22, 0.27, 1),
							GUI.RGBA(0.20, 0.22, 0.27, 1),
						},
						border_width = {1, 1, 1, 1},
						content_margin = {12, 12, 12, 12},
					},
					text = GUI.Text_Style{colour = GUI.RGBA(0.86, 0.89, 0.95, 1)},
				},
			},
		},
	)

	GUI.Make_Label(
		g,
		panel,
		GUI.Label_Opts {
			Base_Opts = GUI.Base_Opts {
				name = "title",
				preset = .Top_Left,
				offsets = GUI.Offset{left = 16, top = 10, right = 500, bottom = 34},
				style = GUI.Style {
					text = GUI.Text_Style {
						colour = GUI.RGBA(0.55, 0.72, 0.98, 1),
						size = 17,
						family = family,
					},
				},
			},
			text = title,
		},
	)
	return panel
}

//* The place of a widget in a section: three columns and the rows of the
//* table of the rows. A row starts under the row above it, so a widget
//* never lands on another widget.
Place :: proc(rows: Rows, column, row: int, width, height: f32) -> GUI.Offset {
	x := 16 + f32(column) * (COLUMN_WIDTH + COLUMN_GAP)
	y := ROW_TOP + rows.tops[row]
	return GUI.Offset{left = x, top = y, right = x + width, bottom = y + height}
}

//* Puts an overlay in a corner of the window. The anchors of a popup are
//* put at zero when it goes under the root, so they are put back here.
Place_In_Corner :: proc(id: GUI.Widget_ID, anchors: GUI.Anchor, offsets: GUI.Offset) {
	GUI.Widget_Set_Anchors(g, id, anchors)
	GUI.Widget_Set_Offsets(g, id, offsets)
}
