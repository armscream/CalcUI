//* == The gallery ==
//* The scene of the gallery: a column of sections in a scroll
//* container. Every section has a title and the widgets of one group in
//* it, and every widget is filled with something that shows what it
//* does. The wheel scrolls the column.
//*   odin run examples\01_gallery
//*   odin run tools\shot - gallery.png

package main

import GUI "../../src/GUI"

//* The width of the column of sections.
GALLERY_WIDTH :: 740

//* The gap between two sections.
GALLERY_GAP :: 12

g: ^GUI.GUI
family: GUI.Font_Family_ID

gallery_scroll: GUI.Widget_ID
gallery_column: GUI.Widget_ID
gallery_height: f32

//* Builds the gallery: the scroll container, the column of sections and
//* the sections themselves.
Init_Gallery :: proc(gui: ^GUI.GUI, body: GUI.Font_Family_ID) {
	g = gui
	family = body
	gallery_scroll = GUI.INVALID_WIDGET_ID
	gallery_column = GUI.INVALID_WIDGET_ID
	gallery_height = 0

	GUI.Widget_Get(g, g.root).style.box.bg_color = GUI.RGBA(0.07, 0.08, 0.10, 1)

	gallery_scroll = GUI.Make_Scroll_Container(
		g,
		g.root,
		GUI.Scroll_Container_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "scroll",
				offsets = GUI.Offset{left = 16, top = 12, right = -16, bottom = -12},
			},
		},
	)

	gallery_column = GUI.Make_VBox(
		g,
		gallery_scroll,
		GUI.Box_Opts{
			Base_Opts = GUI.Base_Opts{
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

//* A section of the gallery: a panel with the title of the group in it.
Section :: proc(parent: GUI.Widget_ID, title: string, height: f32) -> GUI.Widget_ID {
	panel := GUI.Make_Panel(
		g,
		parent,
		GUI.Panel_Opts{
			Base_Opts = GUI.Base_Opts{
				name = title,
				min_size = GUI.Vec2{GALLERY_WIDTH, height},
				size_flags_v = GUI.Size_Flags{.Fill},
				style = GUI.Style{
					box = GUI.StyleBox{
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
		GUI.Label_Opts{
			Base_Opts = GUI.Base_Opts{
				name = "title",
				preset = .Top_Left,
				offsets = GUI.Offset{left = 16, top = 10, right = 500, bottom = 34},
				style = GUI.Style{
					text = GUI.Text_Style{colour = GUI.RGBA(0.55, 0.72, 0.98, 1), size = 17, family = family},
				},
			},
			text = title,
		},
	)
	return panel
}

//* The place of a widget in a section: three columns and rows that are
//* 38 points apart. The first row is under the title.
Slot :: proc(column, row: int) -> GUI.Offset {
	x := 16 + f32(column) * 244
	y := 44 + f32(row) * 38
	return GUI.Offset{left = x, top = y, right = x + 228, bottom = y + 30}
}

//* The place of a widget that is taller than a row.
Box :: proc(column, row, height: int) -> GUI.Offset {
	x := 16 + f32(column) * 244
	y := 44 + f32(row) * 38
	return GUI.Offset{left = x, top = y, right = x + 228, bottom = y + f32(height)}
}

//* The place of a widget of a given size. The rows are 104 points
//* apart, so the taller widgets fit in them.
Place :: proc(column, row: int, width, height: f32) -> GUI.Offset {
	x := 16 + f32(column) * 244
	y := 44 + f32(row) * 104
	return GUI.Offset{left = x, top = y, right = x + width, bottom = y + height}
}
