//* == The gallery ==
//* The scene that shows what CalcUI can do: a toolbar, two panels that
//* can be docked into each other, and a showcase of the text.

package main

import "core:log"
import common "../common"
import GUI "../../src/GUI"

main :: proc() {
	common.Run(
		"CalcUI - Gallery",
		900,
		620,
		proc(app: ^common.App) {
			Init_Demo(app.gui, app.family)
		},
		nil,
	)
	log.info("the gallery is done")
}
