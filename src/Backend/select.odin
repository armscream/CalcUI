//* Picks the SDL3 backend an application asked for and falls back from the
//* GPU to the renderer when the choice was automatic.

package Backend

import GUI "../GUI"
import "core:log"

create_backend :: proc(
	choice: GUI.Backend_Choice,
	gpu_ctx, renderer_ctx: rawptr,
	window: rawptr,
	w, h: i32,
) -> (GUI.Backend, bool) {
	if choice != .Renderer {
		log.info("backend: SDL3 GPU")
		backend := gpu_backend(gpu_ctx)
		if GUI.Backend_Create(backend, window, w, h) {
			return backend, true
		}
		GUI.Backend_Destroy(backend)
		if choice == .GPU {
			log.error("the GPU backend could not be made")
			return {}, false
		}
		log.info("backend: the SDL3 GPU could not be made; using the SDL3 renderer")
	}

	log.info("backend: SDL3 renderer")
	backend := renderer_backend(renderer_ctx)
	if !GUI.Backend_Create(backend, window, w, h) {
		log.error("the backend could not be made")
		return {}, false
	}
	return backend, true
}
