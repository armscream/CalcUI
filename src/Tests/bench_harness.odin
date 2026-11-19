//* The harness of the benchmarks. Every benchmark of the catalogue in
//* bench_test.odin has the same shape and is measured in the same way,
//* so that the numbers of one run can be compared with the numbers of
//* another run.

package Tests

import GUI "../GUI"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:time"

//* One benchmark: what it is called, what it measures, how many times it
//* runs and how long it may take.
Bench_Case :: struct {
	id:         string,
	title:      string,
	group:      string,
	notes:      string,
	series:     string,
	iterations: int,
	budget_ns:  f64,
	//* The size of the scene, when the scene has one.
	count: int,
	//* The id of the benchmark of the same group this one is compared
	//* with, and the factor its vertices have to beat.
	compare_id: string,
	compare_at: f64,
	make:       proc(t: ^testing.T, count: int) -> (g: ^GUI.GUI, ctx: rawptr),
	work:       proc(t: ^testing.T, g: ^GUI.GUI, ctx: rawptr, index: int),
	verify:     proc(g: ^GUI.GUI, ctx: rawptr) -> string,
	cleanup:    proc(g: ^GUI.GUI, ctx: rawptr),
}

//* What one run of a benchmark measured.
Bench_Result :: struct {
	id:          string,
	title:       string,
	group:       string,
	notes:       string,
	series:      string,
	iterations:  int,
	ns_median:   f64,
	ns_mean:     f64,
	ns_min:      f64,
	ns_max:      f64,
	vertices:    int,
	commands:    int,
	logical_bytes: int,
	packed_bytes:  int,
	budget_ns:   f64,
	over_budget: bool,
	compare_id:  string,
	compare_at:  f64,
	note:        string,
}

//* The build the numbers of the run come from. The environment variable
//* CALCUI_BENCH_BUILD names it.
bench_build_name :: proc(buf: []u8) -> string {
	name := os.get_env_buf(buf, "CALCUI_BENCH_BUILD")
	if name == "" {return "the default build of the compiler"}
	return name
}

//* How many results one run keeps. The catalogue must not grow past it.
BENCH_MAX_RESULTS :: 64

//* The results of the run, in the order they were measured.
bench_results: [BENCH_MAX_RESULTS]Bench_Result
bench_result_count: int
//* Keeps the results safe when the tests run side by side.
bench_lock: sync.Mutex
//* Keeps the benchmarks from measuring each other.
bench_run_lock: sync.Mutex
//* The runs before the measured ones, so that the caches are warm.
bench_warmup: int = 3

//* The factor that every budget is multiplied with. The environment
//* variable CALCUI_BENCH_BUDGET scales the budgets, so that a slow
//* machine can be given more room. Zero turns the budgets off.
bench_budget_multiple :: proc() -> f64 {
	buf: [64]byte
	raw := os.get_env_buf(buf[:], "CALCUI_BENCH_BUDGET")
	if raw == "" {return 1}
	value, ok := strconv.parse_f64(raw)
	if !ok {return 1}
	return max(0, value)
}

//* The path of the file the results are written to. The environment
//* variable CALCUI_BENCH_OUTPUT names it. An empty path means that the
//* results are only printed.
bench_report_path :: proc(buf: []u8) -> string {
	return os.get_env_buf(buf, "CALCUI_BENCH_OUTPUT")
}

//* The path of the file the results are compared with. The environment
//* variable CALCUI_BENCH_BASELINE names it.
bench_baseline_path :: proc(buf: []u8) -> string {
	return os.get_env_buf(buf, "CALCUI_BENCH_BASELINE")
}

//* == Measuring ==

//* Runs the work of a benchmark and returns the times of the runs.
bench_measure :: proc(
	t: ^testing.T,
	g: ^GUI.GUI,
	ctx: rawptr,
	iterations: int,
	work: proc(t: ^testing.T, g: ^GUI.GUI, ctx: rawptr, index: int),
) -> []f64 {
	samples := make([dynamic]f64, 0, iterations)
	for i in 0 ..< iterations {
		start := time.tick_now()
		work(t, g, ctx, i)
		end := time.tick_now()
		append(&samples, f64(int(time.tick_diff(start, end))))
	}
	return samples[:]
}

//* The middle, the mean and the ends of the times of a benchmark. The
//* middle is the value the budget is held to, because a single slow run
//* of the machine should not fail a test.
bench_stats :: proc(samples: []f64) -> (median, mean, lowest, highest: f64) {
	if len(samples) == 0 {return}
	total := 0.0
	lowest = samples[0]
	highest = samples[0]
	for s in samples {
		total += s
		lowest = min(lowest, s)
		highest = max(highest, s)
	}
	mean = total / f64(len(samples))

	sorted := make([dynamic]f64, 0, len(samples))
	defer delete(sorted)
	for s in samples {append(&sorted, s)}
	slice.sort(sorted[:])
	middle := len(sorted) / 2
	if len(sorted) % 2 == 1 {
		median = sorted[middle]
	} else {
		median = (sorted[middle - 1] + sorted[middle]) / 2
	}
	return
}

//* == Running ==

//* Makes the scene of a benchmark, measures it and gives the scene back.
bench_run_case :: proc(t: ^testing.T, c: Bench_Case) -> Bench_Result {
	result := Bench_Result{
		id         = c.id,
		title      = c.title,
		group      = c.group,
		notes      = c.notes,
		series     = c.series,
		iterations = c.iterations,
		budget_ns  = c.budget_ns,
	}

	g, ctx := c.make(t, c.count)
	for i in 0 ..< bench_warmup {
		c.work(t, g, ctx, i)
	}
	samples := bench_measure(t, g, ctx, c.iterations, c.work)
	defer delete(samples)
	result.ns_median, result.ns_mean, result.ns_min, result.ns_max = bench_stats(samples)

	multiple := bench_budget_multiple()
	if multiple > 0 {
		result.over_budget = result.ns_median > c.budget_ns * multiple
	}

	if g != nil {
		result.vertices = len(g.draw.vertices)
		result.commands = len(g.draw.commands)
		result.logical_bytes = result.vertices * size_of(GUI.Draw_Vertex)
		result.packed_bytes = result.vertices * size_of(GUI.Packed_Vertex)
	}
	if c.verify != nil {
		result.note = c.verify(g, ctx)
	}
	if c.cleanup != nil {
		c.cleanup(g, ctx)
	}
	if g != nil {
		test_gui_destroy(g)
	}
	return result
}

//* Holds a result to its budget. The budget is the time of one run of
//* the work of the benchmark.
bench_check_budget :: proc(t: ^testing.T, r: Bench_Result) {
	if !r.over_budget {return}
	testing.expect(
		t,
		false,
		fmt.tprintf(
			"the benchmark %s took %.0f ns for one run, the budget is %.0f ns",
			r.id,
			r.ns_median,
			r.budget_ns * bench_budget_multiple(),
		),
	)
}

//* Holds the benchmarks of a series to each other. The slowest of a
//* series must not be more than four times the fastest, so that a
//* scene that grows does not cost more than it should.
bench_check_series :: proc(t: ^testing.T, results: []Bench_Result) {
	names := make([dynamic]string, 0)
	defer delete(names)
	for r in results {
		if r.series == "" {continue}
		found := false
		for name in names {
			if name == r.series {
				found = true
				break
			}
		}
		if !found {append(&names, r.series)}
	}

	for name in names {
		fastest := f64(0)
		slowest := f64(0)
		for r in results {
			if r.series != name {continue}
			if fastest == 0 || r.ns_median < fastest {fastest = r.ns_median}
			slowest = max(slowest, r.ns_median)
		}
		if fastest > 0 && slowest > fastest * 4 {
			testing.expect(
				t,
				false,
				fmt.tprintf(
					"the series %s grew by more than four times: the fastest run took %.0f ns and the slowest %.0f ns",
					name,
					fastest,
					slowest,
				),
			)
		}
	}
}

//* Holds the benchmarks that are compared with each other to their rule.
//* A benchmark that names another one has to need more vertices than the
//* other one, by the factor it names.
bench_check_compare :: proc(t: ^testing.T, results: []Bench_Result) {
	for r in results {
		if r.compare_id == "" {continue}
		other_vertices := 0
		found := false
		for o in results {
			if o.id != r.compare_id {continue}
			other_vertices = o.vertices
			found = true
			break
		}
		if !found {
			testing.expect(
				t,
				false,
				fmt.tprintf("the benchmark %s is compared with %s, which was not measured", r.id, r.compare_id),
			)
			continue
		}
		if f64(r.vertices) <= r.compare_at * f64(other_vertices) {
			testing.expect(
				t,
				false,
				fmt.tprintf(
					"the benchmark %s needed %d vertices, the benchmark %s needed %d and it should have needed more than %d times as many",
					r.id,
					r.vertices,
					r.compare_id,
					other_vertices,
					int(r.compare_at),
				),
			)
		}
	}
}

//* Runs the benchmarks of a group, prints them, holds them to their
//* budgets and keeps the results for the report.
bench_run_group :: proc(t: ^testing.T, group: string, cases: []Bench_Case) {
	sync.mutex_lock(&bench_run_lock)
	defer sync.mutex_unlock(&bench_run_lock)

	results := make([dynamic]Bench_Result, 0, len(cases))
	defer delete(results)

	for c in cases {
		if c.group != group {continue}
		r := bench_run_case(t, c)
		r.compare_id = c.compare_id
		r.compare_at = c.compare_at
		bench_print(r)
		bench_check_budget(t, r)
		if r.note != "" {
			testing.expect(
				t,
				false,
				fmt.tprintf("the benchmark %s did not keep its rule: %s", r.id, r.note),
			)
		}
		append(&results, r)
	}

	bench_check_series(t, results[:])
	bench_check_compare(t, results[:])

	sync.mutex_lock(&bench_lock)
	for r in results {
		if bench_result_count >= len(bench_results) {break}
		bench_results[bench_result_count] = r
		bench_result_count += 1
	}
	sync.mutex_unlock(&bench_lock)

	bench_write_report()
}

//* Prints the result of a benchmark.
bench_print :: proc(r: Bench_Result) {
	if r.vertices > 0 {
		fmt.printf(
			"bench %s: %d x %.0f ns (mean %.0f, least %.0f), %d vertices, %d logical bytes, %d packed bytes, %d commands\n",
			r.id,
			r.iterations,
			r.ns_median,
			r.ns_mean,
			r.ns_min,
			r.vertices,
			r.logical_bytes,
			r.packed_bytes,
			r.commands,
		)
	} else {
		fmt.printf(
			"bench %s: %d x %.0f ns (mean %.0f, least %.0f)\n",
			r.id,
			r.iterations,
			r.ns_median,
			r.ns_mean,
			r.ns_min,
		)
	}
}

//* == The report ==

//* Writes the results of the run to the file of CALCUI_BENCH_OUTPUT.
bench_write_report :: proc() -> bool {
	path_buf: [1024]byte
	path := bench_report_path(path_buf[:])
	if path == "" {return false}

	results_buf: [BENCH_MAX_RESULTS]Bench_Result
	count := bench_results_copy(results_buf[:])
	results := results_buf[:count]

	builder: strings.Builder
	if _, err := strings.builder_init_len_cap(&builder, 0, 8192, context.allocator); err != nil {
		return false
	}
	defer strings.builder_destroy(&builder)

	bench_report_head(&builder)
	bench_report_benchmarks(&builder)
	bench_report_results(&builder, results)
	bench_report_baseline(&builder, results)

	text := strings.to_string(builder)
	defer delete(text)
	if err := os.write_entire_file_from_string(path, text); err != nil {
		fmt.eprintf("the benchmark report was not written to %s: %v\n", path, err)
		return false
	}
	return true
}

//* The results of the run so far, in the order of their ids. The results
//* are copied into the array and the number of them is returned.
bench_results_copy :: proc(into: []Bench_Result) -> int {
	sync.mutex_lock(&bench_lock)
	defer sync.mutex_unlock(&bench_lock)
	count := min(bench_result_count, len(into))
	copy(into[:count], bench_results[:count])
	slice.sort_by(into[:count], proc(a, b: Bench_Result) -> bool {return a.id < b.id})
	return count
}

//* Writes the name of the machine and the state of the repository.
bench_report_head :: proc(builder: ^strings.Builder) {
	build_buf: [128]byte
	processor_buf: [512]byte
	stamp, ok := time.time_to_rfc3339(time.now())
	if !ok {stamp = "unknown"}
	strings.write_string(builder, "# CalcUI internal benchmarks\n\n")
	strings.write_string(
		builder,
		"The results of a run of the test suite. The file is written by the run itself and is not part of the repository.\n\n",
	)
	strings.write_string(builder, "| Field | Value |\n|---|---|\n")
	fmt.sbprintf(builder, "| Run | %s |\n", stamp)
	fmt.sbprintf(builder, "| System | %s |\n", ODIN_OS)
	fmt.sbprintf(builder, "| Processor | %s |\n", bench_processor_name(processor_buf[:]))
	fmt.sbprintf(builder, "| Compiler | %s |\n", ODIN_VERSION)
	fmt.sbprintf(builder, "| Build | %s |\n", bench_build_name(build_buf[:]))
	fmt.sbprintf(builder, "| Commit | %s |\n", bench_commit_name())
	fmt.sbprintf(builder, "| Budget | %.2fx |\n", bench_budget_multiple())
	strings.write_string(builder, "\n")
}

//* Writes what every benchmark of the catalogue measures.
bench_report_benchmarks :: proc(builder: ^strings.Builder) {
	strings.write_string(builder, "## The benchmarks\n\n")
	strings.write_string(builder, "| id | group | scene | what it measures |\n|---|---|---|---|\n")
	cases := bench_cases()
	defer delete(cases)
	for c in cases {
		fmt.sbprintf(builder, "| `%s` | %s | %s | %s |\n", c.id, c.group, c.title, c.notes)
	}
	strings.write_string(builder, "\n")
}

//* Writes the numbers of the run.
bench_report_results :: proc(builder: ^strings.Builder, results: []Bench_Result) {
	strings.write_string(builder, "## The results\n\n")
	strings.write_string(
		builder,
		"| id | group | runs | middle ns | mean ns | least ns | most ns | vertices | logical bytes | packed bytes | commands | budget ns | verdict |\n",
	)
	strings.write_string(
		builder,
		"|---|---|---|---|---|---|---|---|---|---|---|---|---|\n",
	)

	for r in results {
		verdict := "ok"
		if r.over_budget {verdict = "over the budget"}
		if r.note != "" {verdict = r.note}
		fmt.sbprintf(
			builder,
			"| `%s` | %s | %d | %.0f | %.0f | %.0f | %.0f | %d | %d | %d | %d | %.0f | %s |\n",
			r.id,
			r.group,
			r.iterations,
			r.ns_median,
			r.ns_mean,
			r.ns_min,
			r.ns_max,
			r.vertices,
			r.logical_bytes,
			r.packed_bytes,
			r.commands,
			r.budget_ns,
			verdict,
		)
	}
	strings.write_string(builder, "\n")
}

//* Writes how the results of the run differ from the results of the
//* file of CALCUI_BENCH_BASELINE.
bench_report_baseline :: proc(builder: ^strings.Builder, results: []Bench_Result) {
	path_buf: [1024]byte
	path := bench_baseline_path(path_buf[:])
	if path == "" {return}
	if !os.exists(path) {
		fmt.sbprintf(builder, "## The baseline\n\nThe baseline %s was not found.\n\n", path)
		return
	}

	baseline := bench_baseline_read(path)
	if len(baseline) == 0 {
		fmt.sbprintf(builder, "## The baseline\n\nThe baseline %s has no results to compare with.\n\n", path)
		return
	}

	strings.write_string(builder, "## The baseline\n\n")
	fmt.sbprintf(builder, "The run against the results of %s.\n\n", path)
	strings.write_string(builder, "| id | middle ns | baseline ns | change |\n|---|---|---|---|\n")

	for r in results {
		old, found := baseline[r.id]
		if !found {continue}
		change := 0.0
		if old > 0 {change = (r.ns_median - old) / old * 100}
		fmt.sbprintf(
			builder,
			"| `%s` | %.0f | %.0f | %+.1f%% |\n",
			r.id,
			r.ns_median,
			old,
			change,
		)
	}
	strings.write_string(builder, "\n")
}

//* Reads the middle time of every benchmark of a report.
bench_baseline_read :: proc(path: string) -> map[string]f64 {
	times := make(map[string]f64)
	data, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil {return times}
	defer delete(data)

	lines := strings.split_lines(string(data))
	cells: [16]string
	median_column := -1
	for line in lines {
		count := bench_row_cells(line, &cells)
		if count == 0 {continue}
		if median_column < 0 {
			for i in 1 ..< count {
				if cells[i] == "middle ns" || cells[i] == "median ns" {
					median_column = i
					break
				}
			}
			continue
		}
		if median_column >= count {continue}
		id := strings.trim(cells[1], "` ")
		value, ok := strconv.parse_f64(strings.trim_space(cells[median_column]))
		if !ok || id == "" {continue}
		times[id] = value
	}
	return times
}

//* Splits a line of a table into its cells. The cells are put into the
//* array and the number of them is returned. The first cell is the one
//* before the first bar, and it is empty.
bench_row_cells :: proc(line: string, cells: ^[16]string) -> int {
	trimmed := strings.trim_space(line)
	if !strings.has_prefix(trimmed, "|") {return 0}
	count := 0
	start := 0
	for i in 0 ..= len(trimmed) {
		if i < len(trimmed) && trimmed[i] != '|' {continue}
		if count < len(cells) {
			cells[count] = strings.trim_space(trimmed[start:i])
		}
		count += 1
		start = i + 1
	}
	return count
}

//* == The machine ==

//* The name of the processor of the machine. The name is put into the
//* buffer, so that it outlives the call.
bench_processor_name :: proc(buf: []u8) -> string {
	name := os.get_env_buf(buf, "PROCESSOR_IDENTIFIER")
	if name != "" {return name}
	data, err := os.read_entire_file_from_path("/proc/cpuinfo", context.allocator)
	if err != nil {return "unknown"}
	defer delete(data)
	for line in strings.split_lines(string(data)) {
		if !strings.has_prefix(line, "model name") {continue}
		parts := strings.split(line, ":")
		if len(parts) < 2 {continue}
		model := strings.trim_space(parts[1])
		if len(model) > len(buf) {return "unknown"}
		for i in 0 ..< len(model) {
			buf[i] = model[i]
		}
		return string(buf[:len(model)])
	}
	return "unknown"
}

//* The commit of the repository, if there is one.
bench_commit_name :: proc() -> string {
	root := ".git"
	if data, err := os.read_entire_file_from_path(root, context.allocator); err == nil {
		text := string(data)
		delete(data)
		if strings.has_prefix(text, "gitdir: ") {
			root = strings.trim_space(text[len("gitdir: "):])
		}
	}

	head, err := os.read_entire_file_from_path(bench_path(root, "HEAD"), context.allocator)
	if err != nil {return "unknown"}
	defer delete(head)
	text := string(head)

	if !strings.has_prefix(text, "ref: ") {return strings.trim_space(text)}
	ref := strings.trim_space(text[len("ref: "):])

	if data, err := os.read_entire_file_from_path(bench_path(root, ref), context.allocator); err == nil {
		defer delete(data)
		return strings.trim_space(string(data))
	}

	packed, packed_err := os.read_entire_file_from_path(bench_path(root, "packed-refs"), context.allocator)
	if packed_err != nil {return "unknown"}
	defer delete(packed)
	for line in strings.split_lines(string(packed)) {
		parts := strings.split(line, " ")
		if len(parts) < 2 {continue}
		if strings.trim_space(parts[1]) != ref {continue}
		return strings.trim_space(parts[0])
	}
	return "unknown"
}

//* The path of a file of the repository.
bench_path :: proc(root: string, name: string) -> string {
	return strings.concatenate({root, "/", name})
}
