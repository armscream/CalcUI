# CalcUI Benchmarks

CalcUI includes a small benchmark suite that measures the main parts of the toolkit: drawing, layout, styling, text, frames, lifecycle work and virtualized widgets. The numbers below show what the library costs on a typical laptop and give a baseline for spotting regressions.

## Method

Each benchmark builds a fixed scene once, runs it a few times to warm up, then measures the same operation repeatedly. The tables report the median of those runs, with the fastest run beside it. Every timing is for one operation and is given in milliseconds. The scenes are built headlessly, so no window or GPU is needed.

Results depend on the machine, the compiler and the optimization level. The reference run used `-o:speed` on a laptop, matching a normal application build. A faster desktop CPU should produce lower numbers. Treat these values as a relative baseline, not an absolute limit.

## What is measured

| ID | Group | What it measures |
|---|---|---|
| `draw.buttons_200` | draw | Draw-list generation for 200 buttons. |
| `draw.panels_400` | draw | Draw-list generation for 400 panels with backgrounds and borders. |
| `draw.labels_60` | draw | Draw-list generation for 60 long-text labels, including shaping and placement. |
| `draw.clip_labels_60` | draw | The same labels inside a rounded clip they never cross, so the shape clipper stays on the fast path. |
| `draw.pack_vertices` | draw | Packing the vertices of a draw list into the compact GPU form, without uploading them. |
| `draw.shadow_panels_200` | draw | 200 rounded panels, each with one outer SDF shadow and spread. |
| `draw.side_borders_200` | draw | 200 rounded panels whose four borders have four colours, which needs strip geometry. |
| `draw.rounded_panels_200` | draw | Draw-list generation for 200 rounded panels using shader-based corners. |
| `draw.rounded_panels_200_cpu` | draw | The same scene using CPU-based rounded corners. |
| `draw.glass_panels_200` | draw | 200 glass panels with the optical stack, each a standalone command. |
| `draw.glass_nested_100` | draw | 100 glass panels with a smaller glass panel inside each, so the backdrop plan splits the captures per nesting level. |
| `layout.panels_400` | layout | Full layout of 400 panels with every widget marked dirty. |
| `layout.panels_400_one` | layout | Incremental layout after one widget changes. |
| `style.panels_400_colour` | style | Style resolution, including backgrounds and text colours, for 400 panels. |
| `frame.buttons_200` | frame | Full frame update, layout and draw-list generation for 200 buttons. |
| `frame.buttons_200_idle` | frame | Idle frame processing with no changes. |
| `lifecycle.gui_100_widgets` | lifecycle | GUI creation, addition of 100 widgets, layout and destruction with a 1024x1024 atlas. |
| `lifecycle.atlas` | lifecycle | Creation and destruction of a 1024x1024 glyph atlas (4 MB). |
| `lifecycle.atlas_64` | lifecycle | Allocation and release of a 64×64 region in a 512×512 atlas. |
| `widgets.virtual_list_1000` | widgets | Draw-list generation for a 1,000-row virtual list. Only visible rows are requested. |
| `widgets.virtual_list_10000` | widgets | The same test with 10,000 rows. |
| `widgets.virtual_list_100000` | widgets | The same test with 100,000 rows. |
| `widgets.virtual_list_1000000` | widgets | The same test with 1,000,000 rows. |
| `widgets.data_table_1000` | widgets | Draw-list generation for a 1,000-row data table. Only visible rows are requested. |
| `widgets.data_table_10000` | widgets | The same test with 10,000 rows. |
| `widgets.data_table_100000` | widgets | The same test with 100,000 rows. |
| `widgets.data_table_1000000` | widgets | The same test with 1,000,000 rows. |
| `widgets.virtual_list_mixed_100000` | widgets | Draw-list generation for a 100,000-row virtual list with variable row heights. |

## Reference results

The reference run used:

- **OS:** Windows 11 Pro
- **CPU:** Intel64 Family 6 Model 122 Stepping 8, GenuineIntel
- **Compiler:** Odin `dev-2026-10`
- **Build:** `-o:speed`

All times are in milliseconds. Median is the typical cost of one operation; minimum is the fastest recorded run. Logical bytes are the `Draw_Vertex` size of the list; packed bytes are the compact `Packed_Vertex` size the GPU uploads.

| ID | Runs | Median (ms) | Min (ms) | Vertices | Logical bytes | Packed bytes | Commands |
|---|---:|---:|---:|---:|---:|---:|---:|
| `draw.buttons_200` | 200 | 2.34 | 1.84 | 3184 | 305664 | 191040 | 1 |
| `draw.panels_400` | 200 | 1.97 | 1.55 | 8000 | 768000 | 480000 | 1 |
| `draw.labels_60` | 50 | 2.34 | 1.91 | 8400 | 806400 | 504000 | 1 |
| `draw.clip_labels_60` | 50 | 3.52 | 2.62 | 8407 | 807072 | 504420 | 1 |
| `draw.pack_vertices` | 100 | 0.457 | 0.384 | 4200 | 403200 | 252000 | 1 |
| `draw.shadow_panels_200` | 100 | 0.608 | 0.438 | 1600 | 153600 | 96000 | 1 |
| `draw.side_borders_200` | 50 | 3.37 | 2.57 | 27362 | 2626752 | 1641720 | 1 |
| `draw.rounded_panels_200` | 100 | 0.470 | 0.378 | 800 | 76800 | 48000 | 1 |
| `draw.rounded_panels_200_cpu` | 100 | 1.06 | 0.864 | 4200 | 403200 | 252000 | 1 |
| `draw.glass_panels_200` | 100 | 0.531 | 0.414 | 800 | 76800 | 48000 | 200 |
| `draw.glass_nested_100` | 50 | 0.485 | 0.389 | 800 | 76800 | 48000 | 200 |
| `layout.panels_400` | 200 | 0.253 | 0.211 | 8000 | 768000 | 480000 | 1 |
| `layout.panels_400_one` | 200 | 0.103 | 0.094 | 8000 | 768000 | 480000 | 1 |
| `style.panels_400_colour` | 200 | 0.888 | 0.488 | 8000 | 768000 | 480000 | 1 |
| `frame.buttons_200` | 100 | 2.53 | 1.91 | 3184 | 305664 | 191040 | 1 |
| `frame.buttons_200_idle` | 100 | 0.0284 | 0.0232 | 3184 | 305664 | 191040 | 1 |
| `lifecycle.gui_100_widgets` | 20 | 41.04 | 16.68 | 0 | 0 | 0 | 0 |
| `lifecycle.atlas` | 20 | 26.16 | 15.51 | 0 | 0 | 0 | 0 |
| `lifecycle.atlas_64` | 2000 | 0.0003 | 0.0003 | 0 | 0 | 0 | 0 |
| `widgets.virtual_list_1000` | 50 | 0.153 | 0.142 | 480 | 46080 | 28800 | 1 |
| `widgets.virtual_list_10000` | 50 | 0.150 | 0.141 | 480 | 46080 | 28800 | 1 |
| `widgets.virtual_list_100000` | 50 | 0.158 | 0.144 | 480 | 46080 | 28800 | 1 |
| `widgets.virtual_list_1000000` | 50 | 0.189 | 0.148 | 480 | 46080 | 28800 | 1 |
| `widgets.data_table_1000` | 50 | 0.161 | 0.133 | 500 | 48000 | 30000 | 1 |
| `widgets.data_table_10000` | 50 | 0.176 | 0.142 | 500 | 48000 | 30000 | 1 |
| `widgets.data_table_100000` | 50 | 0.169 | 0.151 | 500 | 48000 | 30000 | 1 |
| `widgets.data_table_1000000` | 50 | 0.147 | 0.131 | 500 | 48000 | 30000 | 1 |
| `widgets.virtual_list_mixed_100000` | 50 | 0.142 | 0.120 | 384 | 36864 | 23040 | 1 |

## Notes

The virtual list and data table benchmarks run at four row counts, from 1,000 to 1,000,000. Their cost follows the visible rows rather than the total, which is what makes the virtualized widgets usable with very large data sets.

The rounded panel pair checks the CPU fallback: it generates more vertices than the shader path, because each corner becomes geometry. Packing reduces a vertex from 96 logical bytes to 60, or 62.5% of the logical size.

`draw.clip_labels_60` covers the fast path of rounded clipping, where every glyph stays inside the safe interior and the clipper is never entered.

## Memory report

`GUI_Memory_Stats(g)` returns a snapshot of what a GUI holds: the fixed size of `Widget`, `Style`, `Style_Cache` and `Draw_Vertex`, the live and free widget slots, the arena, the UI atlas pages, the text caches, the draw-list capacities, the font atlases and the bytes the backend reports for the scene, the backdrop and the geometry buffers.

The test suite builds a 10,000-widget scene and prints one line:

```text
memory 10k: widget 1568 B, style 416 B, style cache 472 B, widget bytes 15681568 B, arena 0 B
```

The widgets now come from the general allocator instead of the GUI arena, so closing a large scene gives their memory back. The sparse accessibility metadata, signals and text-box geometry only cost a pointer until a widget uses them, and resolved styles are interned in a small pool, which is why `Style_Cache` is one source style and two ids. The `src/Tests/memory_test.odin` test fails if `Style_Cache` grows past one style plus its ids or if `Widget` grows past two kilobytes, which are the per-widget invariants the larger scenes rely on.

The atlas is made of 1024x1024 pages by default, so a light application pays 4 MiB for the first page instead of 16 MiB. A region that does not fit opens another page, and each page is its own texture (`atlas_texture_of_page`), so retained draw lists keep their UVs.

`GUI_Trim_Memory(g, aggressive)` gives back the draw-list capacities after a large scene is closed; the aggressive mode also drops the style pool and the measure cache.

## Reproducing

The benchmarks run with the test suite:

```sh
odin test src/Tests -o:speed -define:ODIN_TEST_THREADS=1
```

Each benchmark prints one line:

```text
bench draw.buttons_200: 200 x 2340900 ns (mean 3711344, least 1842400), 3184 vertices, 305664 logical bytes, 191040 packed bytes, 1 commands
```

Only compare results from the same benchmark, machine and build configuration. Background load, display scaling and the optimizer settings all change the numbers.
