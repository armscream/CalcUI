//* == gallery ==
//* The scene that shows what CalcUI can do: every kind of widget of the
//* toolkit, in labelled sections, in a column that the wheel scrolls.
//*   odin run examples\01_gallery

package main

import "core:log"
import App "../../src/App"
import Backend "../../src/Backend"
import GUI "../../src/GUI"

import "core:mem"
import "core:fmt"

main :: proc() {
    when ODIN_DEBUG {
        track: mem.Tracking_Allocator
        mem.tracking_allocator_init(&track, context.allocator)
        track.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array
        defer mem.tracking_allocator_destroy(&track)
        context.allocator = mem.tracking_allocator(&track)

        defer {
            if len(track.allocation_map) > 0 {
                fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
                for _, entry in track.allocation_map {
                    fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
                }
            }
            if len(track.bad_free_array) > 0 {
                fmt.eprintf("=== %v bad frees: ===\n", len(track.bad_free_array))
                for entry in track.bad_free_array {
                    fmt.eprintf("- %v\n", entry)
                }
            }
        }
    }

    App.Run("CalcUI - Gallery", 1000, 700, setup, nil)
    log.info("the gallery is done")
}    

//* The gallery widget setup proc.
setup :: proc(app: ^App.App) {
    //* The sound of the gallery: it is false when there is no sound card,
    //* and the GUI stays usable without it.
    Backend.sdl3_audio_install(app.gui)
    Init_Gallery(app.gui, app.family)
}
