//* == gallery ==
//* The scene that shows what CalcUI can do: every kind of widget of the
//* toolkit, in labelled sections, in a column that the wheel scrolls.
//*   odin run examples\01_gallery

package main

import "core:log"
import App "../../src/App"
import GUI "../../src/GUI"

import "core:mem"
import "core:fmt"

main :: proc() {
    when ODIN_DEBUG {
        track: mem.Tracking_Allocator
        mem.tracking_allocator_init(&track, context.allocator)
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
                for _, entry in track.bad_free_array {
                    fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
                }
            }
        }
    }

    App.Run("CalcUI - Gallery", 1000, 700, setup, nil)
    log.info("the gallery is done")
}   

//* The gallery widget setup proc.
setup :: proc(app: ^App.App) {
	Init_Gallery(app.gui, app.family)
}
