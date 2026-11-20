//* The memory report is a regression gate: it states the fixed sizes and
//* the per-widget cost, so a change that grows either one is seen.

package Tests

import GUI "../GUI"
import "core:fmt"
import "core:testing"

@(test)
test_memory_stats_10k_widgets :: proc(t: ^testing.T) {
	g := test_gui(t)
	defer test_gui_destroy(g)

	for _ in 0 ..< 10_000 {
		GUI.New_Widget(g, .Panel, g.root, GUI.Widget_Opts{})
	}

	stats := GUI.GUI_Memory_Stats(g)
	fmt.printfln(
		"memory 10k: widget %d B, style %d B, style cache %d B, widget bytes %d B, arena %d B",
		stats.widget_size,
		stats.style_size,
		stats.style_cache_size,
		stats.widget_bytes,
		stats.arena_committed,
	)
	testing.expect_value(t, stats.widget_slots, 10_001)
	testing.expect_value(t, stats.live_widgets, 10_001)
	testing.expect_value(t, stats.widget_bytes, 10_001 * stats.widget_size)

	//* The style cache keeps the source style of the widget and the ids of
	//* the two resolved ones, not seven full styles.
	testing.expect(
		t,
		stats.style_cache_size <= stats.style_size + 96,
		"the style cache kept more than one full style",
	)
	testing.expect(t, stats.widget_size <= 2048, "the widget grew past two kilobytes")
}
