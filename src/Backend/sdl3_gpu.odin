//* The SDL3 GPU backend.
//
//* This is where the renderer-agnostic design pays off: one
//* implementation of the draw list serves Vulkan, D3D11, D3D12, Metal
//* and OpenGL, because SDL's GPU API abstracts them. The device is
//* chosen by SDL from the shader format the UI needs.
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

GPU_State :: struct {
	device:   ^sdl.GPUDevice,
	window:   ^sdl.Window,
	pipeline: ^sdl.GPUGraphicsPipeline,
	sampler:  ^sdl.GPUSampler,

	textures: [dynamic]^sdl.GPUTexture,

	vertex_buf:  ^sdl.GPUBuffer,
	index_buf:   ^sdl.GPUBuffer,
	vertex_size: int,
	index_size:  int,

	width:  f32,
	height: f32,

	//* The windows of the floating panels. They share the device and
	//* the textures with the main window.
	targets: [dynamic]GPU_Target,
}

//* A floating panel: its window and the size of its swapchain.
GPU_Target :: struct {
	window: ^sdl.Window,
	width:  f32,
	height: f32,
}

gpu_create :: proc(ctx, window: rawptr, w, h: i32) -> bool {
	st := cast(^GPU_State)ctx
	st.window = cast(^sdl.Window)window
	st.width = f32(w)
	st.height = f32(h)

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

	//* The atlas is the one texture of the UI. It is made by the first
	//* upload, which the GUI does when it flushes the atlas.
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

	if st.vertex_buf != nil { sdl.ReleaseGPUBuffer(st.device, st.vertex_buf) }
	if st.index_buf != nil { sdl.ReleaseGPUBuffer(st.device, st.index_buf) }
	if st.sampler != nil { sdl.ReleaseGPUSampler(st.device, st.sampler) }
	if st.pipeline != nil { sdl.ReleaseGPUGraphicsPipeline(st.device, st.pipeline) }
	if st.device != nil { sdl.DestroyGPUDevice(st.device) }

	st^ = {}
}

gpu_resize :: proc(ctx: rawptr, w, h: i32) -> bool {
	st := cast(^GPU_State)ctx
	if st == nil { return false }
	st.width = f32(w)
	st.height = f32(h)
	return true
}

//* Creates or updates a texture and uploads its pixels.
gpu_upload_texture :: proc(ctx: rawptr, id: GUI.Texture_ID, pixels: []u8, w, h: i32) -> bool {
	return gpu_upload_region(ctx, id, pixels, w, h, 0, 0)
}

//* Uploads a part of a texture. The atlas is far too big to be sent
//* again every time one glyph changes, so only the part that changed
//* goes up.
gpu_upload_texture_region :: proc(
	ctx: rawptr,
	id: GUI.Texture_ID,
	pixels: []u8,
	w, h, x, y: i32,
) -> bool {
	return gpu_upload_region(ctx, id, pixels, w, h, x, y)
}

//* The upload itself: the texture is made when it is not there yet,
//* and the pixels are put into the region that is asked for.
gpu_upload_region :: proc(
	ctx: rawptr,
	id: GUI.Texture_ID,
	pixels: []u8,
	w, h, x, y: i32,
) -> bool {
	st := cast(^GPU_State)ctx
	if st == nil || st.device == nil { return false }
	if w <= 0 || h <= 0 { return false }
	if len(pixels) < int(w) * int(h) * 4 { return false }

	idx := int(id)
	for len(st.textures) <= idx {
		append(&st.textures, nil)
	}

	tex := st.textures[idx]
	if tex == nil {
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
		if tex == nil { return false }
		st.textures[idx] = tex
	}

	//* The rows of the region follow each other: the transfer says how
	//* many pixels there are in a row, and that is the stride.
	row_bytes := int(w) * 4
	size := row_bytes * int(h)

	transfer := sdl.CreateGPUTransferBuffer(
		st.device,
		sdl.GPUTransferBufferCreateInfo{usage = .UPLOAD, size = u32(size)},
	)
	if transfer == nil { return false }

	dst := sdl.MapGPUTransferBuffer(st.device, transfer, false)
	mem.copy(dst, raw_data(pixels), size)
	sdl.UnmapGPUTransferBuffer(st.device, transfer)

	cmd := sdl.AcquireGPUCommandBuffer(st.device)
	copy_pass := sdl.BeginGPUCopyPass(cmd)
	sdl.UploadToGPUTexture(
		copy_pass,
		sdl.GPUTextureTransferInfo {
			transfer_buffer = transfer,
			offset = 0,
			pixels_per_row = u32(w),
			rows_per_layer = u32(h),
		},
		sdl.GPUTextureRegion {
			texture = tex,
			x = u32(max(x, 0)),
			y = u32(max(y, 0)),
			w = u32(w),
			h = u32(h),
			d = 1,
		},
		false,
	)
	sdl.EndGPUCopyPass(copy_pass)
	if !sdl.SubmitGPUCommandBuffer(cmd) { return false }
	sdl.ReleaseGPUTransferBuffer(st.device, transfer)
	return true
}

gpu_submit :: proc(ctx: rawptr, dl: ^GUI.Draw_List) {
	st := cast(^GPU_State)ctx
	if st == nil || st.device == nil { return }
	gpu_render(st, st.window, st.width, st.height, dl)
}

//* Renders a draw list into the window of a floating panel. The window
//* is given a swapchain the first time it is used.
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
		w, h: i32
		sdl.GetWindowSizeInPixels(handle, &w, &h)
		append(&st.targets, GPU_Target{window = handle, width = f32(w), height = f32(h)})
		index = len(st.targets) - 1
	}
	target := st.targets[index]
	gpu_render(st, target.window, target.width, target.height, dl)
}

//* Draws a list into one window.
gpu_render :: proc(st: ^GPU_State, window: ^sdl.Window, width, height: f32, dl: ^GUI.Draw_List) {
	// Upload the geometry.
	vertex_bytes := len(dl.vertices) * size_of(Vertex)
	index_bytes := len(dl.indices) * size_of(u32)
	if vertex_bytes > 0 {
		st.vertex_buf = ensure_buffer(
			st,
			raw_data(dl.vertices),
			vertex_bytes,
			{.VERTEX},
			st.vertex_buf,
			&st.vertex_size,
		)
	}
	if index_bytes > 0 {
		st.index_buf = ensure_buffer(
			st,
			raw_data(dl.indices),
			index_bytes,
			{.INDEX},
			st.index_buf,
			&st.index_size,
		)
	}
	if st.vertex_buf == nil || st.index_buf == nil { return }

	cmd_buf := sdl.AcquireGPUCommandBuffer(st.device)
	swapchain: ^sdl.GPUTexture
	if !sdl.WaitAndAcquireGPUSwapchainTexture(cmd_buf, window, &swapchain, nil, nil) { return }

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

	sdl.BindGPUVertexBuffers(pass, 0, &(sdl.GPUBufferBinding{buffer = st.vertex_buf}), 1)
	sdl.BindGPUIndexBuffer(pass, sdl.GPUBufferBinding{buffer = st.index_buf}, ._32BIT)

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
	if !sdl.SubmitGPUCommandBuffer(cmd_buf) { return }
}

//* Uploads `data` into a GPU buffer, recreating the buffer when the
//* data outgrows it.
ensure_buffer :: proc(
	st: ^GPU_State,
	data: rawptr,
	size: int,
	usage: sdl.GPUBufferUsageFlags,
	buf: ^sdl.GPUBuffer,
	capacity: ^int,
) -> ^sdl.GPUBuffer {
	if size <= 0 { return buf }

	out := buf
	if out == nil || size > capacity^ {
		if out != nil { sdl.ReleaseGPUBuffer(st.device, out) }
		capacity^ = max(size, 4096)
		out = sdl.CreateGPUBuffer(
			st.device,
			sdl.GPUBufferCreateInfo{usage = usage, size = u32(capacity^)},
		)
		if out == nil { return nil }
	}

	transfer := sdl.CreateGPUTransferBuffer(
		st.device,
		sdl.GPUTransferBufferCreateInfo{usage = .UPLOAD, size = u32(size)},
	)
	if transfer == nil { return out }

	dst := sdl.MapGPUTransferBuffer(st.device, transfer, false)
	mem.copy(dst, data, size)
	sdl.UnmapGPUTransferBuffer(st.device, transfer)

	cmd := sdl.AcquireGPUCommandBuffer(st.device)
	copy_pass := sdl.BeginGPUCopyPass(cmd)
	sdl.UploadToGPUBuffer(
		copy_pass,
		sdl.GPUTransferBufferLocation{transfer_buffer = transfer},
		sdl.GPUBufferRegion{buffer = out, offset = 0, size = u32(size)},
		false,
	)
	sdl.EndGPUCopyPass(copy_pass)
	if !sdl.SubmitGPUCommandBuffer(cmd) { return out }
	sdl.ReleaseGPUTransferBuffer(st.device, transfer)
	return out
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
