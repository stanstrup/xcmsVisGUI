# Architecture review — xcmsVisGUI

Date: 2026-06-05. Method: two independent reviewers analysed the full codebase
(`app.R`, `global.R`, all `R/*.R`, `test-smoke.R`, `PLAN.md`, `CLAUDE.md`), then
debated to consensus:

- **Agent P** — pragmatic maintainer, bias toward low-risk incremental change.
- **Agent S** — structural/design-first, willing to argue for deeper refactors.

Every claim below was checked against the code by at least one reviewer (a few
initial overstatements were corrected in the debate — noted inline). This
document is the agreed plan, not a wish list.

---

## Implementation status (updated 2026-06-05)

**All of Tier 1 and Tier 2 are implemented, tested, and committed on `main`**
(parse-checked, 72/72 unit + filter-equivalence assertions green, app boots HTTP
200, key paths verified interactively). Each item below is marked ✅ with its
commit subject. The open question was resolved: **no mtime cache key** (these raw
files are not overwritten in practice). Remaining ideas live in `future_work.md`.

| Item | Commit |
|---|---|
| T1.1 plotly render/click helpers | `Extract shared plotly render/click helpers` |
| T1.2 filter-equivalence test | `Add an asserting test suite (pure helpers + filter equivalence)` |
| T1.3 filter schema + make_filter / T1.4 ms_level leak | `Centralize the filter schema and chromatogram MS-level default` |
| T1.5 pure-helper tests + assert smoke | `Add an asserting test suite …` |
| T1.6 per-file error isolation / T2.8 extract_over_files | `Unify single-file extraction with per-file error isolation` |
| T1.7 hygiene | already covered by `.gitignore`; `benchmarks/filter-test.R` folded into tests |
| T2.9 new_eic_target / scan_for_rt | `Add new_eic_target() …` + `Unify single-file extraction …` |
| T2.10 map export 2D-only | `Show the MS-map export button only in 2D mode` |
| T2.11 clear caches on Clear all | `Clear the per-file caches when the file list is cleared` |
| T2.12 settings per-field reactive | `Make settings per-field reactive to stop change fan-out` |

---

## Verdict

The architecture is sound for its scope (single-user, local, **raw**
visualisation only). The load-bearing, easy-to-get-wrong parts — the
`SerialParam` + mzR-in-workers performance split, seconds-internally time
discipline, ColorBrewer/viridis-only colour, and cache keying — are already
centralised and respected. The remaining debt is **ordinary duplication plus a
real test gap**, with two spots where duplication is a latent *correctness*
hazard rather than a style nit.

Both reviewers explicitly **declined a structural rewrite.** The full
"data-service accessor layer" S originally proposed was withdrawn after
verifying the `rv` "god-object" pain is thinner than it looked: `rv$filter` is
constructed in exactly one place (`mod_filter.R:60-82`) and the only real leak
into plot modules is two lines reading `rv$filter$ms_level`.

---

## What is already good — do not touch

- **Centralised performance contract.** `register(SerialParam())` once in
  `global.R`; mirai workers only `library(mzR)`; heavy Spectra/xcms work in the
  main process. This is the whole performance story — off-limits.
- **Clean reactive graph** in the composition root: `included()` → `data_key()`
  → `raw_msexp()` (cached) → `dataset()` → modules (`app.R`).
- **Cache discipline**: `data_key()` keyed only on path-set + filter; `bindCache`
  on heavy reactives excludes cosmetic inputs.
- **Edge discipline**: seconds internally, conversion only at display/input
  edges; colours only through `fct_palettes.R`.
- **Good existing primitives**: `mod_export` (reusable, takes a `plot_gg`
  reactive), `zoom_keeper()` (encapsulates the hard-won plotly zoom-persistence
  trick — `uirevision` was already tried and did not hold zoom here).
- **The `fct_*.R` layer is Shiny-free** (no `input`/`output`/`rv` references) —
  i.e. the testable core is already isolated. It just isn't tested.

---

## Verified pain points

| # | Issue | Evidence | Severity |
|---|---|---|---|
| 1 | The `ggplotly → keep_zoom → 3× event_register` chain is **byte-identical in 5 modules** | spectrum:159, tic_bpc:77, eic:178, map:114, precursors:81 | duplication; next zoom/click bug hides here |
| 2 | `apply_filters` (MsExperiment) and `apply_filters_spectra` (Spectra) are kept identical **by discipline only**, no test | `fct_filters.R:19-54` | **correctness hazard** — a filter that drifts between them silently shows wrong data in single-file views |
| 3 | Filter schema is spelled out in multiple spots | `make_rv()` default, `mod_filter.R:60-82`, both `apply_*`, plus benchmark literals | adding a filter = 4–5 scattered edits |
| 4 | `if (is.finite(rv$filter$ms_level)) … else 1L` duplicated; `rv$filter$ms_level` read directly inside plot modules | tic_bpc:36, eic:126 | filter logic leaks out of the filter layer |
| 5 | Per-file extraction loop (`lapply → extract → attach id/name/group → round(rt,3) scan-join → bind_rows`) re-implemented 3× | map:50-65, precursors:41-50, spectrum (facet/stacked):90-95; scan-join verbatim in map:59 and `add_scan_numbers` (`fct_extract.R`) | two parallel data pipelines to maintain |
| 6 | EIC-target append literal duplicated 3× | spectrum:167, eic:88, eic:101 | `tol=10`/`unit="ppm"` defaults can drift |
| 7 | **No automated tests of the pure core.** `test-smoke.R` only eyeballs printed output; `benchmarks/filter-test.R` already tests filter-equivalence but is a throwaway, unasserted, not run | no `tests/` dir | the layer most worth testing is untested |
| 8 | Multi-file extraction has no `tryCatch`; one unreadable/locked file aborts the whole plot (ingest, by contrast, *does* guard reads) | map/precursors/spectrum loops | one bad file in 20 = blank plot, the exact workflow the app exists for |
| 9 | Module-global caches never cleared on "Clear all" | `.scan_cache`/`.spectra_cache` in `fct_extract.R`; clear handler only does `rv$files <- rv$files[0,]` | unbounded growth across a long session |
| 10 | MS map renders plotly-native but **exports a separately-built ggplot**; 3D modes can't export at all | `mod_plot_map.R` `output$plot_out` vs `export_gg` | on-screen and exported map can drift; silent 2D export from a 3D view |
| 11 | Committed clutter | logs, `*.out`, stray scripts at repo root | hygiene |

---

## Consensus roadmap

Each item: **effort** (S/M/L) · **risk** (low/med/high) · **definition of done**.

### Tier 1 — do now (low-risk, additive, high value) — ✅ ALL DONE

1. ✅ **`finalize_plotly(p, source, keep_zoom)` helper** — S · low.
   *DoD:* the identical `ggplotly → keep_zoom → 3× event_register` chain (issue 1)
   is one call in all 5 modules; app boots HTTP 200; zoom + click still work on
   faahKO + msdata. A `wire_selection(source, plot_name)` helper for the
   near-identical click→`rv$selection` handler can ride along.
   *Done:* added `register_plotly_events` / `finalize_plotly` / `wire_selection`;
   click→spectrum verified interactively.

2. ✅ **Filter-equivalence invariant test** — M · low. *The single highest-value item.*
   *DoD:* for a battery of filter configs (ms_level, rt, mz, intensity, polarity,
   spectrum_id), the spectra surviving `apply_filters` **equal** those surviving
   `apply_filters_spectra` on a real msdata file. Folds in the old
   `benchmarks/filter-test.R`. Makes the lock-step (issue 2) safe.
   *Done:* `tests/test-filters.R`. **Note:** implemented in a dependency-free
   runner (`tests/run-tests.R`), **not** `tests/testthat/` — testthat isn't in
   the renv library and the app is sourced, not installed. (See future_work:
   "make it into an R package" would move this to testthat.)

3. ✅ **Single filter schema + `make_filter()` constructor** — S/M · low-med.
   *DoD:* `make_rv()` and `mod_filter` build the filter from one definition
   (issue 3). *Done:* `empty_filter()` + `make_filter()` in `fct_filters.R`.

4. ✅ **Kill the `rv$filter$ms_level` leak** — S · low.
   *DoD:* a single `chrom_ms_level(filter)` helper holds the `… else 1L` default
   (issue 4); tic/eic no longer read `rv$filter$ms_level` directly. *Done.*

5. ✅ **Tests for the pure helpers** — S · low.
   *DoD:* covers rt round-trips, `bin_peaks`, `combined_ranges`, `polarity_label`,
   `isTRUE_vec`, scan-matching, palettes, filter helpers; `test-smoke.R` upgraded
   to assert. *Done:* `tests/test-helpers.R` (+ smoke `stopifnot`). 72 assertions.

6. ✅ **Per-file error isolation in the multi-file extraction loops** — S · low.
   *DoD:* one unreadable file is skipped + reported instead of aborting the plot
   (issue 8). *Done* via `purrr::possibly` inside `extract_over_files` (item 8) —
   per request, `possibly` rather than `tryCatch`. Verified with a bogus path.

7. ✅ **Repo hygiene** — S · trivial.
   *DoD:* logs / `*.out` / stray scripts git-ignored or removed (issue 11).
   *Done:* already covered by `.gitignore`; `benchmarks/filter-test.R` folded
   into the test suite and removed.

### Tier 2 — do opportunistically — ✅ ALL DONE (done now alongside Tier 1)

8. ✅ **`extract_over_files(files_df, extractor, …)` unification** — M · low-med.
   *DoD:* the triplicated per-file loop + the `round(rt,3)` scan-join (issue 5)
   live in one helper; map/precursors/spectrum call it; output identical on real
   data. *Done* — also carries the item-6 `possibly` isolation.

9. ✅ **Small shared helpers**: `new_eic_target()` for the 3× append literal
   (issue 6); `scan_for_rt()` documenting the 3-decimal rt contract — S · low.
   *Done* (`scan_for_rt` landed with item 8; `new_eic_target` in `utils_reactive.R`).

10. ✅ **Disable the MS-map export button in 3D modes** — S · low.
    *DoD:* export hidden when `mode != "map"` (narrow fix for issue 10).
    *Done* via `conditionalPanel`. Full renderer unification stays declined.

11. ✅ **`clear_caches()` on file-set change** — S · low.
    *DoD:* `.scan_cache`/`.spectra_cache` emptied so memory doesn't grow (issue 9).
    *Done:* `clear_ms_caches()` called from the ingest **"Clear all"** handler
    (the precise W5 gap), rather than on every include-toggle (which would thrash
    the still-relevant per-path cache).

12. ✅ **Narrow the settings observer** — S · low.
    *DoD:* a cosmetic change doesn't fan out beyond its consumers.
    *Done:* `rv$settings` is now a **nested `reactiveValues`** (per-field
    reactivity) written by per-field `observeEvent`s — verified: switching the
    time unit relabels axes without touching palette/export consumers.

### Tier 3 — explicitly declined

- **Full `data-service` accessor layer** — payoff is mostly aesthetic for a
  single-user local app; cost is app-wide signature + test churn at medium risk,
  to unit-test the layer (plot modules) least worth unit-testing. Replaced by the
  Tier-1 leak fix (item 4). *Both reviewers.*
- **Generic plot-module factory / R6 / S7 class hierarchy / plugin registry** —
  over-engineering for 5 fixed tabs; each view has real divergence (EIC target
  table, spectrum's 3 layouts + scan-list modal, map's 3 plotly-native modes).
  Extract the shared *tail*, not the whole module.
- **Plotly-map → ggplot renderer unification** — the two renderers are
  intentional (interactive scattergl/surface can't be `ggsave`d; 3D can't export
  to a static ggplot). Use item 10 instead.
- **`(path, mtime)` cache key** — see open question below; clear-only (item 11)
  is the agreed default.
- **Touching the SerialParam + mzR-in-workers split, `zoom_keeper`/`uirevision`,
  the seconds-internally rule, or the ColorBrewer constraint** — locked,
  documented dogmas. Off-limits.
- **Async-ifying heavy reads, a state-management framework, a DT-checkbox
  abstraction, a swappable-backend layer** — out of scope / speculative.
- **Peak picking / grouping / alignment** — deferred by design (`PLAN.md` §16).

---

## Open question (one unresolved point)

**Should the caches additionally key on file mtime?** Agent P argued yes —
overwriting a file at the same path (re-running an acquisition on a lab box)
serves stale spectra silently. Agent S argued no — for a single-user local app
where the user typed the path and isn't rewriting files mid-session, this is a
non-event, and clear-on-file-set-change (item 11) already bounds the risk.

**Recommendation:** ship clear-only (item 11) now; add `(path, mtime)` keying
only if a user actually reports a re-acquisition/overwrite workflow. Low stakes
either way.

**✅ RESOLVED (2026-06-05):** the user confirmed these files are rarely
overwritten — **no mtime key.** Clear-only (item 11) shipped; mtime declined.

---

## Suggested execution order

✅ **Done** — all of Tier 1 and Tier 2 were implemented in this order across
separate parse-checked, test- and smoke-verified commits on `main`. Remaining
ideas (R package, CI, Docker, persistent settings, default tol setting,
CommonMZ/CAMERA, xcms objects, persistent cache) are tracked in `future_work.md`.
