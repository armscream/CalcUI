//* The SDL3 GPU backend: one draw list and one implementation of it,
//* and SDL's GPU API picks the driver (Vulkan, D3D12, Metal, OpenGL).
//* The rules this backend keeps to are in docs/contracts.md.
package Backend

import sdl "vendor:sdl3"
import GUI "../GUI"
import "core:log"
import "core:mem"

vert_shader_code := #load("Shaders/ui.spv.vert")
frag_shader_code := #load("Shaders/ui.spv.frag")

Vertex :: GUI.Packed_Vertex

//* Matches the uniform block in the vertex shader.
UBO :: struct {
	viewport: [2]f32,
}

//* The glass reads a full window backdrop, so it needs the window metrics
//* and the length of the mip chain, no capture region.
Glass_UBO :: struct {
	metrics: [4]f32, // backdrop scale x, scale y, window width, height
	levels:  [4]f32, // mip level count
}

//* What a target needs to draw a list of its own: the buffers of its
//* geometry and the size of its window.
GPU_Slot :: struct {
	vertex_buf:      ^sdl.GPUBuffer,
	index_buf:       ^sdl.GPUBuffer,
	vertex_size:     int,
	index_size:      int,
	//* The revision and the counts of the geometry that was uploaded last.
	revision:        u64,
	vertex_count:    int,
	index_count:     int,
	packed:          [dynamic]Vertex,
	width:           f32,
	height:          f32,
	//* The offscreen scene, the half resolution backdrop the glass reads,
	//* and the grouped capture points.
	scene_tex:       ^sdl.GPUTexture,
	backdrop_tex:    ^sdl.GPUTexture,
	tex_w:           u32,
	tex_h:           u32,
	plan:            Backdrop_Plan,
	cached_valid:    bool,
	cached_revision: u64,
}

GPU_State :: struct {
	device:           ^sdl.GPUDevice,
	window:           ^sdl.Window,
	pipeline:         ^sdl.GPUGraphicsPipeline,
	sampler:          ^sdl.GPUSampler,
	//* The atlas has one level, so it keeps a nearest mip mode. The
	//* backdrop is sampled trilinearly between the levels of its chain.
	backdrop_sampler: ^sdl.GPUSampler,

	//* The format of the swapchain. The offscreen targets of a glass
	//* list use the same one, so the one pipeline draws into all of
	//* them.
	format:   sdl.GPUTextureFormat,

	textures: [dynamic]^sdl.GPUTexture,

	//* The target of the main window comes first, the floating panels
	//* follow.
	slots: [dynamic]GPU_Slot,

	//* The windows of the floating panels. They share the device and
	//* the textures with the main window.
	targets: [dynamic]GPU_Target,
}

//* A floating panel: the window it has of its own.
GPU_Target :: struct {
	window: ^sdl.Window,
}

gpu_create :: proc(ctx, window: rawptr, w, h: i32) -> bool {
	st := cast(^GPU_State)ctx
	st.window = cast(^sdl.Window)window

	//* SPIR-V only: the UI shaders are compiled with glslc.
	device := sdl.CreateGPUDevice({.SPIRV}, true, nil)
	if device == nil { return false }
	st.device = device
	log.infof("backend: SDL3 GPU device '%s'", sdl.GetGPUDeviceDriver(device))

	if !sdl.ClaimWindowForGPUDevice(device, st.window) { return false }

	vert := load_shader(device, vert_shader_code, .VERTEX, 1, 0)
	frag := load_shader(device, frag_shader_code, .FRAGMENT, 1, 1)
	if vert == nil || frag == nil { return false }

	vertex_attrs := []sdl.GPUVertexAttribute{
		{location = 0, format = .FLOAT2, offset = u32(offset_of(Vertex, pos))},
		{location = 1, format = .USHORT2_NORM, offset = u32(offset_of(Vertex, uv))},
		{location = 2, format = .UBYTE4_NORM, offset = u32(offset_of(Vertex, colour))},
		{location = 3, format = .FLOAT4, offset = u32(offset_of(Vertex, shape))},
		{location = 4, format = .FLOAT2, offset = u32(offset_of(Vertex, local))},
		{location = 5, format = .USHORT4_NORM, offset = u32(offset_of(Vertex, corners))},
		{location = 6, format = .SHORT4_NORM, offset = u32(offset_of(Vertex, border))},
		{location = 7, format = .FLOAT, offset = u32(offset_of(Vertex, opacity))},
	}

	st.format = sdl.GetGPUSwapchainTextureFormat(device, st.window)
	pipeline := sdl.CreateGPUGraphicsPipeline(
		device,
		sdl.GPUGraphicsPipelineCreateInfo {
			vertex_shader = vert,
			fragment_shader = frag,
			primitive_type = .TRIANGLELIST,
			vertex_input_state = {
				num_vertex_buffers = 1,
				vertex_buffer_descriptions = &(sdl.GPUVertexBufferDescription {
					slot = 0,
					pitch = size_of(Vertex),
				}),
				num_vertex_attributes = u32(len(vertex_attrs)),
				vertex_attributes = raw_data(vertex_attrs),
			},
			target_info = {
				num_color_targets = 1,
				color_target_descriptions = &(sdl.GPUColorTargetDescription {
					format = st.format,
					blend_state = sdl.GPUColorTargetBlendState {
						//* The fragment shader outputs premultiplied alpha.
						src_color_blendfactor = .ONE,
						dst_color_blendfactor = .ONE_MINUS_SRC_ALPHA,
						color_blend_op = .ADD,
						src_alpha_blendfactor = .ONE,
						dst_alpha_blendfactor = .ONE_MINUS_SRC_ALPHA,
						alpha_blend_op = .ADD,
						enable_blend = true,
					},
				}),
			},
		},
	)
	sdl.ReleaseGPUShader(device, vert)
	sdl.ReleaseGPUShader(device, frag)
	if pipeline == nil { return false }
	st.pipeline = pipeline

	st.sampler = sdl.CreateGPUSampler(
		device,
		sdl.GPUSamplerCreateInfo {
			min_filter = .LINEAR,
			mag_filter = .LINEAR,
			mipmap_mode = .NEAREST,
			address_mode_u = .CLAMP_TO_EDGE,
			address_mode_v = .CLAMP_TO_EDGE,
			address_mode_w = .CLAMP_TO_EDGE,
		},
	)
	st.backdrop_sampler = sdl.CreateGPUSampler(
		device,
		sdl.GPUSamplerCreateInfo {
			min_filter = .LINEAR,
			mag_filter = .LINEAR,
			mipmap_mode = .LINEAR,
			address_mode_u = .CLAMP_TO_EDGE,
			address_mode_v = .CLAMP_TO_EDGE,
			address_mode_w = .CLAMP_TO_EDGE,
		},
	)

	append(&st.slots, GPU_Slot{width = f32(w), height = f32(h)})
	return true
}

gpu_slot_release :: proc(st: ^GPU_State, slot: ^GPU_Slot) {
	if slot.vertex_buf != nil { sdl.ReleaseGPUBuffer(st.device, slot.vertex_buf) }
	if slot.index_buf != nil { sdl.ReleaseGPUBuffer(st.device, slot.index_buf) }
	if slot.scene_tex != nil { sdl.ReleaseGPUTexture(st.device, slot.scene_tex) }
	if slot.backdrop_tex != nil { sdl.ReleaseGPUTexture(st.device, slot.backdrop_tex) }
	backdrop_plan_destroy(&slot.plan)
	delete(slot.packed)
	slot^ = {}
}

gpu_destroy :: proc(ctx: rawptr) {
	st := cast(^GPU_State)ctx
	if st == nil { return }
	if st.device == nil {
		delete(st.slots)
		delete(st.textures)
		st^ = {}
		return
	}

	for tex in st.textures {
		if tex != nil { sdl.ReleaseGPUTexture(st.device, tex) }
	}
	clear(&st.textures)
	delete(st.textures)

	for &slot in st.slots {
		gpu_slot_release(st, &slot)
	}
	clear(&st.slots)
	delete(st.slots)

	for target in st.targets {
		if target.window != nil {
			sdl.ReleaseWindowFromGPUDevice(st.device, target.window)
		}
	}
	clear(&st.targets)
	delete(st.targets)

	if st.window != nil { sdl.ReleaseWindowFromGPUDevice(st.device, st.window) }
	if st.sampler != nil { sdl.ReleaseGPUSampler(st.device, st.sampler) }
	if st.backdrop_sampler != nil { sdl.ReleaseGPUSampler(st.device, st.backdrop_sampler) }
	if st.pipeline != nil { sdl.ReleaseGPUGraphicsPipeline(st.device, st.pipeline) }
	if st.device != nil { sdl.DestroyGPUDevice(st.device) }

	st^ = {}
}

//* The window of a floating panel is going away: its swapchain is released
//* and the buffers and textures of its slot are given back. The main window
//* keeps slot zero.
gpu_release_target :: proc(ctx: rawptr, window: rawptr) {
	st := cast(^GPU_State)ctx
	if st == nil || st.device == nil || window == nil {return}
	handle := cast(^sdl.Window)window
	for target, i in st.targets {
		if target.window != handle {continue}
		if i + 1 < len(st.slots) {
			gpu_slot_release(st, &st.slots[i + 1])
			ordered_remove(&st.slots, i + 1)
		}
		ordered_remove(&st.targets, i)
		sdl.ReleaseWindowFromGPUDevice(st.device, handle)
		return
	}
}

gpu_resize :: proc(ctx: rawptr, w, h: i32) -> bool {
	st := cast(^GPU_State)ctx
	if st == nil { return false }
	if len(st.slots) == 0 { return false }
	st.slots[0].width = f32(w)
	st.slots[0].height = f32(h)
	st.slots[0].cached_valid = false
	return true
}

gpu_invalidate :: proc(ctx: rawptr) {
	st := cast(^GPU_State)ctx
	if st == nil { return }
	for &slot in st.slots {
		slot.cached_valid = false
	}
}

//* == The textures ==

gpu_upload_texture :: proc(ctx: rawptr, id: GUI.Texture_ID, pixels: []u8, w, h: i32) -> bool {
	st := cast(^GPU_State)ctx
	if st == nil || st.device == nil { return false }
	if w <= 0 || h <= 0 { return false }
	if len(pixels) < int(w) * int(h) * 4 { return false }

	if gpu_make_texture(st, id, w, h) == nil { return false }

	region := GUI.Texture_Upload{pixels = pixels, w = w, h = h, x = 0, y = 0}
	regions := [1]GUI.Texture_Upload{region}
	return gpu_upload_texture_regions(ctx, id, regions[:])
}

//* Uploads the parts of a texture that changed, in one copy pass and
//* one command buffer.
gpu_upload_texture_regions :: proc(
	ctx: rawptr,
	id: GUI.Texture_ID,
	regions: []GUI.Texture_Upload,
) -> bool {
	st := cast(^GPU_State)ctx
	if st == nil || st.device == nil { return false }
	if len(regions) == 0 { return true }

	tex := gpu_texture(st, id)
	if tex == nil { return false }

	//* The pixels of every part are put together in one buffer.
	total := 0
	for &region in regions {
		if region.w <= 0 || region.h <= 0 { continue }
		if len(region.pixels) < int(region.w) * int(region.h) * 4 { continue }
		total += len(region.pixels)
	}
	if total == 0 { return true }

	transfer := sdl.CreateGPUTransferBuffer(
		st.device,
		sdl.GPUTransferBufferCreateInfo{usage = .UPLOAD, size = u32(total)},
	)
	if transfer == nil { return false }

	dst := sdl.MapGPUTransferBuffer(st.device, transfer, false)
	if dst == nil {
		sdl.ReleaseGPUTransferBuffer(st.device, transfer)
		return false
	}
	at := 0
	for &region in regions {
		if region.w <= 0 || region.h <= 0 { continue }
		if len(region.pixels) < int(region.w) * int(region.h) * 4 { continue }
		mem.copy(cast(rawptr)(cast(uintptr)dst + uintptr(at)), raw_data(region.pixels), len(region.pixels))
		at += len(region.pixels)
	}
	sdl.UnmapGPUTransferBuffer(st.device, transfer)

	cmd := sdl.AcquireGPUCommandBuffer(st.device)
	copy_pass := sdl.BeginGPUCopyPass(cmd)
	at = 0
	for &region in regions {
		if region.w <= 0 || region.h <= 0 { continue }
		if len(region.pixels) < int(region.w) * int(region.h) * 4 { continue }
		sdl.UploadToGPUTexture(
			copy_pass,
			sdl.GPUTextureTransferInfo {
				transfer_buffer = transfer,
				offset          = u32(at),
				//* Zero means the rows follow each other tightly, with
				//* the width of the region.
				pixels_per_row  = 0,
				rows_per_layer  = 0,
			},
			sdl.GPUTextureRegion {
				texture = tex,
				x       = u32(max(region.x, 0)),
				y       = u32(max(region.y, 0)),
				w       = u32(region.w),
				h       = u32(region.h),
				d       = 1,
			},
			false,
		)
		at += len(region.pixels)
	}
	sdl.EndGPUCopyPass(copy_pass)
	ok := sdl.SubmitGPUCommandBuffer(cmd)
	sdl.ReleaseGPUTransferBuffer(st.device, transfer)
	return ok
}

gpu_texture :: proc(st: ^GPU_State, id: GUI.Texture_ID) -> ^sdl.GPUTexture {
	idx := int(id)
	if idx < 0 || idx >= len(st.textures) { return nil }
	return st.textures[idx]
}

gpu_make_texture :: proc(st: ^GPU_State, id: GUI.Texture_ID, w, h: i32) -> ^sdl.GPUTexture {
	idx := int(id)
	for len(st.textures) <= idx {
		append(&st.textures, nil)
	}
	tex := st.textures[idx]
	if tex != nil { return tex }
	if w <= 0 || h <= 0 { return nil }

	tex = sdl.CreateGPUTexture(
		st.device,
		sdl.GPUTextureCreateInfo {
			type = .D2,
			format = .R8G8B8A8_UNORM,
			usage = {.SAMPLER},
			width = u32(w),
			height = u32(h),
			layer_count_or_depth = 1,
			num_levels = 1,
			sample_count = ._1,
		},
	)
	if tex == nil { return nil }
	st.textures[idx] = tex
	return tex
}

gpu_destroy_texture :: proc(ctx: rawptr, id: GUI.Texture_ID) {
	st := cast(^GPU_State)ctx
	if st == nil { return }
	idx := int(id)
	if idx >= len(st.textures) { return }
	if st.textures[idx] != nil {
		sdl.ReleaseGPUTexture(st.device, st.textures[idx])
		st.textures[idx] = nil
	}
}

//* == The drawing ==

gpu_submit :: proc(ctx: rawptr, dl: ^GUI.Draw_List) {
	st := cast(^GPU_State)ctx
	if st == nil || st.device == nil { return }
	if len(st.slots) == 0 { return }
	gpu_render(st, 0, st.window, st.slots[0].width, st.slots[0].height, dl)
}

//* Renders a draw list into the window of a floating panel. The window
//* is claimed for the device the first time it is used.
gpu_submit_target :: proc(ctx: rawptr, dl: ^GUI.Draw_List, window: rawptr) {
	st := cast(^GPU_State)ctx
	if st == nil || st.device == nil { return }
	handle := cast(^sdl.Window)window

	index := -1
	for target, i in st.targets {
		if target.window == handle {
			index = i
			break
		}
	}
	if index < 0 {
		if !sdl.ClaimWindowForGPUDevice(st.device, handle) { return }
		append(&st.targets, GPU_Target{window = handle})
		append(&st.slots, GPU_Slot{})
		index = len(st.targets) - 1
	}

	//* The window can be made bigger or smaller at any time, so its
	//* size is asked for every frame.
	w, h: i32
	sdl.GetWindowSizeInPixels(handle, &w, &h)
	slot := &st.slots[index + 1]
	slot.width = f32(w)
	slot.height = f32(h)
	gpu_render(st, index + 1, handle, slot.width, slot.height, dl)
}

gpu_render :: proc(
	st: ^GPU_State,
	slot_index: int,
	window: ^sdl.Window,
	width, height: f32,
	dl: ^GUI.Draw_List,
) {
	if slot_index < 0 || slot_index >= len(st.slots) { return }
	slot := &st.slots[slot_index]
	Stats_Reset()

	cmd_buf := sdl.AcquireGPUCommandBuffer(st.device)
	swapchain: ^sdl.GPUTexture
	if !sdl.WaitAndAcquireGPUSwapchainTexture(cmd_buf, window, &swapchain, nil, nil) {
		_ = sdl.SubmitGPUCommandBuffer(cmd_buf)
		return
	}

	transfers: [2]^sdl.GPUTransferBuffer
	gpu_upload_geometry(st, cmd_buf, slot, dl, &transfers)

	ubo := UBO{viewport = {width, height}}
	sdl.PushGPUVertexUniformData(cmd_buf, 0, &ubo, size_of(ubo))
	glass_ubo := Glass_UBO {
		metrics = {BACKDROP_SCALE, BACKDROP_SCALE, width, height},
		levels  = {f32(BACKDROP_MIPS), 0, 0, 0},
	}
	sdl.PushGPUFragmentUniformData(cmd_buf, 0, &glass_ubo, u32(size_of(glass_ubo)))

	if gpu_scene_ready(st, slot, u32(width), u32(height)) {
		if slot.cached_valid && slot.cached_revision == dl.revision {
			Stats.cache_hits += 1
			gpu_blit(cmd_buf, slot.scene_tex, swapchain, u32(width), u32(height))
		} else {
			gpu_render_scene(st, cmd_buf, slot, width, height, dl)
			gpu_blit(cmd_buf, slot.scene_tex, swapchain, u32(width), u32(height))
			slot.cached_valid = true
			slot.cached_revision = dl.revision
		}
	} else {
		gpu_render_direct(st, cmd_buf, swapchain, slot, width, height, dl)
	}

	_ = sdl.SubmitGPUCommandBuffer(cmd_buf)

	for transfer in transfers {
		if transfer != nil { sdl.ReleaseGPUTransferBuffer(st.device, transfer) }
	}
}

gpu_cmd_texture :: proc(st: ^GPU_State, cmd: GUI.Draw_Command) -> ^sdl.GPUTexture {
	if int(cmd.texture) < len(st.textures) { return st.textures[cmd.texture] }
	return nil
}

//* Binds the pipeline, the viewport and the geometry of a list. The
//* buffers belong to the pass, so this runs again every time a pass is
//* started.
gpu_pass_bind :: proc(
	st: ^GPU_State,
	pass: ^sdl.GPURenderPass,
	slot: ^GPU_Slot,
	width, height: f32,
	dl: ^GUI.Draw_List,
) {
	sdl.BindGPUGraphicsPipeline(pass, st.pipeline)
	sdl.SetGPUViewport(
		pass,
		sdl.GPUViewport{x = 0, y = 0, w = width, h = height, min_depth = 0, max_depth = 1},
	)
	if len(dl.vertices) > 0 && len(dl.indices) > 0 {
		sdl.BindGPUVertexBuffers(pass, 0, &(sdl.GPUBufferBinding{buffer = slot.vertex_buf}), 1)
		sdl.BindGPUIndexBuffer(pass, sdl.GPUBufferBinding{buffer = slot.index_buf}, ._32BIT)
	}
}

//* The plain path: one pass straight into the swapchain.
gpu_render_direct :: proc(
	st: ^GPU_State,
	cmd: ^sdl.GPUCommandBuffer,
	target_tex: ^sdl.GPUTexture,
	slot: ^GPU_Slot,
	width, height: f32,
	dl: ^GUI.Draw_List,
) {
	target := sdl.GPUColorTargetInfo {
		texture = target_tex,
		load_op = .CLEAR,
		clear_color = sdl.FColor{0, 0, 0, 1},
		store_op = .STORE,
	}
	pass := sdl.BeginGPURenderPass(cmd, &target, 1, nil)
	Stats.draw_passes += 1
	Stats.full_updates += 1
	Stats.scene_updates += 1
	gpu_pass_bind(st, pass, slot, width, height, dl)

	bound: ^sdl.GPUTexture = nil
	for c in dl.commands {
		if c.idx_count == 0 { continue }
		tex := gpu_cmd_texture(st, c)
		if tex != bound {
			binding := sdl.GPUTextureSamplerBinding{texture = tex, sampler = st.sampler}
			sdl.BindGPUFragmentSamplers(pass, 0, &binding, 1)
			bound = tex
		}
		sdl.DrawGPUIndexedPrimitives(pass, c.idx_count, 1, c.idx_offset, 0, 0)
	}

	sdl.EndGPURenderPass(pass)
}

//* The glass path: the list is drawn into an offscreen scene. A group of
//* glass commands shares one capture of the half resolution backdrop,
//* which the shader reads and blurs.
gpu_render_scene :: proc(
	st: ^GPU_State,
	cmd: ^sdl.GPUCommandBuffer,
	slot: ^GPU_Slot,
	width, height: f32,
	dl: ^GUI.Draw_List,
) {
	backdrop_plan_build(&slot.plan, dl)

	//* A scissored replay keeps the scene texture and redraws only the
	//* rectangle the core asked for. It is refused when the cache is not
	//* valid, the rectangle is empty or too much of the window, or the
	//* list has glass.
	scissor, scissored := gpu_partial_rect(dl, slot)
	if scissored {
		Stats.partial_updates += 1
	} else {
		Stats.full_updates += 1
	}
	Stats.scene_updates += 1

	target := sdl.GPUColorTargetInfo {
		texture = slot.scene_tex,
		load_op = scissored ? .LOAD : .CLEAR,
		clear_color = sdl.FColor{0, 0, 0, 1},
		store_op = .STORE,
	}
	pass := sdl.BeginGPURenderPass(cmd, &target, 1, nil)
	Stats.draw_passes += 1
	gpu_pass_bind(st, pass, slot, width, height, dl)
	if scissored {
		sdl.SetGPUScissor(pass, scissor)
	}

	bound: ^sdl.GPUTexture = nil
	current_group := -1
	group_valid := false

	for c, i in dl.commands {
		if c.idx_count == 0 { continue }

		if c.glass {
			group := i32(-1)
			if i < len(slot.plan.command_group) { group = slot.plan.command_group[i] }
			if group < 0 { continue }

			if int(group) != current_group {
				current_group = int(group)
				group_valid = false
				sdl.EndGPURenderPass(pass)
				//* The capture is the whole window, so every level of the
				//* mip chain is valid and the shader can pick any of them.
				group_valid = gpu_capture_backdrop(cmd, slot)
				target.load_op = .LOAD
				pass = sdl.BeginGPURenderPass(cmd, &target, 1, nil)
				Stats.draw_passes += 1
				gpu_pass_bind(st, pass, slot, width, height, dl)
				if scissored {
					sdl.SetGPUScissor(pass, scissor)
				}
				bound = nil
			}

			if !group_valid { continue }

			binding := sdl.GPUTextureSamplerBinding {
				texture = slot.backdrop_tex,
				sampler = st.backdrop_sampler,
			}
			sdl.BindGPUFragmentSamplers(pass, 0, &binding, 1)
			bound = slot.backdrop_tex
			Stats.glass_commands += 1
			pixels := int(max(c.bounds.w, 0) * max(c.bounds.h, 0))
			Stats.glass_pixels += pixels
			//* One level of the chain, plus four taps for the dispersion
			//* gradient on the surfaces that ask for it, against twenty-five
			//* taps of the old kernel.
			Stats.glass_taps += pixels * (c.blur > 8 ? 5 : 9)
			sdl.DrawGPUIndexedPrimitives(pass, c.idx_count, 1, c.idx_offset, 0, 0)
			continue
		}

		tex := gpu_cmd_texture(st, c)
		if tex != bound {
			binding := sdl.GPUTextureSamplerBinding{texture = tex, sampler = st.sampler}
			sdl.BindGPUFragmentSamplers(pass, 0, &binding, 1)
			bound = tex
		}
		sdl.DrawGPUIndexedPrimitives(pass, c.idx_count, 1, c.idx_offset, 0, 0)
	}

	sdl.EndGPURenderPass(pass)
}

//* The rectangle of a scissored replay in physical pixels, and whether the
//* request can be honoured. Empty rectangles, rectangles over a third of
//* the window and requests without a valid cache fall back to a full
//* render.
gpu_partial_rect :: proc(dl: ^GUI.Draw_List, slot: ^GPU_Slot) -> (sdl.Rect, bool) {
	if dl == nil || !dl.partial || !slot.cached_valid {return {}, false}
	//* A glass surface reads the picture behind it. Outside the rectangle
	//* the scene still holds the glass of the previous frame, not the
	//* content under it, so a scissored replay would blur the old
	//* composite into the new one. A list with glass is drawn whole.
	if len(slot.plan.groups) > 0 {return {}, false}
	if slot.tex_w == 0 || slot.tex_h == 0 {return {}, false}
	r := dl.dirty_rect
	x0 := i32(max(r.x, 0))
	y0 := i32(max(r.y, 0))
	x1 := i32(min(r.x + r.w, f32(slot.tex_w)))
	y1 := i32(min(r.y + r.h, f32(slot.tex_h)))
	if x1 <= x0 || y1 <= y0 {return {}, false}
	w := x1 - x0
	h := y1 - y0
	if f32(w) * f32(h) > f32(slot.tex_w) * f32(slot.tex_h) / 3 {return {}, false}
	return sdl.Rect{x = x0, y = y0, w = w, h = h}, true
}

//* Makes sure the offscreen scene and the half resolution backdrop match
//* the window. They are kept between frames and remade only when the
//* size changes.
gpu_scene_ready :: proc(st: ^GPU_State, slot: ^GPU_Slot, w, h: u32) -> bool {
	if w == 0 || h == 0 { return false }
	if slot.scene_tex != nil && slot.backdrop_tex != nil && slot.tex_w == w && slot.tex_h == h {
		return true
	}

	if slot.scene_tex != nil {
		sdl.ReleaseGPUTexture(st.device, slot.scene_tex)
		slot.scene_tex = nil
	}
	if slot.backdrop_tex != nil {
		sdl.ReleaseGPUTexture(st.device, slot.backdrop_tex)
		slot.backdrop_tex = nil
	}
	slot.cached_valid = false

	info := sdl.GPUTextureCreateInfo {
		type                 = .D2,
		format               = st.format,
		usage                = {.SAMPLER, .COLOR_TARGET},
		width                = w,
		height               = h,
		layer_count_or_depth = 1,
		num_levels           = 1,
		sample_count         = ._1,
	}
	slot.scene_tex = sdl.CreateGPUTexture(st.device, info)
	info.width = max((w + 1) / 2, 1)
	info.height = max((h + 1) / 2, 1)
	info.num_levels = BACKDROP_MIPS
	slot.backdrop_tex = sdl.CreateGPUTexture(st.device, info)
	if slot.scene_tex == nil || slot.backdrop_tex == nil {
		if slot.scene_tex != nil {
			sdl.ReleaseGPUTexture(st.device, slot.scene_tex)
			slot.scene_tex = nil
		}
		if slot.backdrop_tex != nil {
			sdl.ReleaseGPUTexture(st.device, slot.backdrop_tex)
			slot.backdrop_tex = nil
		}
		return false
	}
	slot.tex_w = w
	slot.tex_h = h
	return true
}

//* Copies the whole scene into level zero of the backdrop and builds the
//* rest of the chain. A group shares one chain, and the shader samples an
//* explicit level of it.
gpu_capture_backdrop :: proc(
	cmd: ^sdl.GPUCommandBuffer,
	slot: ^GPU_Slot,
) -> bool {
	if slot.scene_tex == nil || slot.backdrop_tex == nil { return false }

	dw := max((slot.tex_w + 1) / 2, 1)
	dh := max((slot.tex_h + 1) / 2, 1)

	sdl.BlitGPUTexture(
		cmd,
		sdl.GPUBlitInfo {
			source      = sdl.GPUBlitRegion{texture = slot.scene_tex, w = slot.tex_w, h = slot.tex_h},
			destination = sdl.GPUBlitRegion{texture = slot.backdrop_tex, w = dw, h = dh},
			load_op     = .DONT_CARE,
			clear_color = sdl.FColor{0, 0, 0, 0},
			flip_mode   = .NONE,
			filter      = .LINEAR,
		},
	)
	sdl.GenerateMipmapsForGPUTexture(cmd, slot.backdrop_tex)

	Stats.capture_points += 1
	Stats.backdrop_blits += 1
	Stats.backdrop_pixels += int(dw) * int(dh)
	Stats.mip_generations += 1
	return true
}

gpu_blit :: proc(
	cmd: ^sdl.GPUCommandBuffer,
	src, dst: ^sdl.GPUTexture,
	w, h: u32,
) {
	if src == nil || dst == nil { return }
	sdl.BlitGPUTexture(
		cmd,
		sdl.GPUBlitInfo {
			source = sdl.GPUBlitRegion{texture = src, w = w, h = h},
			destination = sdl.GPUBlitRegion{texture = dst, w = w, h = h},
			load_op = .DONT_CARE,
			clear_color = sdl.FColor{0, 0, 0, 0},
			flip_mode = .NONE,
			filter = .NEAREST,
		},
	)
}

gpu_upload_geometry :: proc(
	st: ^GPU_State,
	cmd: ^sdl.GPUCommandBuffer,
	slot: ^GPU_Slot,
	dl: ^GUI.Draw_List,
	transfers: ^[2]^sdl.GPUTransferBuffer,
) {
	changed :=
		slot.revision != dl.revision ||
		slot.vertex_count != len(dl.vertices) ||
		slot.index_count != len(dl.indices)

	vertex_bytes := len(dl.vertices) * size_of(Vertex)
	index_bytes := len(dl.indices) * size_of(u32)
	if vertex_bytes == 0 || index_bytes == 0 { return }

	if slot.vertex_buf == nil || vertex_bytes > slot.vertex_size {
		if slot.vertex_buf != nil { sdl.ReleaseGPUBuffer(st.device, slot.vertex_buf) }
		slot.vertex_size = max(vertex_bytes, 4096)
		slot.vertex_buf = sdl.CreateGPUBuffer(
			st.device,
			sdl.GPUBufferCreateInfo{usage = {.VERTEX}, size = u32(slot.vertex_size)},
		)
		if slot.vertex_buf == nil { return }
		changed = true
	}
	if slot.index_buf == nil || index_bytes > slot.index_size {
		if slot.index_buf != nil { sdl.ReleaseGPUBuffer(st.device, slot.index_buf) }
		slot.index_size = max(index_bytes, 4096)
		slot.index_buf = sdl.CreateGPUBuffer(
			st.device,
			sdl.GPUBufferCreateInfo{usage = {.INDEX}, size = u32(slot.index_size)},
		)
		if slot.index_buf == nil { return }
		changed = true
	}

	if !changed { return }

	resize(&slot.packed, len(dl.vertices))
	for v, i in dl.vertices {
		slot.packed[i] = GUI.pack_vertex(v)
	}

	copy_pass := sdl.BeginGPUCopyPass(cmd)
	transfers[0] = upload_buffer(st, copy_pass, raw_data(slot.packed), vertex_bytes, slot.vertex_buf)
	transfers[1] = upload_buffer(st, copy_pass, raw_data(dl.indices), index_bytes, slot.index_buf)
	sdl.EndGPUCopyPass(copy_pass)

	slot.revision = dl.revision
	slot.vertex_count = len(dl.vertices)
	slot.index_count = len(dl.indices)
}

//* Uploads data into a GPU buffer. The transfer buffer is given back to
//* the caller, which frees it after the command buffer is submitted.
upload_buffer :: proc(
	st: ^GPU_State,
	copy_pass: ^sdl.GPUCopyPass,
	data: rawptr,
	size: int,
	buf: ^sdl.GPUBuffer,
) -> ^sdl.GPUTransferBuffer {
	transfer := sdl.CreateGPUTransferBuffer(
		st.device,
		sdl.GPUTransferBufferCreateInfo{usage = .UPLOAD, size = u32(size)},
	)
	if transfer == nil { return nil }

	dst := sdl.MapGPUTransferBuffer(st.device, transfer, false)
	if dst == nil {
		sdl.ReleaseGPUTransferBuffer(st.device, transfer)
		return nil
	}
	mem.copy(cast(rawptr)cast(uintptr)dst, data, size)
	sdl.UnmapGPUTransferBuffer(st.device, transfer)

	sdl.UploadToGPUBuffer(
		copy_pass,
		sdl.GPUTransferBufferLocation{transfer_buffer = transfer},
		sdl.GPUBufferRegion{buffer = buf, offset = 0, size = u32(size)},
		false,
	)
	return transfer
}

load_shader :: proc(
	device: ^sdl.GPUDevice,
	code: []u8,
	stage: sdl.GPUShaderStage,
	num_uniform_buffers: u32,
	num_samplers: u32,
) -> ^sdl.GPUShader {
	return sdl.CreateGPUShader(
		device,
		sdl.GPUShaderCreateInfo {
			code_size = uint(len(code)),
			code = raw_data(code),
			entrypoint = "main",
			format = {.SPIRV},
			stage = stage,
			num_uniform_buffers = num_uniform_buffers,
			num_samplers = num_samplers,
		},
	)
}

//* The GUI backend that draws through SDL's GPU API.
gpu_backend :: proc(ctx: rawptr) -> GUI.Backend {
	return GUI.Backend {
		ctx                    = ctx,
		create                 = gpu_create,
		destroy                = gpu_destroy,
		resize                 = gpu_resize,
		upload_texture         = gpu_upload_texture,
		upload_texture_regions = gpu_upload_texture_regions,
		destroy_texture        = gpu_destroy_texture,
		submit                 = gpu_submit,
		submit_target          = gpu_submit_target,
		release_target         = gpu_release_target,
		invalidate             = gpu_invalidate,
		open_url               = open_url,
		supports_shapes        = true,
		supports_backdrop_blur = true,
	}
}
