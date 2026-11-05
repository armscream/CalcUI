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

//* The vertex layout has to match the GUI's Draw_Vertex exactly.
Vertex :: GUI.Draw_Vertex

//* Matches the uniform block in the vertex shader.
UBO :: struct {
	viewport: [2]f32,
}

//* What a target needs to draw a list of its own: the buffers of its
//* geometry and the size of its window.
GPU_Slot :: struct {
	vertex_buf:  ^sdl.GPUBuffer,
	index_buf:   ^sdl.GPUBuffer,
	vertex_size: int,
	index_size:  int,
	//* The geometry that was uploaded last. A list that did not change
	//* is not sent again.
	vertices:    []GUI.Draw_Vertex,
	indices:     []u32,
	width:       f32,
	height:      f32,
}

GPU_State :: struct {
	device:   ^sdl.GPUDevice,
	window:   ^sdl.Window,
	pipeline: ^sdl.GPUGraphicsPipeline,
	sampler:  ^sdl.GPUSampler,

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
	frag := load_shader(device, frag_shader_code, .FRAGMENT, 0, 1)
	if vert == nil || frag == nil { return false }

	vertex_attrs := []sdl.GPUVertexAttribute{
		{location = 0, format = .FLOAT2, offset = u32(offset_of(Vertex, pos))},
		{location = 1, format = .FLOAT2, offset = u32(offset_of(Vertex, uv))},
		{location = 2, format = .FLOAT4, offset = u32(offset_of(Vertex, colour))},
		{location = 3, format = .FLOAT4, offset = u32(offset_of(Vertex, shape))},
		{location = 4, format = .FLOAT2, offset = u32(offset_of(Vertex, local))},
	}

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
					format = sdl.GetGPUSwapchainTextureFormat(device, st.window),
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

	append(&st.slots, GPU_Slot{width = f32(w), height = f32(h)})
	return true
}

gpu_destroy :: proc(ctx: rawptr) {
	st := cast(^GPU_State)ctx
	if st == nil { return }

	for tex in st.textures {
		if tex != nil { sdl.ReleaseGPUTexture(st.device, tex) }
	}
	clear(&st.textures)
	delete(st.textures)

	for &slot in st.slots {
		if slot.vertex_buf != nil { sdl.ReleaseGPUBuffer(st.device, slot.vertex_buf) }
		if slot.index_buf != nil { sdl.ReleaseGPUBuffer(st.device, slot.index_buf) }
		delete(slot.vertices)
		delete(slot.indices)
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
	if st.pipeline != nil { sdl.ReleaseGPUGraphicsPipeline(st.device, st.pipeline) }
	if st.device != nil { sdl.DestroyGPUDevice(st.device) }

	st^ = {}
}

gpu_resize :: proc(ctx: rawptr, w, h: i32) -> bool {
	st := cast(^GPU_State)ctx
	if st == nil { return false }
	if len(st.slots) == 0 { return false }
	st.slots[0].width = f32(w)
	st.slots[0].height = f32(h)
	return true
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

	cmd_buf := sdl.AcquireGPUCommandBuffer(st.device)
	swapchain: ^sdl.GPUTexture
	if !sdl.WaitAndAcquireGPUSwapchainTexture(cmd_buf, window, &swapchain, nil, nil) {
		_ = sdl.SubmitGPUCommandBuffer(cmd_buf)
		return
	}

	//* The geometry goes up in the same command buffer as the drawing.
	transfers: [2]^sdl.GPUTransferBuffer
	gpu_upload_geometry(st, cmd_buf, slot, dl, &transfers)

	colour_target := sdl.GPUColorTargetInfo {
		texture = swapchain,
		load_op = .CLEAR,
		clear_color = sdl.FColor{0, 0, 0, 1},
		store_op = .STORE,
	}

	pass := sdl.BeginGPURenderPass(cmd_buf, &colour_target, 1, nil)
	sdl.BindGPUGraphicsPipeline(pass, st.pipeline)
	sdl.SetGPUViewport(
		pass,
		sdl.GPUViewport{x = 0, y = 0, w = width, h = height, min_depth = 0, max_depth = 1},
	)

	ubo := UBO{viewport = {width, height}}
	sdl.PushGPUVertexUniformData(cmd_buf, 0, &ubo, size_of(ubo))

	empty := len(dl.vertices) == 0 || len(dl.indices) == 0
	if !empty {
		sdl.BindGPUVertexBuffers(pass, 0, &(sdl.GPUBufferBinding{buffer = slot.vertex_buf}), 1)
		sdl.BindGPUIndexBuffer(pass, sdl.GPUBufferBinding{buffer = slot.index_buf}, ._32BIT)
	}

	//* The clip is already worked out in the draw list, so there is no
	//* scissor here. Everything the window shows comes out of the one
	//* atlas, so the texture is bound once and the whole window is one
	//* draw call.
	bound: ^sdl.GPUTexture = nil
	for cmd in dl.commands {
		if cmd.idx_count == 0 { continue }

		tex: ^sdl.GPUTexture = nil
		if int(cmd.texture) < len(st.textures) { tex = st.textures[cmd.texture] }
		if tex != bound {
			binding := sdl.GPUTextureSamplerBinding{texture = tex, sampler = st.sampler}
			sdl.BindGPUFragmentSamplers(pass, 0, &binding, 1)
			bound = tex
		}

		sdl.DrawGPUIndexedPrimitives(pass, cmd.idx_count, 1, cmd.idx_offset, 0, 0)
	}

	sdl.EndGPURenderPass(pass)
	_ = sdl.SubmitGPUCommandBuffer(cmd_buf)

	//* The transfer buffers live until the command buffer is done.
	for transfer in transfers {
		if transfer != nil { sdl.ReleaseGPUTransferBuffer(st.device, transfer) }
	}
}

//* Puts the geometry of a list into the buffers of a target. A list
//* that did not change is not sent again.
gpu_upload_geometry :: proc(
	st: ^GPU_State,
	cmd: ^sdl.GPUCommandBuffer,
	slot: ^GPU_Slot,
	dl: ^GUI.Draw_List,
	transfers: ^[2]^sdl.GPUTransferBuffer,
) {
	changed :=
		len(slot.vertices) != len(dl.vertices) ||
		len(slot.indices) != len(dl.indices) ||
		!same_bytes(raw_data(slot.vertices), raw_data(dl.vertices), len(dl.vertices) * size_of(GUI.Draw_Vertex)) ||
		!same_bytes(raw_data(slot.indices), raw_data(dl.indices), len(dl.indices) * size_of(u32))

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

	copy_pass := sdl.BeginGPUCopyPass(cmd)
	transfers[0] = upload_buffer(st, copy_pass, raw_data(dl.vertices), vertex_bytes, slot.vertex_buf)
	transfers[1] = upload_buffer(st, copy_pass, raw_data(dl.indices), index_bytes, slot.index_buf)
	sdl.EndGPUCopyPass(copy_pass)

	//* The copy is only kept when the geometry really went up.
	keep_geometry(slot, dl)
}

same_bytes :: proc(a, b: rawptr, n: int) -> bool {
	if n <= 0 { return true }
	return mem.compare_ptrs(a, b, n) == 0
}

//* Keeps a copy of the geometry, so the next frame can tell whether it
//* changed.
keep_geometry :: proc(slot: ^GPU_Slot, dl: ^GUI.Draw_List) {
	if len(slot.vertices) != len(dl.vertices) {
		delete(slot.vertices)
		slot.vertices = make([]GUI.Draw_Vertex, len(dl.vertices))
	}
	if len(slot.indices) != len(dl.indices) {
		delete(slot.indices)
		slot.indices = make([]u32, len(dl.indices))
	}
	copy(slot.vertices[:], dl.vertices[:])
	copy(slot.indices[:], dl.indices[:])
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
