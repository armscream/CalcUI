# CalcUI Benchmarks

CalcUI includes a benchmark suite in its test suite. It measures layout, styling, text, drawing, widgets, and frame performance to catch regressions as the framework evolves.

This page documents the benchmarks, how to run them, reference results, and how CalcUI compares with Dear ImGui and Qt.

## What the suite measures

Each benchmark has a stable ID, group, scene, and performance budget. Scenes are built once, warmed up, and then timed across multiple runs. The median is used for budget checks.

| ID | Group | What it measures |
|---|---|---|
| `draw.buttons_200` | draw | Draw-list generation for 200 buttons. |
| `draw.panels_400` | draw | Draw-list generation for 400 panels with backgrounds and borders. |
| `draw.labels_60` | draw | Draw-list generation for 60 long-text labels, including shaping and placement. |
| `draw.clip_labels_60` | draw | The same labels inside a rounded clip they never cross, so the shape clipper stays on the fast path. |
| `draw.pack_vertices_5000` | draw | Packing the vertices of a draw list into the compact GPU form, without uploading them. |
| `draw.shadow_panels_200` | draw | 200 rounded panels, each with one outer SDF shadow with spread. |
| `draw.side_borders_200` | draw | 200 rounded panels whose four borders have four colours, which needs strip geometry. |
| `draw.rounded_panels_200` | draw | Draw-list generation for 200 rounded panels using shader-based corners. |
| `draw.rounded_panels_200_cpu` | draw | The same scene using CPU-based rounded corners. |
| `draw.glass_panels_200` | draw | 200 glass panels with the optical stack, each a standalone command. |
| `draw.glass_nested_100` | draw | 100 glass panels, each with a smaller glass panel inside, so the backdrop plan splits the captures per nesting level. |
| `draw.theming_wallpaper_24` | draw | A wallpaper canvas of 100 items under 24 glass surfaces, shaped like the theming example. |
| `layout.panels_400` | layout | Full layout of 400 panels with every widget marked dirty. |
| `layout.panels_400_one` | layout | Incremental layout after one widget changes. |
| `style.panels_400` | style | Style resolution for 400 panels. |
| `style.panels_400_colour` | style | Style resolution, including backgrounds and text colours. |
| `frame.buttons_200` | frame | Full frame update, layout, and draw-list generation for 200 buttons. |
| `frame.buttons_200_idle` | frame | Idle frame processing with no changes. |
| `lifecycle.gui_100_widgets` | lifecycle | GUI creation, addition of 100 widgets, layout, and destruction with a 2048×2048 atlas. |
| `lifecycle.atlas` | lifecycle | Creation and destruction of a 2048×2048 glyph atlas (16 MB). |
| `lifecycle.atlas_16` | lifecycle | Allocation and release of a 16×16 region in a 512×512 atlas. |
| `lifecycle.atlas_64` | lifecycle | Allocation and release of a 64×64 region in a 512×512 atlas. |
| `widgets.virtual_list_1000` | widgets | Draw-list generation for a 1,000-row virtual list. Only visible rows are requested. |
| `widgets.virtual_list_10000` | widgets | Same test with 10,000 rows. |
| `widgets.virtual_list_100000` | widgets | Same test with 100,000 rows. |
| `widgets.virtual_list_1000000` | widgets | Same test with 1,000,000 rows. |
| `widgets.data_table_1000` | widgets | Draw-list generation for a 1,000-row data table. Only visible rows are requested. |
| `widgets.data_table_10000` | widgets | Same test with 10,000 rows. |
| `widgets.data_table_100000` | widgets | Same test with 100,000 rows. |
| `widgets.data_table_1000000` | widgets | Same test with 1,000,000 rows. |
| `widgets.virtual_list_mixed_100000` | widgets | Draw-list generation for a 100,000-row virtual list with variable row heights. |
| `node_graph.draw_500` | node_graph | Draw-list generation for a graph with 500 nodes and 1,000 wires. |
| `node_graph.drag_500` | node_graph | Pointer movement over a graph with 500 nodes and 1,000 wires. |
| `node_graph.draw_2000` | node_graph | Draw-list generation for a graph with 2,000 nodes and 4,000 wires. |
| `node_graph.hover_empty_2000` | node_graph | A pointer over the empty canvas of a graph with 2,000 nodes and 4,000 wires, which exercises the wire hit test and the spatial index. |

## Running the suite

Run the benchmarks alongside the normal test suite:

```sh
odin test src/Tests -define:ODIN_TEST_THREADS=1
```

Each benchmark prints a result line:

```text
bench draw.buttons_200: 200 x 8216600 ns (mean 8210026, least 6822900), 3184 vertices, 305664 logical bytes, 191040 packed bytes, 1 commands
```

The output includes the benchmark ID, run count, median, mean, fastest run, the final draw-list vertex and command counts, and the vertex bytes in the logical `Draw_Vertex` form and the compact `Packed_Vertex` form.

### Environment variables

| Variable | Description |
|---|---|
| `CALCUI_BENCH_BUDGET` | Budget multiplier. `1` uses the default budgets, `0` disables budget checks, and larger values allow slower machines more headroom. |
| `CALCUI_BENCH_OUTPUT` | Output path for a Markdown benchmark report. |
| `CALCUI_BENCH_BASELINE` | Path to an earlier report. Adds a comparison table showing changes against that baseline. |

### Build configuration

Benchmark results depend on optimization settings. `odin test` defaults to `-o:minimal`, while `-o:speed` builds are typically 2–5 times faster.

The reference results below use `-o:speed`, matching the intended application build.

To reproduce them:

```sh
odin test src/Tests -o:speed -define:ODIN_TEST_THREADS=1
```

Budgets are calibrated against the default build, so both default and optimized builds should pass.

## Reference results

The reference run used:

- **OS:** Windows 11 Pro
- **CPU:** Intel64 Family 6 Model 122 Stepping 8, GenuineIntel
- **Compiler:** Odin `dev-2026-10`
- **Build:** `-o:speed`

The reference machine is a laptop, so faster desktop CPUs should produce lower timings.

All times are in milliseconds. Median represents typical performance, while minimum shows the fastest recorded run. Logical bytes are the `Draw_Vertex` size of the list and packed bytes are the `Packed_Vertex` size the GPU uploads.

| ID | Runs | Median (ms) | Min (ms) | Vertices | Logical bytes | Packed bytes | Commands |
|---|---:|---:|---:|---:|---:|---:|---:|
| `draw.buttons_200` | 200 | 3.30 | 2.80 | 3184 | 305664 | 191040 | 1 |
| `draw.panels_400` | 200 | 2.56 | 2.27 | 8000 | 768000 | 480000 | 1 |
| `draw.labels_60` | 50 | 3.20 | 2.92 | 8400 | 806400 | 504000 | 1 |
| `draw.clip_labels_60` | 50 | 4.86 | 4.36 | 8406 | 806976 | 504360 | 1 |
| `draw.pack_vertices_5000` | 100 | 0.737 | 0.654 | 5000 | 480000 | 300000 | 1 |
| `draw.shadow_panels_200` | 100 | 0.937 | 0.752 | 1600 | 153600 | 96000 | 1 |
| `draw.side_borders_200` | 50 | 4.11 | 3.74 | 27362 | 2626752 | 1641720 | 1 |
| `draw.rounded_panels_200` | 100 | 0.784 | 0.617 | 800 | 76800 | 48000 | 1 |
| `draw.rounded_panels_200_cpu` | 100 | 1.65 | 1.44 | 5000 | 480000 | 300000 | 1 |
| `layout.panels_400` | 200 | 0.418 | 0.329 | 8000 | 768000 | 480000 | 1 |
| `layout.panels_400_one` | 200 | 0.159 | 0.144 | 8000 | 768000 | 480000 | 1 |
| `style.panels_400` | 200 | 0.199 | 0.178 | 8000 | 768000 | 480000 | 1 |
| `style.panels_400_colour` | 200 | 1.10 | 0.745 | 8000 | 768000 | 480000 | 1 |
| `frame.buttons_200` | 100 | 3.49 | 2.76 | 3184 | 305664 | 191040 | 1 |
| `frame.buttons_200_idle` | 100 | 0.0394 | 0.0386 | 3184 | 305664 | 191040 | 1 |
| `lifecycle.gui_100_widgets` | 20 | 18.38 | 15.68 | 0 | 0 | 0 | 0 |
| `lifecycle.atlas` | 20 | 15.38 | 13.73 | 0 | 0 | 0 | 0 |
| `lifecycle.atlas_16` | 2000 | 0.0005 | 0.0004 | 0 | 0 | 0 | 0 |
| `lifecycle.atlas_64` | 2000 | 0.0005 | 0.0004 | 0 | 0 | 0 | 0 |
| `widgets.virtual_list_1000` | 50 | 0.245 | 0.240 | 480 | 46080 | 28800 | 1 |
| `widgets.virtual_list_10000` | 50 | 0.246 | 0.217 | 480 | 46080 | 28800 | 1 |
| `widgets.virtual_list_100000` | 50 | 0.275 | 0.222 | 480 | 46080 | 28800 | 1 |
| `widgets.virtual_list_1000000` | 50 | 0.271 | 0.225 | 480 | 46080 | 28800 | 1 |
| `widgets.data_table_1000` | 50 | 0.238 | 0.205 | 500 | 48000 | 30000 | 1 |
| `widgets.data_table_10000` | 50 | 0.255 | 0.212 | 500 | 48000 | 30000 | 1 |
| `widgets.data_table_100000` | 50 | 0.223 | 0.208 | 500 | 48000 | 30000 | 1 |
| `widgets.data_table_1000000` | 50 | 0.273 | 0.215 | 500 | 48000 | 30000 | 1 |
| `widgets.virtual_list_mixed_100000` | 50 | 0.225 | 0.178 | 384 | 36864 | 23040 | 1 |
| `node_graph.draw_500` | 20 | 28.88 | 24.89 | 29855 | 2866080 | 1791300 | 1 |
| `node_graph.drag_500` | 200 | 0.0123 | 0.0115 | 0 | 0 | 0 | 0 |
| `node_graph.draw_2000` | 10 | 61.28 | 56.93 | 64800 | 6220800 | 3888000 | 1 |
| `node_graph.hover_empty_2000` | 50 | 0.0179 | 0.0171 | 0 | 0 | 0 | 0 |

### Scaling checks

The virtual list and data table benchmarks each test four row counts, from 1,000 to 1,000,000.

The slowest result in each series must remain within 4× the fastest. This checks that performance scales with visible rows rather than total row count.

The rounded panel benchmarks also verify the CPU fallback: it must generate more than 4× the vertices of the shader-based implementation.

`draw.clip_labels_60` measures the fast path of rounded clipping: every glyph stays inside the safe interior, so the clipper must not be entered. `draw.pack_vertices_5000` measures only the packing step the GPU does when a list changes. Packing turns 96 logical bytes per vertex into 60, which is 62.5% of the logical size.

## Interpreting results

Budgets are checked against the median rather than individual runs. This prevents occasional slow runs on shared machines from causing unnecessary test failures.

The minimum shows the machine's best recorded performance. The difference between the minimum and median indicates how much variation occurred during testing.

### Performance budgets

Budgets are regression thresholds, not performance targets. They are set at approximately 3× the median of the default build.

This allows slower machines some headroom while catching significant regressions. For example, a change that doubles benchmark time should fail the corresponding check.

Set `CALCUI_BENCH_BUDGET=0` to disable budget checks while still generating benchmark reports. CI uses this configuration to collect results without enforcing machine-dependent timing thresholds.

### Comparing results

Only compare results from the same benchmark, machine, and build configuration.

Use `CALCUI_BENCH_BASELINE` with a previous report from the same machine to identify performance changes between revisions.