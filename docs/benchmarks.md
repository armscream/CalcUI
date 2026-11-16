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
| `draw.rounded_panels_200` | draw | Draw-list generation for 200 rounded panels using shader-based corners. |
| `draw.rounded_panels_200_cpu` | draw | The same scene using CPU-based rounded corners. |
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

## Running the suite

Run the benchmarks alongside the normal test suite:

```sh
odin test src/Tests -define:ODIN_TEST_THREADS=1
```

Each benchmark prints a result line:

```text
bench draw.buttons_200: 200 x 8216600 ns (mean 8210026, least 6822900), 3184 vertices, 1 commands
```

The output includes the benchmark ID, run count, median, mean, fastest run, and final draw-list vertex and command counts.

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

- **OS:** Windows 11 Pro (10.0.26200)
- **CPU:** Intel Pentium Silver N5030 (4 cores)
- **Compiler:** Odin `dev-2026-10`
- **Build:** `-o:speed`

The N5030 is a low-power processor, so faster desktop CPUs should produce lower timings.

All times are in milliseconds. Median represents typical performance, while minimum shows the fastest recorded run.

| ID | Runs | Median (ms) | Min (ms) | Vertices | Commands |
|---|---:|---:|---:|---:|---:|
| `draw.buttons_200` | 200 | 2.17 | 1.91 | 3184 | 1 |
| `draw.panels_400` | 200 | 1.85 | 1.50 | 8000 | 1 |
| `draw.labels_60` | 50 | 2.59 | 2.10 | 8400 | 1 |
| `draw.rounded_panels_200` | 100 | 0.539 | 0.488 | 800 | 1 |
| `draw.rounded_panels_200_cpu` | 100 | 1.14 | 1.01 | 5000 | 1 |
| `layout.panels_400` | 200 | 0.339 | 0.287 | 8000 | 1 |
| `layout.panels_400_one` | 200 | 0.142 | 0.132 | 8000 | 1 |
| `style.panels_400` | 200 | 0.175 | 0.158 | 8000 | 1 |
| `style.panels_400_colour` | 200 | 0.921 | 0.661 | 8000 | 1 |
| `frame.buttons_200` | 100 | 2.33 | 1.73 | 3184 | 1 |
| `frame.buttons_200_idle` | 100 | 0.0347 | 0.0343 | 3184 | 1 |
| `lifecycle.gui_100_widgets` | 20 | 12.60 | 9.69 | 0 | 0 |
| `lifecycle.atlas` | 20 | 13.39 | 12.65 | 0 | 0 |
| `lifecycle.atlas_16` | 2000 | 0.0005 | 0.0004 | 0 | 0 |
| `lifecycle.atlas_64` | 2000 | 0.0005 | 0.0004 | 0 | 0 |
| `widgets.virtual_list_1000` | 50 | 0.194 | 0.185 | 480 | 1 |
| `widgets.virtual_list_10000` | 50 | 0.209 | 0.193 | 480 | 1 |
| `widgets.virtual_list_100000` | 50 | 0.198 | 0.189 | 480 | 1 |
| `widgets.virtual_list_1000000` | 50 | 0.228 | 0.194 | 480 | 1 |
| `widgets.data_table_1000` | 50 | 0.184 | 0.172 | 500 | 1 |
| `widgets.data_table_10000` | 50 | 0.221 | 0.176 | 500 | 1 |
| `widgets.data_table_100000` | 50 | 0.192 | 0.169 | 500 | 1 |
| `widgets.data_table_1000000` | 50 | 0.177 | 0.159 | 500 | 1 |
| `widgets.virtual_list_mixed_100000` | 50 | 0.160 | 0.138 | 384 | 1 |
| `node_graph.draw_500` | 20 | 35.56 | 33.49 | 136215 | 1 |
| `node_graph.drag_500` | 200 | 0.0091 | 0.0082 | 0 | 0 |

### Scaling checks

The virtual list and data table benchmarks each test four row counts, from 1,000 to 1,000,000.

The slowest result in each series must remain within 4× the fastest. This checks that performance scales with visible rows rather than total row count.

The rounded panel benchmarks also verify the CPU fallback: it must generate more than 4× the vertices of the shader-based implementation.

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