package Widgets
import "core:math"

GIZMO_BASE_SIZE        :: 32.0
GIZMO_AXIS_LENGTH      :: 48.0
GIZMO_RING_RADIUS      :: 64.0
GIZMO_HANDLE_SIZE      :: 9.0
GIZMO_HIT_TOLERANCE    :: 6.0
GIZMO_RING_SEGMENTS    :: 64
GIZMO_MIN_SCALE        :: 0.05
GIZMO_MAX_SCALE        :: 1000.0
GIZMO_ARROW_LENGTH     :: 9.0
GIZMO_ARROW_HALF_WIDTH :: 4.5

GIZMO_SCALE_SIGNS :: [4]Vec2{
	{-1, -1},
	{1, -1},
	{1, 1},
	{-1, 1},
}

gizmo_scale_handle :: proc(index: int) -> Gizmo_Handle {
	switch index {
	case 0:
		return .Scale_Top_Left
	case 1:
		return .Scale_Top_Right
	case 2:
		return .Scale_Bottom_Right
	case 3:
		return .Scale_Bottom_Left
	}
	return .None
}

Make_Gizmo :: proc(g: ^GUI, parent: Widget_ID, opts: Gizmo_Opts) -> Widget_ID {
	kind_register(g, .Gizmo, gizmo_kind())
	id := New_Widget(g, .Gizmo, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)
	if w == nil {return id}

	base_size := opts.base_size
	if base_size <= 0 {base_size = GIZMO_BASE_SIZE}
	min_scale := opts.min_scale
	if min_scale <= 0 {min_scale = GIZMO_MIN_SCALE}
	max_scale := opts.max_scale
	if max_scale <= min_scale {max_scale = GIZMO_MAX_SCALE}

	transform := opts.transform
	if transform.scale.x == 0 && transform.scale.y == 0 {transform.scale = Vec2{1, 1}}
	transform = gizmo_normalize_transform(transform, min_scale, max_scale)

	w.data = Gizmo_Data{
		transform     = transform,
		mode          = opts.mode,
		snap_position = gizmo_sanitize_snap(opts.snap_position),
		snap_angle    = gizmo_sanitize_snap(opts.snap_angle),
		min_scale     = min_scale,
		max_scale     = max_scale,
		base_size     = base_size,
		on_changed    = opts.on_changed,
		on_begin      = opts.on_begin,
		on_end        = opts.on_end,
	}
	w.focus_mode = .All
	return id
}

gizmo_kind :: proc() -> Widget_Kind {
	return Widget_Kind{
		draw            = draw_gizmo,
		pointer         = pointer_gizmo,
		key             = key_gizmo,
		post_update     = post_update_gizmo,
		hit_test        = hit_test_gizmo,
		uses_arrow_keys = true,
		interactive     = true,
		theme_name      = "Gizmo",
		access_role     = .Custom,
	}
}

gizmo_data :: proc(g: ^GUI, id: Widget_ID) -> ^Gizmo_Data {
	w := Widget_Get(g, id)
	if w == nil {return nil}
	#partial switch &d in w.data {
	case Gizmo_Data:
		return &d
	}
	return nil
}

gizmo_transform :: proc(g: ^GUI, id: Widget_ID) -> Gizmo_Transform {
	d := gizmo_data(g, id)
	if d == nil {return Gizmo_Transform{scale = Vec2{1, 1}}}
	return d.transform
}

gizmo_set_transform :: proc(g: ^GUI, id: Widget_ID, transform: Gizmo_Transform) {
	d := gizmo_data(g, id)
	if d == nil {return}
	next := transform
	if next.scale.x == 0 && next.scale.y == 0 {next.scale = Vec2{1, 1}}
	next = gizmo_normalize_transform(next, d.min_scale, d.max_scale)
	if next == d.transform {return}
	d.transform = next
	invalidate(g, id, Dirty_Flags{.Visual})
	if d.on_changed != nil {d.on_changed(g, id, d.transform)}
}

gizmo_mode :: proc(g: ^GUI, id: Widget_ID) -> Gizmo_Mode {
	d := gizmo_data(g, id)
	if d == nil {return .All}
	return d.mode
}

gizmo_set_mode :: proc(g: ^GUI, id: Widget_ID, mode: Gizmo_Mode) {
	d := gizmo_data(g, id)
	if d == nil || d.mode == mode {return}
	d.mode = mode
	d.hover = .None
	invalidate(g, id, Dirty_Flags{.Visual})
}

gizmo_handle_at :: proc(g: ^GUI, id: Widget_ID, pos: Vec2) -> Gizmo_Handle {
	w := Widget_Get(g, id)
	if w == nil {return .None}
	d := gizmo_data(g, id)
	if d == nil {return .None}
	return gizmo_handle_at_data(g, w, d, pos)
}

gizmo_handle_at_data :: proc(
	g: ^GUI,
	w: ^Widget,
	d: ^Gizmo_Data,
	pos: Vec2,
) -> Gizmo_Handle {
	content := content_rect(g, w)
	pivot := gizmo_pivot_of(
		Vec2{content.x + content.w * 0.5, content.y + content.h * 0.5},
		d.transform,
	)
	local := Vec2{pos.x - pivot.x, pos.y - pivot.y}
	frame := gizmo_rotate_point(local, -d.transform.rotation)
	grab := f32(GIZMO_HIT_TOLERANCE + GIZMO_HANDLE_SIZE * 0.5)

	if d.mode == .Scale || d.mode == .All {
		half := gizmo_box_half(d)
		for sign, i in GIZMO_SCALE_SIGNS {
			local := gizmo_rotate_point(
				Vec2{sign.x * half.x, sign.y * half.y},
				d.transform.rotation,
			)
			corner := Vec2{pivot.x + local.x, pivot.y + local.y}
			if abs(pos.x - corner.x) <= grab && abs(pos.y - corner.y) <= grab {
				return gizmo_scale_handle(i)
			}
		}
	}

	if d.mode == .Rotate || d.mode == .All {
		if abs(vec2_length(local) - gizmo_ring_radius(d)) <= grab {
			return .Rotate
		}
	}

	if d.mode == .Move || d.mode == .All {
		if abs(local.x) <= grab && abs(local.y) <= grab {return .Move_Free}
		axis := gizmo_axis_length(d)
		if abs(frame.y) <= GIZMO_HIT_TOLERANCE && frame.x >= 0 && frame.x <= axis {
			return .Move_X
		}
		if abs(frame.x) <= GIZMO_HIT_TOLERANCE && frame.y >= 0 && frame.y <= axis {
			return .Move_Y
		}
	}
	return .None
}

gizmo_normalize_transform :: proc(
	transform: Gizmo_Transform,
	min_scale, max_scale: f32,
) -> Gizmo_Transform {
	result := transform
	if result.position.x != result.position.x {result.position.x = 0}
	if result.position.y != result.position.y {result.position.y = 0}
	if result.rotation != result.rotation {result.rotation = 0}

	scale := result.scale
	if scale.x != scale.x {scale.x = 1}
	if scale.y != scale.y {scale.y = 1}
	scale.x = clamp(abs(scale.x), min_scale, max_scale)
	scale.y = clamp(abs(scale.y), min_scale, max_scale)
	result.scale = scale
	result.rotation = gizmo_wrap_angle(result.rotation)
	return result
}

gizmo_wrap_angle :: proc(angle: f32) -> f32 {
	two_pi := f32(math.PI * 2)
	return angle - two_pi * math.floor((angle + f32(math.PI)) / two_pi)
}

gizmo_snap_value :: proc(value, step: f32) -> f32 {
	if step <= 0 {return value}
	return math.round(value / step) * step
}

gizmo_sanitize_snap :: proc(value: f32) -> f32 {
	if value != value || value < 0 {return 0}
	return value
}

gizmo_rotate_point :: proc(point: Vec2, angle: f32) -> Vec2 {
	cosine := math.cos(angle)
	sine := math.sin(angle)
	return Vec2{
		x = point.x * cosine - point.y * sine,
		y = point.x * sine + point.y * cosine,
	}
}

gizmo_pivot_of :: proc(centre: Vec2, transform: Gizmo_Transform) -> Vec2 {
	return Vec2{
		x = centre.x + transform.position.x,
		y = centre.y + transform.position.y,
	}
}

gizmo_axis_length :: proc(d: ^Gizmo_Data) -> f32 {
	return d.base_size * f32(GIZMO_AXIS_LENGTH / GIZMO_BASE_SIZE)
}

gizmo_ring_radius :: proc(d: ^Gizmo_Data) -> f32 {
	return d.base_size * f32(GIZMO_RING_RADIUS / GIZMO_BASE_SIZE)
}

gizmo_box_half :: proc(d: ^Gizmo_Data) -> Vec2 {
	return Vec2{
		x = abs(d.transform.scale.x) * d.base_size,
		y = abs(d.transform.scale.y) * d.base_size,
	}
}

gizmo_colour :: proc(
	g: ^GUI,
	w: ^Widget,
	name: string,
	fallback: Colour,
) -> Colour {
	colour := theme_color(g, w, name)
	if colour.a > 0 {return colour}
	return fallback
}

gizmo_highlight :: proc(colour: Colour) -> Colour {
	return RGBA(
		min(colour.r + 0.22, 1),
		min(colour.g + 0.22, 1),
		min(colour.b + 0.22, 1),
		colour.a,
	)
}

gizmo_handle_colour :: proc(
	base: Colour,
	d: ^Gizmo_Data,
	handle: Gizmo_Handle,
) -> Colour {
	if d.active == handle || d.hover == handle {return gizmo_highlight(base)}
	return base
}

gizmo_cursor :: proc(handle: Gizmo_Handle, active: bool) -> Cursor {
	#partial switch handle {
	case .Move_X, .Move_Y, .Move_Free:
		return active ? .Grabbing : .Grab
	case .Rotate:
		return .Crosshair
	case .Scale_Top_Left:
		return .Resize_NW
	case .Scale_Top_Right:
		return .Resize_NE
	case .Scale_Bottom_Right:
		return .Resize_SE
	case .Scale_Bottom_Left:
		return .Resize_SW
	}
	return .Default
}

draw_gizmo :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	d := gizmo_data(g, id)
	if d == nil {return}

	pivot := gizmo_pivot_of(
		Vec2{content.x + content.w * 0.5, content.y + content.h * 0.5},
		d.transform,
	)
	x_axis := gizmo_colour(g, w, "x_axis", RGBA(0.92, 0.28, 0.32, 1))
	y_axis := gizmo_colour(g, w, "y_axis", RGBA(0.34, 0.82, 0.40, 1))
	move := gizmo_colour(g, w, "move", RGBA(0.92, 0.94, 0.98, 1))
	rotate := gizmo_colour(g, w, "rotate", RGBA(0.36, 0.64, 1, 1))
	scale := gizmo_colour(g, w, "scale", RGBA(0.94, 0.76, 0.28, 1))

	if d.mode == .Rotate || d.mode == .All {
		gizmo_draw_ring(g, d, pivot, gizmo_handle_colour(rotate, d, .Rotate))
	}
	if d.mode == .Scale || d.mode == .All {
		gizmo_draw_scale_box(g, d, pivot, scale)
	}
	if d.mode == .Move || d.mode == .All {
		gizmo_draw_move_axes(g, d, pivot, x_axis, y_axis)
		half := f32(GIZMO_HANDLE_SIZE * 0.5)
		draw_rect(
			g,
			Rect{x = pivot.x - half, y = pivot.y - half, w = GIZMO_HANDLE_SIZE, h = GIZMO_HANDLE_SIZE},
			gizmo_handle_colour(move, d, .Move_Free),
			2,
		)
	}
	if d.mode == .Scale || d.mode == .All {
		gizmo_draw_scale_handles(g, d, pivot, scale)
	}
	if d.mode == .Rotate || d.mode == .All {
		gizmo_draw_rotation_knob(g, d, pivot, gizmo_handle_colour(rotate, d, .Rotate))
	}
}

gizmo_draw_ring :: proc(g: ^GUI, d: ^Gizmo_Data, pivot: Vec2, colour: Colour) {
	radius := gizmo_ring_radius(d)
	segments := GIZMO_RING_SEGMENTS
	for i in 0 ..< segments {
		a0 := 2 * f32(math.PI) * f32(i) / f32(segments)
		a1 := 2 * f32(math.PI) * f32(i + 1) / f32(segments)
		p0 := gizmo_rotate_point(Vec2{radius, 0}, a0)
		p1 := gizmo_rotate_point(Vec2{radius, 0}, a1)
		draw_thick_line(
			g.target,
			{pivot.x + p0.x, pivot.y + p0.y},
			{pivot.x + p1.x, pivot.y + p1.y},
			2,
			colour,
			g.atlas_texture,
		)
	}
}

gizmo_draw_rotation_knob :: proc(
	g: ^GUI,
	d: ^Gizmo_Data,
	pivot: Vec2,
	colour: Colour,
) {
	radius := gizmo_ring_radius(d)
	point := gizmo_rotate_point(Vec2{radius, 0}, d.transform.rotation)
	half := f32(GIZMO_HANDLE_SIZE * 0.5) + 1
	draw_rect(
		g,
		Rect{
			x = pivot.x + point.x - half,
			y = pivot.y + point.y - half,
			w = GIZMO_HANDLE_SIZE + 2,
			h = GIZMO_HANDLE_SIZE + 2,
		},
		colour,
		2,
	)
}

gizmo_draw_scale_box :: proc(
	g: ^GUI,
	d: ^Gizmo_Data,
	pivot: Vec2,
	colour: Colour,
) {
	corners := gizmo_scale_corners(d, pivot)
	for i in 0 ..< 4 {
		a := corners[i]
		b := corners[(i + 1) % 4]
		draw_thick_line(
			g.target,
			{a.x, a.y},
			{b.x, b.y},
			1,
			colour,
			g.atlas_texture,
		)
	}
}

gizmo_draw_scale_handles :: proc(
	g: ^GUI,
	d: ^Gizmo_Data,
	pivot: Vec2,
	colour: Colour,
) {
	corners := gizmo_scale_corners(d, pivot)
	half := f32(GIZMO_HANDLE_SIZE * 0.5)
	for corner, i in corners {
		handle := gizmo_scale_handle(i)
		draw_rect(
			g,
			Rect{
				x = corner.x - half,
				y = corner.y - half,
				w = GIZMO_HANDLE_SIZE,
				h = GIZMO_HANDLE_SIZE,
			},
			gizmo_handle_colour(colour, d, handle),
			2,
		)
	}
}

gizmo_scale_corners :: proc(d: ^Gizmo_Data, pivot: Vec2) -> [4]Vec2 {
	half := gizmo_box_half(d)
	corners: [4]Vec2
	for sign, i in GIZMO_SCALE_SIGNS {
		local := gizmo_rotate_point(
			Vec2{sign.x * half.x, sign.y * half.y},
			d.transform.rotation,
		)
		corners[i] = Vec2{pivot.x + local.x, pivot.y + local.y}
	}
	return corners
}

gizmo_draw_move_axes :: proc(
	g: ^GUI,
	d: ^Gizmo_Data,
	pivot: Vec2,
	x_colour, y_colour: Colour,
) {
	length := gizmo_axis_length(d)
	x_direction := gizmo_rotate_point(Vec2{1, 0}, d.transform.rotation)
	y_direction := gizmo_rotate_point(Vec2{0, 1}, d.transform.rotation)
	x_tip := Vec2{pivot.x + x_direction.x * length, pivot.y + x_direction.y * length}
	y_tip := Vec2{pivot.x + y_direction.x * length, pivot.y + y_direction.y * length}

	draw_thick_line(
		g.target,
		{pivot.x, pivot.y},
		{x_tip.x, x_tip.y},
		2,
		gizmo_handle_colour(x_colour, d, .Move_X),
		g.atlas_texture,
	)
	draw_thick_line(
		g.target,
		{pivot.x, pivot.y},
		{y_tip.x, y_tip.y},
		2,
		gizmo_handle_colour(y_colour, d, .Move_Y),
		g.atlas_texture,
	)
	gizmo_draw_arrow(g, x_tip, x_direction, gizmo_handle_colour(x_colour, d, .Move_X))
	gizmo_draw_arrow(g, y_tip, y_direction, gizmo_handle_colour(y_colour, d, .Move_Y))
}

gizmo_draw_arrow :: proc(
	g: ^GUI,
	tip, direction: Vec2,
	colour: Colour,
) {
	back := Vec2{
		x = tip.x - direction.x * GIZMO_ARROW_LENGTH,
		y = tip.y - direction.y * GIZMO_ARROW_LENGTH,
	}
	side := Vec2{
		x = -direction.y * GIZMO_ARROW_HALF_WIDTH,
		y = direction.x * GIZMO_ARROW_HALF_WIDTH,
	}
	points := [3][2]f32{
		{tip.x, tip.y},
		{back.x + side.x, back.y + side.y},
		{back.x - side.x, back.y - side.y},
	}
	draw_polygon(g.target, points[:], colour, g.atlas_texture)
}

pointer_gizmo :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Pointer_Event) {
	d := gizmo_data(g, id)
	if d == nil {return}
	if e.kind == .Down && e.button != .Left {return}

	switch e.kind {
	case .Down:
		handle := gizmo_handle_at_data(g, w, d, e.pos)
		if handle == .None {return}
		d.active = handle
		d.hover = handle
		d.drag_start = e.pos
		d.drag_transform = d.transform
		content := content_rect(g, w)
		pivot := gizmo_pivot_of(
			Vec2{content.x + content.w * 0.5, content.y + content.h * 0.5},
			d.drag_transform,
		)
		d.drag_angle = math.atan2(e.pos.y - pivot.y, e.pos.x - pivot.x)
		Widget_Capture_Pointer(g, id)
		Focus_Set(g, id)
		invalidate(g, id, Dirty_Flags{.Visual})
		Event_Handled(g)
		if d.on_begin != nil {d.on_begin(g, id, handle)}

	case .Move:
		if d.active == .None {
			handle := gizmo_handle_at_data(g, w, d, e.pos)
			if handle != d.hover {
				d.hover = handle
				invalidate(g, id, Dirty_Flags{.Visual})
			}
			return
		}
		gizmo_drag(g, id, w, d, e.pos)

	case .Up:
		if d.active == .None {return}
		handle := d.active
		d.active = .None
		d.hover = .None
		Widget_Release_Pointer(g)
		invalidate(g, id, Dirty_Flags{.Visual})
		if d.on_end != nil {d.on_end(g, id, handle)}

	case .Wheel:
	}
}

gizmo_drag :: proc(
	g: ^GUI,
	id: Widget_ID,
	w: ^Widget,
	d: ^Gizmo_Data,
	pos: Vec2,
) {
	content := content_rect(g, w)
	pivot := gizmo_pivot_of(
		Vec2{content.x + content.w * 0.5, content.y + content.h * 0.5},
		d.drag_transform,
	)
	next := d.transform

	#partial switch d.active {
	case .Move_Free, .Move_X, .Move_Y:
		delta := Vec2{pos.x - d.drag_start.x, pos.y - d.drag_start.y}
		move := gizmo_rotate_point(delta, -d.drag_transform.rotation)
		if d.active == .Move_X {move.y = 0}
		if d.active == .Move_Y {move.x = 0}
		world := gizmo_rotate_point(move, d.drag_transform.rotation)
		next.position = Vec2{
			x = d.drag_transform.position.x + world.x,
			y = d.drag_transform.position.y + world.y,
		}
		if d.snap_position > 0 && .Ctrl in g.mods {
			next.position.x = gizmo_snap_value(next.position.x, d.snap_position)
			next.position.y = gizmo_snap_value(next.position.y, d.snap_position)
		}

	case .Rotate:
		angle := math.atan2(pos.y - pivot.y, pos.x - pivot.x)
		next.rotation = d.drag_transform.rotation + gizmo_wrap_angle(angle - d.drag_angle)
		if d.snap_angle > 0 && .Shift in g.mods {
			next.rotation = gizmo_snap_value(next.rotation, d.snap_angle)
		}

	case .Scale_Top_Left, .Scale_Top_Right, .Scale_Bottom_Right, .Scale_Bottom_Left:
		start := gizmo_rotate_point(
			Vec2{d.drag_start.x - pivot.x, d.drag_start.y - pivot.y},
			-d.drag_transform.rotation,
		)
		now := gizmo_rotate_point(
			Vec2{pos.x - pivot.x, pos.y - pivot.y},
			-d.drag_transform.rotation,
		)
		factor := Vec2{1, 1}
		if abs(start.x) > 0.0001 {factor.x = now.x / start.x}
		if abs(start.y) > 0.0001 {factor.y = now.y / start.y}
		next.scale = Vec2{
			x = d.drag_transform.scale.x * factor.x,
			y = d.drag_transform.scale.y * factor.y,
		}

	case .None:
		return
	}

	next = gizmo_normalize_transform(next, d.min_scale, d.max_scale)
	if next == d.transform {return}
	d.transform = next
	invalidate(g, id, Dirty_Flags{.Visual})
	if d.on_changed != nil {d.on_changed(g, id, d.transform)}
}

hit_test_gizmo :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, pos: Vec2) -> bool {
	d := gizmo_data(g, id)
	if d == nil {return false}
	if d.active != .None {return true}
	return gizmo_handle_at_data(g, w, d, pos) != .None
}

post_update_gizmo :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, dt: f32) {
	d := gizmo_data(g, id)
	if d == nil {return}

	if d.active != .None {
		g.cursor = gizmo_cursor(d.active, true)
		return
	}

	if !g.pointer_known {return}
	pointer := window_local_pos(g, id, g.global_pointer)
	handle := Gizmo_Handle.None
	if rect_contains(w.rect, pointer.x, pointer.y) {
		handle = gizmo_handle_at_data(g, w, d, pointer)
	}
	if handle == d.hover {
		if handle != .None {g.cursor = gizmo_cursor(handle, false)}
		return
	}
	d.hover = handle
	invalidate(g, id, Dirty_Flags{.Visual})
	if handle != .None {g.cursor = gizmo_cursor(handle, false)}
}

key_gizmo :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, e: Key_Down_Event) {
	d := gizmo_data(g, id)
	if d == nil {return}
	next := d.transform

	switch d.mode {
	case .Move, .All:
		step := f32(1)
		if .Shift in e.mods {
			step = 10
		} else if .Ctrl in e.mods {
			step = 0.1
		}
		#partial switch e.key {
		case .Left:
			next.position.x -= step
		case .Right:
			next.position.x += step
		case .Up:
			next.position.y -= step
		case .Down:
			next.position.y += step
		case:
			return
		}

	case .Rotate:
		step := d.snap_angle
		if step <= 0 {step = f32(math.PI / 12)}
		#partial switch e.key {
		case .Left:
			next.rotation -= step
		case .Right:
			next.rotation += step
		case:
			return
		}

	case .Scale:
		step := f32(0.1)
		if .Shift in e.mods {step = 0.5}
		#partial switch e.key {
		case .Up, .Right:
			next.scale = Vec2{next.scale.x + step, next.scale.y + step}
		case .Down, .Left:
			next.scale = Vec2{next.scale.x - step, next.scale.y - step}
		case:
			return
		}
	}

	next = gizmo_normalize_transform(next, d.min_scale, d.max_scale)
	if next == d.transform {return}
	d.transform = next
	invalidate(g, id, Dirty_Flags{.Visual})
	Event_Handled(g)
	if d.on_changed != nil {d.on_changed(g, id, d.transform)}
}
