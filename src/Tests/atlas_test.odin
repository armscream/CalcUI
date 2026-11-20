//* The atlas adds pages instead of growing one, so a retained draw list
//* keeps the UVs it was built with.

package Tests

import GUI "../GUI"
import "core:testing"

@(test)
test_atlas_pages_are_added_and_keep_their_uvs :: proc(t: ^testing.T) {
	a := GUI.atlas_make(64, 64, 4)
	defer GUI.atlas_destroy(a)

	regions: [4]GUI.Atlas_Region
	for i in 0 ..< len(regions) {
		//* A pinned region is never thrown out, so the next request has to
		//* open a new page.
		regions[i] = GUI.atlas_alloc(a, 48, 48, true)
		testing.expect(t, regions[i].id >= 0, "the atlas ran out of pages")
		testing.expect_value(t, regions[i].page, u16(i))
	}

	testing.expect_value(t, len(a.pages), 4)
	testing.expect(
		t,
		GUI.atlas_texture_for(regions[0]) != GUI.atlas_texture_for(regions[1]),
		"two pages shared a texture",
	)

	//* A sub-rectangle is scaled by the page it lives on, not by another.
	uv := GUI.atlas_region_uv_inside(a, regions[1], 0, 0, 48, 48)
	testing.expect_value(t, uv[2], f32(48) / f32(64))
	testing.expect_value(t, uv[3], f32(48) / f32(64))

	//* The limit is honoured: a fifth page is not made.
	full := GUI.atlas_alloc(a, 48, 48, true)
	testing.expect_value(t, full.id, -1)
}

@(test)
test_atlas_region_uv_uses_page_size :: proc(t: ^testing.T) {
	a := GUI.atlas_make(128, 128)
	defer GUI.atlas_destroy(a)

	region := GUI.atlas_alloc(a, 16, 16, false)
	testing.expect(t, region.id >= 0)
	uv := GUI.atlas_region_uv_inside(a, region, 8, 8, 8, 8)
	testing.expect_value(t, uv[0], f32(region.x + 8) / f32(128))
	testing.expect_value(t, uv[1], f32(region.y + 8) / f32(128))
}

@(test)
test_atlas_drops_the_cpu_mirror_after_the_first_upload :: proc(t: ^testing.T) {
	a := GUI.atlas_make(64, 64)
	defer GUI.atlas_destroy(a)
	state := Mock_State{}
	backend := mock_backend
	backend.ctx = &state

	GUI.atlas_flush(a, backend)
	testing.expect(t, a.pages[0].uploaded)
	testing.expect(t, a.pages[0].pixels == nil, "the mirror was kept after the first upload")

	//* A later write goes into the staging buffer, not a mirror.
	region := GUI.atlas_alloc(a, 8, 8, false)
	testing.expect(t, region.id >= 0)
	pixels := make([]u8, 8 * 8 * 4)
	defer delete(pixels)
	GUI.atlas_write(a, region, pixels)
	testing.expect_value(t, len(a.pages[0].stage), 8 * 8 * 4)

	GUI.atlas_flush(a, backend)
	testing.expect_value(t, len(a.pages[0].stage), 0)
	testing.expect_value(t, state.region_uploads, 1)
}

@(test)
test_atlas_keeps_the_mirror_without_regional_uploads :: proc(t: ^testing.T) {
	a := GUI.atlas_make(64, 64)
	defer GUI.atlas_destroy(a)
	backend := mock_backend
	backend.upload_texture_regions = nil

	GUI.atlas_flush(a, backend)
	testing.expect(t, a.pages[0].uploaded)
	testing.expect(t, a.pages[0].pixels != nil, "the mirror was dropped without regional uploads")
}

@(test)
test_trim_releases_empty_atlas_pages :: proc(t: ^testing.T) {
	g := test_gui(t)
	defer test_gui_destroy(g)
	state := Mock_State{}
	g.backend = mock_backend
	g.backend.ctx = &state

	//* Make the page bigger than the default so a second page is needed.
	region := GUI.atlas_alloc(g.atlas, GUI.ATLAS_DEFAULT_SIZE * 2, 16, true)
	testing.expect(t, region.id >= 0)
	testing.expect_value(t, GUI.atlas_page_count(g.atlas), 2)
	GUI.atlas_flush(g.atlas, g.backend)

	GUI.atlas_free(g.atlas, region)
	GUI.GUI_Trim_Memory(g)
	testing.expect_value(t, GUI.atlas_page_count(g.atlas), 1)
	testing.expect(t, state.destroyed >= 1, "the texture of the empty page was not released")
}
