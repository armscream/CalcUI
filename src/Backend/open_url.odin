//* The links of the toolkit: a link is opened by SDL, so it does not
//* matter which backend draws the pixels.
package Backend

import sdl "vendor:sdl3"
import "core:strings"

//* Opens a link in the browser of the system. Gives false back when the
//* link could not be opened.
open_url :: proc(ctx: rawptr, url: string) -> bool {
	_ = ctx
	return sdl.OpenURL(strings.clone_to_cstring(url, context.temp_allocator))
}
