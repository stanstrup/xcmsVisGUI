# CLAUDE.md — working notes for xcmsVisGUI

Read this before changing anything. It captures the non-obvious decisions, the
performance traps, and the conventions this codebase follows. Also read
`ARCHITECTURE_REVIEW.md` — the single design+architecture doc (folds in the former
PLAN.md original design + the deferred-preprocessing brief, and carries the Decision
log: package conversion, cache, export, xcmsVis). The perf root cause is summarised
below under "THE performance story" (the standalone BENCHMARK.md write-up was filed
upstream and removed). User-facing behaviour is in the pkgdown usage guide
(`vignettes/articles/usage.Rmd`).

## What this is
A **local desktop Shiny app** for interactively visualising **raw** LC-MS data
(TIC/BPC, EICs, spectra, 2D/3D MS maps, DDA precursors). Single user, runs locally.
Scope is **raw visualisation only** — no peak picking / grouping / alignment
(deferred; see `ARCHITECTURE_REVIEW.md` → "Deferred: preprocessing").

## Run / test (Windows dev box)
- R: `C:\Program Files\R\R-4.6.0\bin\Rscript.exe` (not on PATH — call by full path).
  (4.5.0/4.5.2 are also installed; use 4.6.0. Each minor version has its OWN package
  library under `AppData/Local/R/win-library/<x.y>`, so after switching, deps must be
  present there — they are for 4.6.0.)
- **This is now an R package.** `R/` is package code (loaded via the namespace, not
  Shiny-auto-sourced); the app is the exported `run_app()`. Launch headless:
  `Rscript -e "pkgload::load_all('.'); run_app(port=7799, launch.browser=FALSE)"`
  (or `Rscript run.R`, which load_all's + launches). Installed: `xcmsVisGUI::run_app()`.
- Tests (testthat, edition 3): `Rscript -e "testthat::test_local('.')"` (dev, load_all)
  or `R CMD check`. Real-data tests (filter-equivalence + extraction smoke) SKIP when
  msdata/faahKO are absent. `tests/testthat/` holds them.
- After changing imports/roxygen run `Rscript -e "roxygen2::roxygenise()"` to regenerate
  NAMESPACE + `man/`.
- `benchmarks/` holds throwaway timing/repro scripts; their `*.out` are git-ignored.
- After editing, ALWAYS: parse-check every R file (or `load_all`), then boot headless and
  confirm HTTP 200, before committing. Test plot/extraction logic on real data — never assume
  a plot works without running real MS data (faahKO, msdata, or the user's urine files
  at `../Mcourse_new/data/2023/incognito_urine_A_vs_C_pos`).

## THE performance story (most important thing here)
Benchmarked: `Spectra(MsBackendMzR())` / `xcms::chromatogram()` took **80–150 s/file**
on real mzML. Root cause = **BiocParallel**: `MsBackendMzR::backendInitialize` reads
headers via `bplapply(files, ..., BPPARAM = bpparam())`, and the Windows default is
`SnowParam(6)` — it spawns a socket cluster (each worker reloading the Bioc stack) per
call. Fix: **`register(SerialParam())`** → 0.2–1.6 s. Done in **`.onLoad` (`R/zzz.R`)**
so every read path (the app AND the test suite) gets it.

Consequences baked into the architecture:
- `.onLoad` (`R/zzz.R`) calls `BiocParallel::register(SerialParam())`. **Do not remove it.**
  (`run_app()` adds the mirai daemon pool + large-upload option; daemons are NOT spawned
  on package load.)
- File-list **header summaries** are read with **raw mzR** (`read_ms_header`, ~0.1 s) in
  mirai workers — even SerialParam Spectra reads are ~5 s/file, too slow for 100+ files.
  Workers only `library(mzR)` (no BiocParallel).
- Heavy **plotting/filtering** uses Spectra/xcms in the **main process** under SerialParam
  (`chromatogram`, `extract_peaks`, `extract_spectrum`, filters). This regains the full
  Spectra filter set.
- Git history preserves alternatives: the Spectra baseline (commit `Spectra/xcms baseline`)
  and a pure-mzR version (commit `Replace Spectra data layer with direct mzR`). If Spectra
  fixes the SnowParam default upstream, the SerialParam workaround can be dropped.

## Architecture / data flow
- `R/run_app.R`: `app_ui()` builds the bslib `page_navbar` (sidebar with Files
  (`mod_ingest`) + Filters (`mod_filter`); nav panels = plot modules); `app_server()`
  builds `included` (ticked + ready files), `meta` (id/name/path/group), `data_key`
  (paths + filter), a cached `raw_msexp` (`build_msexp`, keyed on path set) and `dataset`
  (= `apply_filters(raw)`). `run_app()` does runtime setup + `shinyApp` + `runApp`.
  **`included` is `debounce`d** (`SELECTION_DEBOUNCE_MS`): it is the root of every
  extraction, and each tick in the file list writes one row of `rv$files$include`,
  so unticking ten files used to cost ten full re-extracts. shiny's `debounce`
  emits its first value with no delay, so startup is unaffected. The file table
  reads `rv$files` directly and still responds instantly.
- **Package layout (not an app-dir):** what was `global.R` is split into `R/zzz.R`
  (`.onLoad` → SerialParam), `R/constants.R` (constants + rt helpers), `R/daemons.R`
  (`set_daemons`/`setup_runtime`). `R/xcmsVisGUI-package.R` holds the roxygen import
  declarations; NAMESPACE/`man/` are roxygen-generated — don't hand-edit.
- Central reactive state: `make_rv()` in `R/utils_reactive.R` (rv$files, rv$eic_targets,
  rv$selection, rv$filter, rv$settings). One `rv` passed to every module.
- Modules (`R/mod_*.R`): one per plot + ingest/filter/settings/export. Plot modules
  return a reactive ggplot `plot_gg` (the export source of truth) and render
  `ggplotly(plot_gg())`. The MS map is plotly-native (scattergl/surface).

## Key files
| file | role |
|---|---|
| `R/fct_extract.R` | all data extraction: `read_ms_header` (mzR), `build_msexp`, `chromatogram` helpers, `extract_peaks/_spectrum/_precursors`, `file_scan_table` (cached), `add_scan_numbers`, `bin_peaks` |
| `R/fct_filters.R` | `apply_filters` (MsExperiment) + `apply_filters_spectra` (Spectra, optional `cp` peak-picking) — keep them consistent; `centroid_spec`/`profile_ms_levels`/`centroid_ms_levels` (peak picking); `combined_ranges` for filter hints |
| `R/fct_palettes.R` | `brewer_qual/seq/colorscale` (ColorBrewer + viridis; `invert` reverses) |
| `R/fct_export.R` | `save_gg` (png/svg/pdf via ggsave; **rds** = save the ggplot object itself) |
| `R/fct_cache.R` | `cache_disk_qs2` (qs2 disk store), `app_cache` (layered mem+disk), `clear_disk_cache` |
| `R/fct_settings_store.R` | `load_settings`/`save_settings` — persist allow-listed settings as JSON to the per-user config dir |
| `R/fct_annotate.R` | spectrum annotation engine (pure): `adduct_rules`/`quasi_adducts` (commonMZ dict), `neutral_mass`/`adduct_mz`/`project_ions`, `match_spectrum`, `annotate_anchor` (manual), `rank_anchors` (findMAIN auto), `difference_network`, `centroid_peaks`. Overlaid by `mod_plot_spectrum`'s `annotate_layers`. **Matching pool is real `pickPeaks` centroids** built by the module's `ann_candidates()` at the user's Match S/N (not the raw trace); the engine's `centroid_peaks` is a pass-through on those, and callers pass `rel_floor = 0` (no hidden floor). |
| `R/fct_isotope.R` | fine isotope-pattern engine (pure): `formula_candidates` (Rdisop from neutral mass), `scale_formula`, `isotope_pattern` (enviPat isotopologues → adduct ion m/z, reusing `adduct_rules`), `isotope_profile` (Gaussian envelope at a resolving power), `estimate_resolution` (from an observed profile peak's FWHM). Wired into `mod_plot_spectrum`'s `ann_mode == "iso"`. Adds enviPat + Rdisop deps. |
| `R/utils_reactive.R` | `make_rv`, `zoom_keeper` (`$apply`/`$ranges`), `with_plotly_aes`, `centroid_controls_ui`/`read_centroid_spec` (shared Peak-picking panel), helpers |

## Conventions / dogmas
- **Colours: ColorBrewer / viridis only** (user preference). Qualitative for
  groups/traces, sequential for maps. Honour `rv$settings$invert_scale`.
- **Time: data is always SECONDS internally**; convert at display/input edges with
  `rt_to_disp` / `rt_to_sec` / `rt_axis_label` (unit = `rv$settings$time_unit`).
  Plotly click `x` is in the display unit → convert back to seconds for `rv$selection`.
- **Filters apply everywhere.** Single-file views (spectrum, map) must go through
  `apply_filters_spectra` so intensity/spectrum-id/etc. reach them — don't read raw.
  Peak picking is the ONE thing that is NOT a filter (below): it is data processing,
  a separate `cp` arg, so filter == which spectra, cp == how to reduce them.
- **Profile mode / peak picking** — `centroid_spec(mode, snr, hws, k)`, a per-view
  processing spec passed as `apply_filters_spectra(sp, f, cp)` / `extract_*(..., cp)`,
  NOT part of the filter. `apply_filters_spectra` peak-picks profile scans via
  `Spectra::pickPeaks()` — a *lazy* step, so nothing materialises until a view reads
  peaks. Why it matters: one profile Orbitrap MS1 scan is ~17k points and a file ~29M
  (690 MB) — the MS map was unusable and the spectrum drew 17k sticks. Picked: 1.4k /
  2M (48 MB).
  - **Owned per view, not global** (user: "it's data processing, not a filter"). Each
    view that draws peaks has its own **Peak-picking panel** (`centroid_controls_ui` +
    `read_centroid_spec`, shared in `utils_reactive.R`). Defaults differ: **Spectrum**
    opens on `off` (raw trace — you came to see the data), **MS map** on `auto` (raw is
    tens of millions of points there). Modes: `off` / `auto` (pick detected-profile
    levels) / `on` (force all levels). `cp = NULL` means no picking.
  - **Exposed pickPeaks knobs**: `snr` (S/N floor), `hws` (half-window for local-max),
    `k` (m/z refinement = intensity-weighted mean of ±k raw points). Not exposed:
    `method`/`descending`/`threshold` (niche). Sub-controls show only when picking on.
  - **Detection is per MS LEVEL, not per file** (`profile_ms_levels`). Mixed files
    (profile MS1 + centroided MS2) are the norm on Thermo DDA, and pickPeaks over an
    already-centroided spectrum DROPS every peak whose neighbour is more intense —
    it would gut the MS2s. Hence `pickPeaks(msLevel. = <profile levels>)`.
    Source of truth = the file's `centroided` flag (mzML has it per spectrum; mzR and
    Spectra both expose it), falling back to `Spectra::isCentroided()` peak-shape
    sniffing when absent (CDF). Undecidable → treat as centroided; never pick on a guess.
  - **Chromatograms are NEVER centroided** (`apply_filters` takes no `cp`): TIC/BPC/EIC
    sum/max over an m/z window, which is correct on profile samples and reproduces the
    instrument's TIC. With `cp = NULL` `apply_filters_spectra` is a pure filter and
    matches `apply_filters` — the equivalence invariant the filter tests rest on.
  - **`Spectra::pickPeaks` must be namespaced** — attaching xcms pulls in an MSnbase
    `pickPeaks` generic that masks ProtGenerics', and a bare call fails to dispatch.
  - Peak-level filters (m/z, intensity) run AFTER picking; an intensity floor applied
    to profile samples would clip the flanks off every peak before pickPeaks saw it.
  - The spectrum view draws raw profile as a **line**, not sticks (`profile` column
    from `extract_spectrum`), and snaps peak clicks to the apex (`PROFILE_SNAP_DA`).
- **Zoom persistence**: use `zoom_keeper(source)` (captures `plotly_relayout`, re-applies
  the range each render) — `uirevision` did NOT hold zoom here. Keep `dynamicTicks=TRUE`.
  It returns a **list**: `$apply` (pipe the plotly object through it) and `$ranges` (a
  reactive `list(x=,y=)`). Pass `$ranges` to `mod_export_server(..., zoom=)` so **Save
  plot saves what you are looking at** — `apply_zoom()` turns it into `coord_cartesian`
  limits on the ggplot before the preview/ggsave render. `$apply` isolates the range
  (re-reading it reactively caused an autorange feedback loop); `$ranges` does not,
  because the export preview *should* follow the zoom.
- **The plotly-only aesthetics** `text` (tooltip) and `key` (click file id) are unknown
  to ggplot2. A plot-level `aes()` passes unchecked, but any `geom_*(aes(text=))` warns
  "Ignoring unknown aesthetics" at layer-construction time. Wrap those layers in
  `with_plotly_aes()` (`utils_reactive.R`), which mutes that warning **only** for
  `text`/`key` — a genuinely misspelled aesthetic still surfaces.
- **Legends of file names go below the plot** (`theme(legend.position = "bottom")` on
  TIC/EIC): a right-hand legend of long file names eats the plot width. ggplotly maps
  it to a horizontal legend under the x axis.
- **Caching**: heavy reactives use `bindCache` keyed on `data_key()` (+ their own inputs).
  `file_scan_table` / `.ms_cache` cache per-file reads in memory. Don't key caches on
  cosmetic inputs (colour, contrast, points) — that breaks zoom and wastes work.
  The app-level `bindCache` store (`shinyOptions(cache=)` in `setup_runtime`) is the
  **layered mem+disk** `app_cache()` from `R/fct_cache.R`: in-session hits stay in
  memory; the **disk** layer (qs2, `compress_level=0`, under `R_user_dir(...,"cache")`)
  persists TIC/EIC tibbles across restarts. **No mtime keying** (files aren't
  overwritten in practice). `raw_msexp` uses the in-memory `"session"` cache only — the
  MsExperiment is a file-backed S4 object, not worth disk-serialising. Clear-all resets
  the disk cache via `clear_ms_caches` → `clear_disk_cache`.
- **Settings persist** across restarts (`fct_settings_store.R`): an allow-list
  (`.PERSISTED_SETTINGS`) is written as JSON to `R_user_dir("xcmsVisGUI","config")`
  (not the package dir — must work for a normal install). Restored on startup, saved
  debounced.
- **Cross-plot nav** via `rv$selection` (list: plot, file_id, rt[sec], mz). A plotly
  `key = sample_id` aesthetic carries the file id into click events.
- **Heavy single-file views are gated** (MS map "Plot" button) so they don't auto-render
  on every change.
- Match surrounding **code style**: 2-space indent, `<-` assignment, roxygen-ish `#'`
  comments on helpers, `ggplot2::`/`Spectra::` namespacing in `fct_*` (modules may use
  attached funcs). Keep comments about *why*, not *what*.

## Gotchas
- mzR prints a benign Rcpp ABI warning on load — ignore (rebuilding mzR didn't change it).
- `mzR::openMSfile` reads CDF too, not just mzML/mzXML.
- CDF headers carry no m/z range (sentinel −1) and unset polarity — mapped to NA/blank.
- ggplot2 is v4 (S7 objects) — don't mutate `aes()` objects; build geoms conditionally.
- Don't use PowerShell here-strings (`@'...'@`) in the Bash tool — they leak a stray `@`.
- shinyFiles was removed (users disliked the custom modal); loading = typed path
  (no copy) + native `fileInput` Browse (copies to temp — documented trade-off).
- **xcmsVis is NOT used** — we build ggplots ourselves. It was evaluated and declined
  for the raw-only scope (wrong input type, can't carry the `key`/time-unit/ColorBrewer
  aesthetics via post-hoc `+`, doesn't ggplotly cleanly, mostly peak/feature plots) and
  it currently *segfaults on first symbol access* in this R install. Full rationale +
  "revisit when peak picking lands" in `ARCHITECTURE_REVIEW.md` Decision log. Don't add
  it back without checking that.

## Git workflow
Commit **sequentially**, one logical change per commit. End messages with
`Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. Author is
Jan Stanstrup <stanstrup@gmail.com>.
