//* The geometry of a nine-patch image. The source rectangle is divided
//* into nine cells by four border measurements, and every cell is mapped
//* to a destination rectangle. The corner cells keep the size of their
//* border, the edges stretch along one axis, and the centre takes what is
//* left.
//
//* The layout is computed in source pixels and logical units, so it is
//* independent of the texture atlas and of the renderer. Drawing the
//* cells is the job of the widget.
package Core
import "core:math"

//* How an edge or the centre fills the room between the corners.
Nine_Patch_Edge_Mode :: enum u8 {
	//* The texture of the cell is scaled to the destination of the cell.
	Stretch,
	//* The texture of the cell is repeated along the stretching axis.
	Tile,
}

//* How the centre of a nine-patch image fills its room.
Nine_Patch_Centre_Mode :: enum u8 {
	Stretch,
	Tile,
	Disabled,
}

//* The nine cells, in the order the layout stores them.
Nine_Patch_Cell :: enum u8 {
	Top_Left,
	Top,
	Top_Right,
	Left,
	Centre,
	Right,
	Bottom_Left,
	Bottom,
	Bottom_Right,
}

NINE_PATCH_CELL_COUNT :: 9

//* The calculated geometry of a nine-patch image. A source or destination
//* cell with a width or a height of zero is not visible and is skipped by
//* the drawing code.
Nine_Patch_Layout :: struct {
	valid:   bool,
	//* The source region, in texture pixels.
	source:  Rect,
	//* The destination region, in logical units.
	dest:    Rect,
	//* The scale that turns physical pixels into logical units.
	scale:   f32,
	//* The four border measurements after they were fitted to the source,
	//* in source pixels. The order is left, top, right, bottom.
	patch:   [4]f32,
	//* The four border measurements after they were fitted to the
	//* destination, in logical units. The order is left, top, right,
	//* bottom.
	borders: [4]f32,
	sources: [NINE_PATCH_CELL_COUNT]Rect,
	dests:   [NINE_PATCH_CELL_COUNT]Rect,
}

//* Divides a source rectangle into nine cells and maps them to a
//* destination rectangle.
//
//* `patch` is the size of the four borders in source pixels, in the order
//* left, top, right and bottom. A negative or non-finite border is treated
//* as zero. When the opposing borders do not fit in the source or in the
//* destination, they are scaled down together, so they keep their relative
//* sizes and do not overlap.
//
//* `scale` is the number of physical pixels in a logical unit. A source
//* pixel and a logical unit are the same size when the scale is one.
nine_patch_layout :: proc(
	source: Rect,
	dest: Rect,
	patch: [4]f32,
	scale: f32,
) -> Nine_Patch_Layout {
	out := Nine_Patch_Layout {
		source = source,
		dest   = dest,
		scale  = scale,
	}
	if !(source.w > 0 && source.h > 0) {return out}
	if !(dest.w > 0 && dest.h > 0) {return out}
	unit_scale := scale
	if !(unit_scale > 0) || !nine_patch_finite(unit_scale) {
		unit_scale = 1
		out.scale = 1
	}

	left := nine_patch_border(patch[0])
	top := nine_patch_border(patch[1])
	right := nine_patch_border(patch[2])
	bottom := nine_patch_border(patch[3])

	//* The corners cannot be wider or taller than the source.
	left, right = nine_patch_fit(left, right, source.w)
	top, bottom = nine_patch_fit(top, bottom, source.h)
	out.patch = {left, top, right, bottom}

	//* The corners cannot be wider or taller than the destination either.
	logical_left := left / unit_scale
	logical_top := top / unit_scale
	logical_right := right / unit_scale
	logical_bottom := bottom / unit_scale
	logical_left, logical_right = nine_patch_fit(logical_left, logical_right, dest.w)
	logical_top, logical_bottom = nine_patch_fit(logical_top, logical_bottom, dest.h)
	out.borders = {logical_left, logical_top, logical_right, logical_bottom}

	//* The source boundaries. The centre takes the space between the
	//* borders, and it is empty when the borders meet.
	source_left := source.x
	source_top := source.y
	source_right := source.x + source.w
	source_bottom := source.y + source.h
	source_centre_left := source_left + left
	source_centre_top := source_top + top
	source_centre_right := source_right - right
	source_centre_bottom := source_bottom - bottom
	source_centre_w := source_centre_right - source_centre_left
	source_centre_h := source_centre_bottom - source_centre_top

	//* The destination boundaries. Every cell uses these shared values,
	//* so neighbouring cells meet exactly and no seam opens between them.
	dest_left := dest.x
	dest_top := dest.y
	dest_right := dest.x + dest.w
	dest_bottom := dest.y + dest.h
	dest_centre_left := dest_left + logical_left
	dest_centre_top := dest_top + logical_top
	dest_centre_right := dest_right - logical_right
	dest_centre_bottom := dest_bottom - logical_bottom
	dest_centre_w := dest_centre_right - dest_centre_left
	dest_centre_h := dest_centre_bottom - dest_centre_top

	nine_patch_cell(
		&out,
		.Top_Left,
		Rect{source_left, source_top, left, top},
		Rect{dest_left, dest_top, logical_left, logical_top},
	)
	nine_patch_cell(
		&out,
		.Top,
		Rect{source_centre_left, source_top, source_centre_w, top},
		Rect{dest_centre_left, dest_top, dest_centre_w, logical_top},
	)
	nine_patch_cell(
		&out,
		.Top_Right,
		Rect{source_centre_right, source_top, right, top},
		Rect{dest_centre_right, dest_top, logical_right, logical_top},
	)
	nine_patch_cell(
		&out,
		.Left,
		Rect{source_left, source_centre_top, left, source_centre_h},
		Rect{dest_left, dest_centre_top, logical_left, dest_centre_h},
	)
	nine_patch_cell(
		&out,
		.Centre,
		Rect{source_centre_left, source_centre_top, source_centre_w, source_centre_h},
		Rect{dest_centre_left, dest_centre_top, dest_centre_w, dest_centre_h},
	)
	nine_patch_cell(
		&out,
		.Right,
		Rect{source_centre_right, source_centre_top, right, source_centre_h},
		Rect{dest_centre_right, dest_centre_top, logical_right, dest_centre_h},
	)
	nine_patch_cell(
		&out,
		.Bottom_Left,
		Rect{source_left, source_centre_bottom, left, bottom},
		Rect{dest_left, dest_centre_bottom, logical_left, logical_bottom},
	)
	nine_patch_cell(
		&out,
		.Bottom,
		Rect{source_centre_left, source_centre_bottom, source_centre_w, bottom},
		Rect{dest_centre_left, dest_centre_bottom, dest_centre_w, logical_bottom},
	)
	nine_patch_cell(
		&out,
		.Bottom_Right,
		Rect{source_centre_right, source_centre_bottom, right, bottom},
		Rect{dest_centre_right, dest_centre_bottom, logical_right, logical_bottom},
	)

	out.valid = true
	return out
}

//* Reads one border measurement and treats an invalid value as zero.
nine_patch_border :: proc(value: f32) -> f32 {
	if !nine_patch_finite(value) || value <= 0 {return 0}
	return value
}

nine_patch_finite :: proc(value: f32) -> bool {
	return !math.is_nan(value) && !math.is_inf(value)
}

//* Fits two opposing borders into a length. When they do not fit, both
//* are scaled by the same factor, so they keep their relative sizes.
nine_patch_fit :: proc(a, b, limit: f32) -> (f32, f32) {
	total := a + b
	if total <= 0 {return 0, 0}
	if total <= limit {return a, b}
	factor := limit / total
	return a * factor, b * factor
}

nine_patch_cell :: proc(layout: ^Nine_Patch_Layout, cell: Nine_Patch_Cell, source, dest: Rect) {
	layout.sources[int(cell)] = source
	layout.dests[int(cell)] = dest
}
