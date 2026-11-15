# CalcUI — AI Implementation Prompt Plan

**Document:** `promptplan.md`  
**Project:** CalcUI  
**Language:** Odin  
**Primary reference:** `ref.md`  
**Purpose:** Sequential AI-assisted implementation roadmap

---

# 1. Instructions for the Coding Agent

You are working on CalcUI, an existing retained-mode GUI framework written in Odin.

Your task is to improve the existing implementation, not replace it with a new GUI architecture.

The repository contains an established widget system, layout system, rendering pipeline, text integration, input system, styling, and extensive widget collection.

You must inspect the actual repository before making changes.

`ref.md` describes the intended architecture and the reported baseline. It is a reference, not proof that every listed implementation detail remains unchanged.

## 1.1 Mandatory Rules

1. Read `ref.md` before beginning.
2. Inspect the relevant source files before modifying them.
3. Verify whether the requested feature already exists.
4. Reuse existing systems wherever possible.
5. Do not introduce duplicate systems.
6. Do not replace the retained-mode architecture.
7. Do not replace the existing renderer architecture.
8. Do not introduce new external dependencies without justification.
9. Use Odin for all CalcUI implementation work.
10. Preserve existing public APIs unless a deliberate API change is necessary.
11. Maintain renderer independence.
12. Preserve stable widget identities.
13. Use generation-validated `Widget_ID` references for long-lived references.
14. Avoid raw pointers as persistent ownership references.
15. Avoid unnecessary allocations in hot paths.
16. Add tests for all new behavior.
17. Run the existing test suite after each meaningful phase. A test command that compiles a package with no tests is not a test run.
18. Do not silently remove existing functionality.
19. Do not implement unrelated features during a phase.
20. Report all changes and known limitations.
21. Do not add comments in edited code files. Remove inaccurate existing ones.
22. Do not edit dependencies (Runa/SDL3)

## 1.2 Source Inspection Requirements

Before each phase:

- Identify the relevant files.
- Trace the current execution flow.
- Identify existing data structures.
- Identify existing invalidation mechanisms.
- Identify relevant tests.
- Identify public API dependencies.
- Identify backend-specific behavior.
- Identify any existing partial implementation.
- Read the verified baseline corrections in Prompt 0.3.

Do not assume names or file organization from this plan.

Use the actual repository structure.

## 1.3 Implementation Discipline

Work in small, verifiable steps.

For each phase:

1. Inspect.
2. Explain the current implementation.
3. Identify the precise deficiency.
4. Propose the smallest appropriate design.
5. Implement the change.
6. Add tests only where necessary.
7. Run tests.
8. Fix regressions.
9. Benchmark where applicable.
10. Summarize the result.

Do not proceed to the next phase if the current phase leaves the codebase in a broken or unverified state.

## 1.4 Avoid Speculative Refactoring

Do not refactor unrelated code simply because a different design seems cleaner.

Refactor only when required to implement the requested functionality safely.

If a substantial architectural change appears necessary:

- Explain why.
- Identify the affected systems.
- Describe compatibility implications.
- Propose the migration.
- Wait for approval if it would substantially change public APIs or core architecture.

---


# 6. Phase 4 — Animation System


## Prompt 4.1 - Package split

## Objective

Move all private / core code into src/GUI/Core 'package Core'
all public code into src/GUI 'package GUI' - anything exposed to user, backend, Main, App and examples, all widgets, all things needed to make a GUI app.
Move all tweens / animation related code to src/GUI/Animation 'package Animation'
Undo changes to src/GUI/dependencies/Runa as we dont maintain it, ensure that functionality can work 
without changing Runa.
Consolidate code into files that make sense by functionality/feature - do not increase number of files, if anything, reduce the total amount - keep code concise with minimal comments and no code duplication - where possible.
- Delegate tasks to subagents

### Acceptance Criteria
- Full test suite passes (delete irrelevant old tests)
- No regressions in existing functionality
- all examples compile and run

## Prompt 4.3 — Integrate Animation with Styling

### Objective

Allow style transitions through the existing style system.

### Requirements

Support transitions for:

- Hover.
- Pressed.
- Focused.
- Selected.
- Expanded.
- Popup visibility.
- Opacity.
- Other relevant style properties.

Use floating-point interpolation.

Do not create a second style-resolution system.

### Acceptance Criteria

- State changes can animate smoothly.
- Immediate style changes remain possible.
- Transitions can be interrupted.
- Transition targets remain valid.
- Theme changes behave predictably.
- Animation does not break style caching.
- Examples demonstrate the above in 01_gallery, 06_scene, and 05_theming.

---

## Prompt 4.4 - Button shouldnt be default

### Objective

Not all widgets should have general clicked and hovered states.
Most can be inert while having clickable areas inside them, currently if you click or hover over most widgets that are not supposed to be buttons, they will change state.

# 7. Phase 5 — Lazy Redraw and Frame Scheduling

## Prompt 5.1 — Implement Dirty-Driven Frame Scheduling

### Objective

Allow CalcUI to avoid unnecessary frames when its UI is unchanged.

The framework must continue supporting continuous rendering.

### Requirements

Inspect the existing application loop and platform abstraction.

Separate framework frame requirements from backend-specific waiting and presentation.

Use existing dirty-state systems.

Verified current state: the application loop calls `Frame` and submits every draw list unconditionally. There is no `needs_frame` flag. The GPU backend may skip a geometry upload when the vertex data is unchanged, but the core still walks the tree and rebuilds the draw list every frame.

Determine whether another frame is needed because of:

- Input.
- State changes.
- Layout changes.
- Rendering changes.
- Active animations.
- Resource uploads.
- Window exposure.
- Window resizing.
- Explicit application requests.

### Requirements

Support at least:

1. Continuous rendering.
2. Event-driven rendering.

### Acceptance Criteria

- Idle event-driven applications do not continuously rebuild the draw list.
- Active animations continue to receive frames.
- Input always triggers necessary updates.
- Window exposure causes repainting.
- Resize events update layout.
- Resource uploads trigger appropriate frames.
- Continuous mode behaves as before.

---

## Prompt 5.2 — Optimize Unchanged Draw Data

### Objective

Avoid unnecessary draw-list reconstruction when the GUI has not changed.

### Requirements

Investigate whether the existing draw list can be retained safely.

Verified current state: the core rebuilds the draw list every frame. Only the GPU upload is conditionally skipped.

Determine which operations invalidate it.

Potential invalidation sources:

- Widget appearance.
- Widget visibility.
- Widget geometry.
- Text changes.
- Atlas changes.
- Clipping changes.
- Resource generation changes.
- Layer ordering.
- Popup changes.

Preserve resource lifetime and generation validation.

Do not reuse stale draw commands.

### Acceptance Criteria

- Unchanged UI reuses valid rendering data.
- Dirty widgets update appropriately.
- Resource changes invalidate affected commands.
- Backend submission remains correct.
- No stale handles are used.
- No memory leaks found.

---

# 8. Phase 6 — Rendering Completion

## Prompt 6.1 — Implement Style-Box Shadows

### Objective

Complete shadow rendering using the shared SDF rendering architecture.

### Requirements

Verify the existing style fields.

Verified current state: `StyleBox` carries shadow colour, offset, blur, and spread fields; the theme propagates them; no draw path reads them. Text shadows and outlines are separate.

Support:

- Shadow color.
- Offset.
- Softness.
- Spread where practical.
- Rounded geometry.
- Clipping.
- Correct draw order.

Prefer a compact shared SDF implementation.

Avoid per-widget shader or texture creation.

### Acceptance Criteria

- Style-box shadows render.
- Rounded corners match the box geometry.
- Clipping behaves correctly.
- Existing text shadows remain unchanged.
- Both backends have deliberate behavior.

---

## Prompt 6.2 — Improve Shared SDF Shape Support

### Objective

Complete shared SDF shape functionality.

Investigate:

- Per-side borders.
- Border thickness.
- Corner radius.
- Corner-radius clamping.
- Fill.
- Border color.
- Shadow integration.

Keep the representation compact.

Verified current state: the SDF shader implements a rounded-box fill only. It has no per-side border or shadow parameters. `stylebox_radius` collapses the four corner radii to the maximum, and both the GPU shader and the CPU polygon path clamp that single radius to half the smaller dimension.

### Acceptance Criteria

- Small dimensions render correctly.
- Corner radii are clamped safely.
- Border geometry is consistent.
- Backends remain compatible.
- Existing visual behavior does not regress.

---

# 9. Phase 7 — Grid Improvements

## Prompt 7.1 — Add Grid Placement and Spans

### Objective

Extend the existing grid layout rather than replacing it.

### Requirements

Support:

- Automatic placement.
- Explicit row placement.
- Explicit column placement.
- Row spans.
- Column spans.
- Fixed tracks.
- Flexible tracks.
- Content-sized tracks.
- Minimum and maximum track sizes.
- Track spacing.

Do not implement named grid lines.

Verified current state: the grid supports a fixed column count only. It has no automatic or explicit placement, spans, or fixed, flexible, and content-sized tracks. It allocates two temporary arrays per layout.

### Requirements

Integrate with intrinsic measurement and layout constraints.

Ensure spanning children contribute correctly to track measurement.

Avoid excessive temporary allocations.

### Acceptance Criteria

- Automatic placement works.
- Explicit placement works.
- Spans work.
- Flexible tracks distribute correctly.
- Content-sized tracks measure correctly.
- Nested grids work.
- RTL behavior is correct.
- Tests cover placement and sizing.

---

# 10. Phase 8 — Text Editing and Shaping

## Prompt 8.1 — Implement Undo Coalescing

### Objective

Improve the existing undo stack without replacing the text-editing model.

### Requirements

Coalesce logically continuous operations.

Support:

- Typing.
- Backspace.
- Forward delete.
- Selection replacement.
- Paste.
- Programmatic changes.
- Explicit undo groups.

Use appropriate time or operation-boundary rules.

Do not merge unrelated edits.

Verified current state: every insertion, backspace, and delete creates a separate undo record. `undo_commit` clones the before and after text per record.

### Acceptance Criteria

- Continuous typing is undone as a logical group.
- Continuous deletion behaves predictably.
- Selection replacement is one logical operation.
- Paste is one logical operation.
- Cursor movement establishes appropriate boundaries.
- Existing undo/redo behavior remains correct.

---

## Prompt 8.2 — Optimize Text Shaping and Caret Data

### Objective

Reduce repeated shaping and measurement work.

### Requirements

Investigate whether one shaping result can supply:

- Glyph positions.
- Glyph advances.
- Clusters.
- Caret positions.
- Selection geometry.
- Rendering information.

Reuse the result where appropriate.

Verified current state: measurement is cached, but caret and selection queries re-walk the glyphs of a line, and `text_box_clusters` rebuilds and insertion-sorts a cluster array per call.

Do not compromise:

- Bidi handling.
- Complex shaping.
- Font fallback.
- Cluster correctness.
- Subpixel positioning.
- IME behavior.

### Acceptance Criteria

- Repeated shaping is reduced.
- Caret movement remains correct.
- Selection geometry remains correct.
- Text rendering remains correct.
- Existing shaping tests pass.

---

# 11. Phase 9 — Overlay and Style Optimization

## Prompt 9.1 — Optimize Overlay Traversal

### Objective

Reduce unnecessary work in inactive popup and overlay systems.

### Requirements

Investigate whether a frame-stamped overlay traversal gate is useful.

Preserve:

- Popup stack.
- Z-order.
- Focus restoration.
- Nested popups.
- Pointer capture.
- Hit-test priority.
- Dismissal behavior.

Do not replace the existing popup architecture.

Verified current state: popups are not traversed or rebuilt as a separate per-frame overlay pass; they are drawn as part of the normal widget tree. The popup stack is scanned linearly by `popup_index`, `Popup_Close`, and outside-click handling. Measure before implementing a gate.

### Acceptance Criteria

- Inactive overlays do not require unnecessary traversal.
- Active overlays work correctly.
- Nested popups remain correct.
- Hit testing remains correct.
- Focus restoration remains correct.

---

## Prompt 9.2 — Granular Style Invalidation

### Objective

Investigate more precise style invalidation.

### Requirements

Determine whether changes to individual style properties can invalidate only affected widgets and systems.

Potential categories:

- Text.
- Background.
- Border.
- Shadow.
- Layout.
- Interaction state.
- Font.

Retain the global theme epoch or equivalent fallback.

Do not implement this unless profiling shows meaningful benefit.

Verified current state: theme changes increment a global epoch and invalidate every theme-using widget with `.Measure` and `.Visual`. There is no per-property changed set.

### Acceptance Criteria

- Style changes invalidate appropriate properties.
- Layout is not unnecessarily invalidated.
- Rendering is not unnecessarily rebuilt.
- Theme-wide changes remain reliable.
- Cache correctness is tested.

---

# 12. Phase 10 — Command Palette Search

## Prompt 10.1 — Improve Fuzzy Matching

### Objective

Improve command-palette search quality using a lightweight local scoring algorithm.

### Requirements

Support:

- Case-insensitive matching.
- Prefix bonuses.
- Word-boundary bonuses.
- Consecutive-character bonuses.
- Subsequence matching.
- Match-position scoring.
- Stable sorting.

Keep the algorithm deterministic.

Avoid external dependencies.

Verified current state: matching is a case-insensitive substring test over the label and keywords, returned in insertion order. There is no subsequence matching or scoring.

### Acceptance Criteria

- Relevant matches rank above weak matches.
- Prefix matches receive appropriate priority.
- Word-boundary matches are rewarded.
- Search remains responsive.
- Existing command palette functionality remains unchanged.

---

# 13. Phase 11 — Serialization and Accessibility

These phases should begin only after the foundational systems are stable.

## Prompt 11.1 — Serialize Docking and Floating Layout

### Objective

Persist docking and floating panel arrangements.

### Requirements

Serialize:

- Dock tree.
- Split ratios.
- Active tabs.
- Floating panel position.
- Floating panel dimensions.
- Relevant window information.

Do not serialize:

- Raw pointers.
- GPU handles.
- Runtime-only resource references.
- Temporary interaction state.

Use versioned serialization.

Verified current state: `Scene_Save` walks the widget tree only. Floating panels are detached into `g.floats`, so they are lost. Split ratios are stored as widget weights, which the saver does not write. Active tab state is not saved.

### Acceptance Criteria

- Dock layouts survive save/load.
- Floating panels survive save/load.
- Invalid data is handled safely.
- Old files remain readable where possible.
- Serialization is deterministic.

## Prompt 11.2 — Native Accessibility Bridge

### Objective

Connect existing accessibility metadata to native accessibility APIs.

### Requirements

Keep semantic information backend-independent.

Implement platform bridges through the appropriate platform abstraction.

Preserve:

- Roles.
- Names.
- Descriptions.
- Relationships.
- State.
- Focus.
- Selection.
- Value information.

Do not add operating-system-specific logic to individual widgets.

Verified current state: the semantic model and `Access_Bridge` hooks exist. No platform bridge is implemented in `src/Window`.

### Acceptance Criteria

- Native accessibility tools can inspect supported widgets.
- Focus and selection changes are reflected.
- Widget destruction updates native references.
- Unsupported roles degrade gracefully.
- Platform-specific code remains isolated.

---

# 14. Phase 12 — Optional Advanced Features

These are separate projects and should not be bundled into foundational changes.

Potential future prompts:

- Virtualized tree views.
- Column reordering and advanced table interactions.
- Async image loading.
- Resource cache improvements.
- Custom cursor requests.
- Per-monitor DPI support.
- User-controlled UI zoom.
- Optional developer property inspector.
- GUI debugging and layout visualization.

Each should begin with a dedicated source audit and design proposal.

---

# 15. Final Validation Phase

## Prompt 15.1 — Full Architecture and Regression Audit

After all approved phases are implemented, perform a complete audit.

### Verify

- Stable widget identity.
- Generation validation.
- Widget destruction.
- Update ordering.
- Measurement.
- Arrangement.
- Constraint allocation.
- Scroll content sizing.
- Animation lifecycle.
- Frame scheduling.
- Draw-list reuse.
- Rendering backends.
- SDF behavior.
- Text shaping.
- Text editing.
- Undo history.
- Popup behavior.
- Focus behavior.
- Theme invalidation.
- Serialization.
- Accessibility metadata.
- Memory allocations.
- No memory leaks.

### Testing

Use the repaired harness: `odin check src/GUI -no-entry-point`, `odin check src/Tests -no-entry-point`, and `CALCUI_BENCH_BUDGET=0 odin test src/Tests`. Verify that the command reports the expected number of tests; a build that runs zero tests is not a pass.

Run all existing tests.

Run all new tests.

Run relevant benchmarks.

Test both SDL3 rendering backends.

Test representative applications and examples.

### Performance

Compare against the original baseline.

Report:

- Allocation counts.
- Layout timings.
- Rendering preparation timings.
- Idle CPU usage where measurable.
- Large widget-tree performance.
- Large virtual-list performance.
- Text-editing performance.

Do not claim performance improvements without measurements.

### Deliverables

Produce:

1. Final architecture summary.
2. Implemented feature list.
3. Remaining limitations.
4. Test results.
5. Benchmark comparisons.
6. API changes.
7. Migration notes.
8. Recommended next steps.

---

# 16. Execution Order

Follow this order:

| Phase | Work | Priority |
|---|---|---|
| 0.1 | Repository audit | Mandatory |
| 0.2 | Test harness repair and CI alignment | Mandatory prerequisite |
| 0.3 | Verified baseline corrections | Mandatory |
| 1 | Frame lifecycle, SDL rounded corners, allocations | Critical |
| 2 | Intrinsic measurement and scroll sizing | Critical |
| 3 | Constraints and flexible axis solver | Critical |
| 4 | Central animation system | High |
| 5 | Lazy redraw and frame scheduling | High |
| 6 | Shadows and SDF completion | High |
| 7 | Grid improvements | Medium |
| 8 | Text editing and shaping | Medium |
| 9 | Overlay and style optimization | Medium |
| 10 | Command palette search | Medium |
| 11 | Dock serialization and accessibility | Later |
| 12 | Optional advanced features | Later |
| 15 | Final regression audit | Mandatory |

Do not skip foundational phases simply because later features are more visually interesting.

---

# 17. Required Agent Response Format

At the end of each phase, report:

## Phase Summary

What was implemented.

## Source Changes

List files changed and explain their purpose.

## Architectural Decisions

Explain important decisions and why they fit the existing architecture.

## Tests

List tests added and tests executed.

## Results

Report pass/fail status, including the test command, the number of tests executed, and whether the harness compiled.

## Performance

Include measurements where relevant.

## Remaining Issues

List known limitations.

## Next Phase Readiness

State whether the next phase can safely begin.

---

# Final Instruction

The objective is to make CalcUI a mature, high-performance retained-mode GUI framework.

Do not turn this project into a collection of disconnected features.

The most important architectural priorities are:

1. Correct intrinsic measurement.
2. Reliable constraints and flexible allocation.
3. Centralized animation.
4. Efficient frame scheduling.
5. Unified rendering.
6. Allocation-conscious execution.
7. Correct text editing and shaping.

Preserve the existing strengths of CalcUI.

Use other Odin GUI projects as references for algorithms and implementation techniques, not as replacements for the architecture.

Every change must make the framework more coherent, more predictable, or more capable.

A working test harness is a precondition for every phase. Do not report a phase as complete while the suite cannot compile or the test command executes zero tests.