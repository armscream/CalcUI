//* The nil-safe way to call the procedures of a backend, and the check
//* that says whether a backend can draw at all. A program that gives the
//* toolkit a backend of its own never has to test the procedures of the
//* backend itself.
package GUI

import "core:log"

//* Checks the procedures of a backend and says whether it can draw at
//* all. A backend that cannot draw has no 'submit', and a backend that
//* cannot draw text has no 'upload_texture'. The check says nothing and
//* writes nothing: a program that wants to know what is missing asks
//* `Backend_Report` for the details.
Backend_Validate :: proc(b: Backend) -> bool {
	if b.submit == nil { return false }
	if b.upload_texture == nil { return false }
	return true
}

//* Reports the procedures of a backend that are missing: the ones that
//* are needed as errors, the ones that may be left out as warnings.
Backend_Report :: proc(b: Backend) {
	if b.submit == nil {
		log.error("backend: no 'submit': nothing can be drawn")
	}
	if b.upload_texture == nil {
		log.error("backend: no 'upload_texture': no text can be drawn")
	}

	if b.create == nil {
		log.warn("backend: no 'create': the backend cannot be made")
	}
	if b.destroy == nil {
		log.warn("backend: no 'destroy': the backend cannot be given back")
	}
	if b.resize == nil {
		log.warn("backend: no 'resize': the window cannot be resized")
	}
	if b.upload_texture_regions == nil {
		log.warn("backend: no 'upload_texture_regions': the atlas is uploaded in one piece")
	}
	if b.destroy_texture == nil {
		log.warn("backend: no 'destroy_texture': the textures are not given back")
	}
	if b.submit_target == nil {
		log.warn("backend: no 'submit_target': the floating panels cannot be drawn")
	}
}

//* Makes the backend for a window of the given size in pixels. Returns
//* false when the backend has no 'create' or when it could not be made.
Backend_Create :: proc(b: Backend, window: rawptr, w, h: i32) -> bool {
	if b.create == nil { return false }
	return b.create(b.ctx, window, w, h)
}

//* Gives the backend back. Does nothing when the backend has no 'destroy'.
Backend_Destroy :: proc(b: Backend) {
	if b.destroy == nil { return }
	b.destroy(b.ctx)
}

//* Tells the backend that the window is of another size in pixels. Returns
//* false when the backend has no 'resize'.
Backend_Resize :: proc(b: Backend, w, h: i32) -> bool {
	if b.resize == nil { return false }
	return b.resize(b.ctx, w, h)
}

//* Puts the pixels of a texture into the backend. Returns false when the
//* backend has no 'upload_texture'.
Backend_Upload_Texture :: proc(b: Backend, id: Texture_ID, pixels: []u8, w, h: i32) -> bool {
	if b.upload_texture == nil { return false }
	return b.upload_texture(b.ctx, id, pixels, w, h)
}

//* Gives a texture back to the backend. Does nothing when the backend has
//* no 'destroy_texture'.
Backend_Destroy_Texture :: proc(b: Backend, id: Texture_ID) {
	if b.destroy_texture == nil { return }
	b.destroy_texture(b.ctx, id)
}

//* Draws a draw list. Does nothing when the backend has no 'submit'.
Backend_Submit :: proc(b: Backend, dl: ^Draw_List) {
	if b.submit == nil { return }
	b.submit(b.ctx, dl)
}

//* Draws a draw list in a window of its own. Does nothing when the backend
//* has no 'submit_target'.
Backend_Submit_Target :: proc(b: Backend, dl: ^Draw_List, window: rawptr) {
	if b.submit_target == nil { return }
	b.submit_target(b.ctx, dl, window)
}
