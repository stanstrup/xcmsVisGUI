# CLAUDE.md — working notes for xcmsVisGUI

Read this before changing anything. It captures the non-obvious
decisions, the performance traps, and the conventions this codebase
follows. Also read `ARCHITECTURE_REVIEW.md` — the single
design+architecture doc (folds in the former PLAN.md original design +
the deferred-preprocessing brief, and carries the Decision log: package
conversion, cache, export, xcmsVis). The perf root cause is summarised
below under “THE performance story” (the standalone BENCHMARK.md
write-up was filed upstream and removed). User-facing behaviour is in
the pkgdown usage guide (`vignettes/articles/usage.Rmd`).

## What this is

A **local desktop Shiny app** for interactively visualising **raw**
LC-MS data (TIC/BPC, EICs, spectra, 2D/3D MS maps, DDA precursors).
Single user, runs locally. Scope is **raw visualisation only** — no peak
picking / grouping / alignment (deferred; see `ARCHITECTURE_REVIEW.md` →
“Deferred: preprocessing”).

## Run / test (Windows dev box)

- R: `C:\Program Files\R\R-4.5.2\bin\Rscript.exe` (not on PATH — call by
  full path).
- **This is now an R package.** `R/` is package code (loaded via the
  namespace, not Shiny-auto-sourced); the app is the exported
  [`run_app()`](https://stanstrup.github.io/xcmsVisGUI/reference/run_app.md).
  Launch headless:
  `Rscript -e "pkgload::load_all('.'); run_app(port=7799, launch.browser=FALSE)"`
  (or `Rscript run.R`, which load_all’s + launches). Installed:
  [`xcmsVisGUI::run_app()`](https://stanstrup.github.io/xcmsVisGUI/reference/run_app.md).
- Tests (testthat, edition 3): `Rscript -e "testthat::test_local('.')"`
  (dev, load_all) or `R CMD check`. Real-data tests
  (filter-equivalence + extraction smoke) SKIP when msdata/faahKO are
  absent. `tests/testthat/` holds them.
- After changing imports/roxygen run
  `Rscript -e "roxygen2::roxygenise()"` to regenerate NAMESPACE +
  `man/`.
- `benchmarks/` holds throwaway timing/repro scripts; their `*.out` are
  git-ignored.
- After editing, ALWAYS: parse-check every R file (or `load_all`), then
  boot headless and confirm HTTP 200, before committing. Test
  plot/extraction logic on real data — never assume a plot works without
  running real MS data (faahKO, msdata, or the user’s urine files at
  `../Mcourse_new/data/2023/incognito_urine_A_vs_C_pos`).

## THE performance story (most important thing here)

Benchmarked: `Spectra(MsBackendMzR())` /
[`xcms::chromatogram()`](https://rdrr.io/pkg/ProtGenerics/man/protgenerics.html)
took **80–150 s/file** on real mzML. Root cause = **BiocParallel**:
`MsBackendMzR::backendInitialize` reads headers via
`bplapply(files, ..., BPPARAM = bpparam())`, and the Windows default is
`SnowParam(6)` — it spawns a socket cluster (each worker reloading the
Bioc stack) per call. Fix: **`register(SerialParam())`** → 0.2–1.6 s.
Done in **`.onLoad` (`R/zzz.R`)** so every read path (the app AND the
test suite) gets it.

Consequences baked into the architecture: - `.onLoad` (`R/zzz.R`) calls
`BiocParallel::register(SerialParam())`. **Do not remove it.**
([`run_app()`](https://stanstrup.github.io/xcmsVisGUI/reference/run_app.md)
adds the mirai daemon pool + large-upload option; daemons are NOT
spawned on package load.) - File-list **header summaries** are read with
**raw mzR** (`read_ms_header`, ~0.1 s) in mirai workers — even
SerialParam Spectra reads are ~5 s/file, too slow for 100+ files.
Workers only [`library(mzR)`](https://github.com/sneumann/mzR/) (no
BiocParallel). - Heavy **plotting/filtering** uses Spectra/xcms in the
**main process** under SerialParam (`chromatogram`, `extract_peaks`,
`extract_spectrum`, filters). This regains the full Spectra filter
set. - Git history preserves alternatives: the Spectra baseline (commit
`Spectra/xcms baseline`) and a pure-mzR version (commit
`Replace Spectra data layer with direct mzR`). If Spectra fixes the
SnowParam default upstream, the SerialParam workaround can be dropped.

## Architecture / data flow

- `R/run_app.R`: `app_ui()` builds the bslib `page_navbar` (sidebar with
  Files (`mod_ingest`) + Filters (`mod_filter`); nav panels = plot
  modules); `app_server()` builds `included` (ticked + ready files),
  `meta` (id/name/path/group), `data_key` (paths + filter), a cached
  `raw_msexp` (`build_msexp`, keyed on path set) and `dataset` (=
  `apply_filters(raw)`).
  [`run_app()`](https://stanstrup.github.io/xcmsVisGUI/reference/run_app.md)
  does runtime setup + `shinyApp` + `runApp`.
- **Package layout (not an app-dir):** what was `global.R` is split into
  `R/zzz.R` (`.onLoad` → SerialParam), `R/constants.R` (constants + rt
  helpers), `R/daemons.R` (`set_daemons`/`setup_runtime`).
  `R/xcmsVisGUI-package.R` holds the roxygen import declarations;
  NAMESPACE/`man/` are roxygen-generated — don’t hand-edit.
- Central reactive state: `make_rv()` in `R/utils_reactive.R`
  (rv$`files, rv`$eic_targets, rv$`selection, rv`$filter, rv\$settings).
  One `rv` passed to every module.
- Modules (`R/mod_*.R`): one per plot + ingest/filter/settings/export.
  Plot modules return a reactive ggplot `plot_gg` (the export source of
  truth) and render `ggplotly(plot_gg())`. The MS map is plotly-native
  (scattergl/surface).

## Key files

| file | role |
|----|----|
| `R/fct_extract.R` | all data extraction: `read_ms_header` (mzR), `build_msexp`, `chromatogram` helpers, `extract_peaks/_spectrum/_precursors`, `file_scan_table` (cached), `add_scan_numbers`, `bin_peaks` |
| `R/fct_filters.R` | `apply_filters` (MsExperiment) + `apply_filters_spectra` (Spectra) — keep them consistent; `combined_ranges` for filter hints |
| `R/fct_palettes.R` | `brewer_qual/seq/colorscale` (ColorBrewer + viridis; `invert` reverses) |
| `R/fct_export.R` | `save_gg` (png/svg/pdf via ggsave; **rds** = save the ggplot object itself) |
| `R/fct_cache.R` | `cache_disk_qs2` (qs2 disk store), `app_cache` (layered mem+disk), `clear_disk_cache` |
| `R/fct_settings_store.R` | `load_settings`/`save_settings` — persist allow-listed settings as JSON to the per-user config dir |
| `R/fct_annotate.R` | spectrum annotation engine (pure): `adduct_rules`/`quasi_adducts` (commonMZ dict), `neutral_mass`/`adduct_mz`/`project_ions`, `match_spectrum`, `annotate_anchor` (manual), `rank_anchors` (findMAIN auto), `difference_network`, `centroid_peaks`. Overlaid by `mod_plot_spectrum`’s `annotate_layers` |
| `R/utils_reactive.R` | `make_rv`, `zoom_keeper`, helpers |

## Conventions / dogmas

- **Colours: ColorBrewer / viridis only** (user preference). Qualitative
  for groups/traces, sequential for maps. Honour
  `rv$settings$invert_scale`.
- **Time: data is always SECONDS internally**; convert at display/input
  edges with `rt_to_disp` / `rt_to_sec` / `rt_axis_label` (unit =
  `rv$settings$time_unit`). Plotly click `x` is in the display unit →
  convert back to seconds for `rv$selection`.
- **Filters apply everywhere.** Single-file views (spectrum, map) must
  go through `apply_filters_spectra` so intensity/spectrum-id/etc. reach
  them — don’t read raw.
- **Zoom persistence**: use `zoom_keeper(source)` (captures
  `plotly_relayout`, re-applies the range each render) — `uirevision`
  did NOT hold zoom here. Keep `dynamicTicks=TRUE`.
- **Caching**: heavy reactives use `bindCache` keyed on `data_key()` (+
  their own inputs). `file_scan_table` / `.ms_cache` cache per-file
  reads in memory. Don’t key caches on cosmetic inputs (colour,
  contrast, points) — that breaks zoom and wastes work. The app-level
  `bindCache` store (`shinyOptions(cache=)` in `setup_runtime`) is the
  **layered mem+disk** `app_cache()` from `R/fct_cache.R`: in-session
  hits stay in memory; the **disk** layer (qs2, `compress_level=0`,
  under `R_user_dir(...,"cache")`) persists TIC/EIC tibbles across
  restarts. **No mtime keying** (files aren’t overwritten in practice).
  `raw_msexp` uses the in-memory `"session"` cache only — the
  MsExperiment is a file-backed S4 object, not worth disk-serialising.
  Clear-all resets the disk cache via `clear_ms_caches` →
  `clear_disk_cache`.
- **Settings persist** across restarts (`fct_settings_store.R`): an
  allow-list (`.PERSISTED_SETTINGS`) is written as JSON to
  `R_user_dir("xcmsVisGUI","config")` (not the package dir — must work
  for a normal install). Restored on startup, saved debounced.
- **Cross-plot nav** via `rv$selection` (list: plot, file_id, rt\[sec\],
  mz). A plotly `key = sample_id` aesthetic carries the file id into
  click events.
- **Heavy single-file views are gated** (MS map “Plot” button) so they
  don’t auto-render on every change.
- Match surrounding **code style**: 2-space indent, `<-` assignment,
  roxygen-ish `#'` comments on helpers, `ggplot2::`/`Spectra::`
  namespacing in `fct_*` (modules may use attached funcs). Keep comments
  about *why*, not *what*.

## Gotchas

- mzR prints a benign Rcpp ABI warning on load — ignore (rebuilding mzR
  didn’t change it).
- [`mzR::openMSfile`](https://rdrr.io/pkg/mzR/man/openMSfile.html) reads
  CDF too, not just mzML/mzXML.
- CDF headers carry no m/z range (sentinel −1) and unset polarity —
  mapped to NA/blank.
- ggplot2 is v4 (S7 objects) — don’t mutate `aes()` objects; build geoms
  conditionally.
- Don’t use PowerShell here-strings (`@'...'@`) in the Bash tool — they
  leak a stray `@`.
- shinyFiles was removed (users disliked the custom modal); loading =
  typed path (no copy) + native `fileInput` Browse (copies to temp —
  documented trade-off).
- **xcmsVis is NOT used** — we build ggplots ourselves. It was evaluated
  and declined for the raw-only scope (wrong input type, can’t carry the
  `key`/time-unit/ColorBrewer aesthetics via post-hoc `+`, doesn’t
  ggplotly cleanly, mostly peak/feature plots) and it currently
  *segfaults on first symbol access* in this R install. Full rationale +
  “revisit when peak picking lands” in `ARCHITECTURE_REVIEW.md` Decision
  log. Don’t add it back without checking that.

## Git workflow

Commit **sequentially**, one logical change per commit. End messages
with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. Author
is Jan Stanstrup <stanstrup@gmail.com>.
