# Architecture review — xcmsVisGUI

Date: 2026-06-05 (file refs updated 2026-06-06 for the package
conversion). Method: two independent reviewers analysed the full
codebase (then `app.R`, `global.R`, all `R/*.R`, `test-smoke.R`,
`PLAN.md`, `CLAUDE.md`), then debated to consensus:

> **Note:** this review predates the R-package conversion. Where it says
> `app.R` read `R/run_app.R`; `global.R` is now split into `R/zzz.R`
> (the `.onLoad` SerialParam fix), `R/constants.R`, and `R/daemons.R`;
> `test-smoke.R` / `tests/run-tests.R` are now `tests/testthat/`. See
> the **Decision log** at the bottom for everything done *after* this
> review (package, cache, export, pkgdown, Docker, CI, persistent
> settings, xcmsVis).

- **Agent P** — pragmatic maintainer, bias toward low-risk incremental
  change.
- **Agent S** — structural/design-first, willing to argue for deeper
  refactors.

Every claim below was checked against the code by at least one reviewer
(a few initial overstatements were corrected in the debate — noted
inline). This document is the agreed plan, not a wish list.

------------------------------------------------------------------------

## Implementation status (updated 2026-06-05)

**All of Tier 1 and Tier 2 are implemented, tested, and committed on
`main`** (parse-checked, 72/72 unit + filter-equivalence assertions
green, app boots HTTP 200, key paths verified interactively). Each item
below is marked ✅ with its commit subject. The open question was
resolved: **no mtime cache key** (these raw files are not overwritten in
practice). Remaining ideas live in `future_work.md`.

| Item | Commit |
|----|----|
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

------------------------------------------------------------------------

## Verdict

The architecture is sound for its scope (single-user, local, **raw**
visualisation only). The load-bearing, easy-to-get-wrong parts — the
`SerialParam` + mzR-in-workers performance split, seconds-internally
time discipline, ColorBrewer/viridis-only colour, and cache keying — are
already centralised and respected. The remaining debt is **ordinary
duplication plus a real test gap**, with two spots where duplication is
a latent *correctness* hazard rather than a style nit.

Both reviewers explicitly **declined a structural rewrite.** The full
“data-service accessor layer” S originally proposed was withdrawn after
verifying the `rv` “god-object” pain is thinner than it looked:
`rv$filter` is constructed in exactly one place (`mod_filter.R:60-82`)
and the only real leak into plot modules is two lines reading
`rv$filter$ms_level`.

------------------------------------------------------------------------

## What is already good — do not touch

- **Centralised performance contract.** `register(SerialParam())` once
  in `R/zzz.R` (`.onLoad`); mirai workers only
  [`requireNamespace("mzR")`](https://github.com/sneumann/mzR/); heavy
  Spectra/xcms work in the main process. This is the whole performance
  story — off-limits.
- **Clean reactive graph** in the composition root: `included()` →
  `data_key()` → `raw_msexp()` (cached) → `dataset()` → modules
  (`R/run_app.R`).
- **Cache discipline**: `data_key()` keyed only on path-set + filter;
  `bindCache` on heavy reactives excludes cosmetic inputs.
- **Edge discipline**: seconds internally, conversion only at
  display/input edges; colours only through `fct_palettes.R`.
- **Good existing primitives**: `mod_export` (reusable, takes a
  `plot_gg` reactive), `zoom_keeper()` (encapsulates the hard-won plotly
  zoom-persistence trick — `uirevision` was already tried and did not
  hold zoom here).
- **The `fct_*.R` layer is Shiny-free** (no `input`/`output`/`rv`
  references) — i.e. the testable core is already isolated. It just
  isn’t tested.

------------------------------------------------------------------------

## Verified pain points

| \# | Issue | Evidence | Severity |
|----|----|----|----|
| 1 | The `ggplotly → keep_zoom → 3× event_register` chain is **byte-identical in 5 modules** | spectrum:159, tic_bpc:77, eic:178, map:114, precursors:81 | duplication; next zoom/click bug hides here |
| 2 | `apply_filters` (MsExperiment) and `apply_filters_spectra` (Spectra) are kept identical **by discipline only**, no test | `fct_filters.R:19-54` | **correctness hazard** — a filter that drifts between them silently shows wrong data in single-file views |
| 3 | Filter schema is spelled out in multiple spots | `make_rv()` default, `mod_filter.R:60-82`, both `apply_*`, plus benchmark literals | adding a filter = 4–5 scattered edits |
| 4 | `if (is.finite(rv$filter$ms_level)) … else 1L` duplicated; `rv$filter$ms_level` read directly inside plot modules | tic_bpc:36, eic:126 | filter logic leaks out of the filter layer |
| 5 | Per-file extraction loop (`lapply → extract → attach id/name/group → round(rt,3) scan-join → bind_rows`) re-implemented 3× | map:50-65, precursors:41-50, spectrum (facet/stacked):90-95; scan-join verbatim in map:59 and `add_scan_numbers` (`fct_extract.R`) | two parallel data pipelines to maintain |
| 6 | EIC-target append literal duplicated 3× | spectrum:167, eic:88, eic:101 | `tol=10`/`unit="ppm"` defaults can drift |
| 7 | **No automated tests of the pure core.** `test-smoke.R` only eyeballs printed output; `benchmarks/filter-test.R` already tests filter-equivalence but is a throwaway, unasserted, not run | no `tests/` dir | the layer most worth testing is untested |
| 8 | Multi-file extraction has no `tryCatch`; one unreadable/locked file aborts the whole plot (ingest, by contrast, *does* guard reads) | map/precursors/spectrum loops | one bad file in 20 = blank plot, the exact workflow the app exists for |
| 9 | Module-global caches never cleared on “Clear all” | `.scan_cache`/`.spectra_cache` in `fct_extract.R`; clear handler only does `rv$files <- rv$files[0,]` | unbounded growth across a long session |
| 10 | MS map renders plotly-native but **exports a separately-built ggplot**; 3D modes can’t export at all | `mod_plot_map.R` `output$plot_out` vs `export_gg` | on-screen and exported map can drift; silent 2D export from a 3D view |
| 11 | Committed clutter | logs, `*.out`, stray scripts at repo root | hygiene |

------------------------------------------------------------------------

## Consensus roadmap

Each item: **effort** (S/M/L) · **risk** (low/med/high) · **definition
of done**.

### Tier 1 — do now (low-risk, additive, high value) — ✅ ALL DONE

1.  ✅ **`finalize_plotly(p, source, keep_zoom)` helper** — S · low.
    *DoD:* the identical `ggplotly → keep_zoom → 3× event_register`
    chain (issue 1) is one call in all 5 modules; app boots HTTP 200;
    zoom + click still work on faahKO + msdata. A
    `wire_selection(source, plot_name)` helper for the near-identical
    click→`rv$selection` handler can ride along. *Done:* added
    `register_plotly_events` / `finalize_plotly` / `wire_selection`;
    click→spectrum verified interactively.

2.  ✅ **Filter-equivalence invariant test** — M · low. *The single
    highest-value item.* *DoD:* for a battery of filter configs
    (ms_level, rt, mz, intensity, polarity, spectrum_id), the spectra
    surviving `apply_filters` **equal** those surviving
    `apply_filters_spectra` on a real msdata file. Folds in the old
    `benchmarks/filter-test.R`. Makes the lock-step (issue 2) safe.
    *Done:* `tests/testthat/test-filters.R`. **Update (2026-06-06):**
    the original dependency-free `tests/run-tests.R` runner has since
    been folded into `tests/testthat/` as part of the package conversion
    — testthat (edition 3) is now the suite, run via
    `testthat::test_local(".")` / `R CMD check`.

3.  ✅ **Single filter schema + `make_filter()` constructor** — S/M ·
    low-med. *DoD:* `make_rv()` and `mod_filter` build the filter from
    one definition (issue 3). *Done:* `empty_filter()` + `make_filter()`
    in `fct_filters.R`.

4.  ✅ **Kill the `rv$filter$ms_level` leak** — S · low. *DoD:* a single
    `chrom_ms_level(filter)` helper holds the `… else 1L` default (issue
    4); tic/eic no longer read `rv$filter$ms_level` directly. *Done.*

5.  ✅ **Tests for the pure helpers** — S · low. *DoD:* covers rt
    round-trips, `bin_peaks`, `combined_ranges`, `polarity_label`,
    `isTRUE_vec`, scan-matching, palettes, filter helpers;
    `test-smoke.R` upgraded to assert. *Done:* `tests/test-helpers.R` (+
    smoke `stopifnot`). 72 assertions.

6.  ✅ **Per-file error isolation in the multi-file extraction loops** —
    S · low. *DoD:* one unreadable file is skipped + reported instead of
    aborting the plot (issue 8). *Done* via
    [`purrr::possibly`](https://purrr.tidyverse.org/reference/possibly.html)
    inside `extract_over_files` (item 8) — per request, `possibly`
    rather than `tryCatch`. Verified with a bogus path.

7.  ✅ **Repo hygiene** — S · trivial. *DoD:* logs / `*.out` / stray
    scripts git-ignored or removed (issue 11). *Done:* already covered
    by `.gitignore`; `benchmarks/filter-test.R` folded into the test
    suite and removed.

### Tier 2 — do opportunistically — ✅ ALL DONE (done now alongside Tier 1)

8.  ✅ **`extract_over_files(files_df, extractor, …)` unification** — M
    · low-med. *DoD:* the triplicated per-file loop + the `round(rt,3)`
    scan-join (issue 5) live in one helper; map/precursors/spectrum call
    it; output identical on real data. *Done* — also carries the item-6
    `possibly` isolation.

9.  ✅ **Small shared helpers**: `new_eic_target()` for the 3× append
    literal (issue 6); `scan_for_rt()` documenting the 3-decimal rt
    contract — S · low. *Done* (`scan_for_rt` landed with item 8;
    `new_eic_target` in `utils_reactive.R`).

10. ✅ **Disable the MS-map export button in 3D modes** — S · low.
    *DoD:* export hidden when `mode != "map"` (narrow fix for issue 10).
    *Done* via `conditionalPanel`. Full renderer unification stays
    declined.

11. ✅ **`clear_caches()` on file-set change** — S · low. *DoD:*
    `.scan_cache`/`.spectra_cache` emptied so memory doesn’t grow (issue
    9). *Done:* `clear_ms_caches()` called from the ingest **“Clear
    all”** handler (the precise W5 gap), rather than on every
    include-toggle (which would thrash the still-relevant per-path
    cache).

12. ✅ **Narrow the settings observer** — S · low. *DoD:* a cosmetic
    change doesn’t fan out beyond its consumers. *Done:* `rv$settings`
    is now a **nested `reactiveValues`** (per-field reactivity) written
    by per-field `observeEvent`s — verified: switching the time unit
    relabels axes without touching palette/export consumers.

### Tier 3 — explicitly declined

- **Full `data-service` accessor layer** — payoff is mostly aesthetic
  for a single-user local app; cost is app-wide signature + test churn
  at medium risk, to unit-test the layer (plot modules) least worth
  unit-testing. Replaced by the Tier-1 leak fix (item 4). *Both
  reviewers.*
- **Generic plot-module factory / R6 / S7 class hierarchy / plugin
  registry** — over-engineering for 5 fixed tabs; each view has real
  divergence (EIC target table, spectrum’s 3 layouts + scan-list modal,
  map’s 3 plotly-native modes). Extract the shared *tail*, not the whole
  module.
- **Plotly-map → ggplot renderer unification** — the two renderers are
  intentional (interactive scattergl/surface can’t be `ggsave`d; 3D
  can’t export to a static ggplot). Use item 10 instead.
- **`(path, mtime)` cache key** — see open question below; clear-only
  (item 11) is the agreed default.
- **Touching the SerialParam + mzR-in-workers split,
  `zoom_keeper`/`uirevision`, the seconds-internally rule, or the
  ColorBrewer constraint** — locked, documented dogmas. Off-limits.
- **Async-ifying heavy reads, a state-management framework, a
  DT-checkbox abstraction, a swappable-backend layer** — out of scope /
  speculative.
- **Peak picking / grouping / alignment** — deferred by design (see
  **Deferred: preprocessing** below).

------------------------------------------------------------------------

## Open question (one unresolved point)

**Should the caches additionally key on file mtime?** Agent P argued yes
— overwriting a file at the same path (re-running an acquisition on a
lab box) serves stale spectra silently. Agent S argued no — for a
single-user local app where the user typed the path and isn’t rewriting
files mid-session, this is a non-event, and clear-on-file-set-change
(item 11) already bounds the risk.

**Recommendation:** ship clear-only (item 11) now; add `(path, mtime)`
keying only if a user actually reports a re-acquisition/overwrite
workflow. Low stakes either way.

**✅ RESOLVED (2026-06-05):** the user confirmed these files are rarely
overwritten — **no mtime key.** Clear-only (item 11) shipped; mtime
declined.

------------------------------------------------------------------------

## Suggested execution order

✅ **Done** — all of Tier 1 and Tier 2 were implemented in this order
across separate parse-checked, test- and smoke-verified commits on
`main`. The post-review work (R package, CI, Docker, persistent
settings, default tol setting, persistent cache, rds export, spectrum
annotation) is now also done — see the Decision log below. Remaining
ideas (xcms objects, peak picking, CAMERA-style cross-sample grouping)
live in `future_work.md` and the **Deferred: preprocessing** section
below.

------------------------------------------------------------------------

## Decision log (work done after the review above)

Everything here landed on `main` after the Tier-1/Tier-2 roadmap, each
as its own parse-checked + `R CMD check`-clean commit. Recorded so these
decisions don’t get re-litigated.

### Packaging & infrastructure

- **Converted the sourced app into an installable R package.** `app.R` +
  the side-effecting tail of `global.R` → exported
  [`run_app()`](https://stanstrup.github.io/xcmsVisGUI/reference/run_app.md)
  in `R/run_app.R`; `global.R` split into `R/zzz.R` (`.onLoad` →
  `register(SerialParam())`), `R/constants.R`, `R/daemons.R`. Imports
  declared per-function via roxygen; NAMESPACE/`man/` are generated. The
  MS S4 stack (Spectra/MsExperiment/xcms/ BiocParallel/mzR) is called
  via `::` to dodge overlapping-generic conflicts.
- **Test suite → testthat (edition 3)** in `tests/testthat/`;
  `R CMD check` passes Status: OK. Real-data tests skip when
  `msdata`/`faahKO` are absent.
- **CI** — GitHub Actions `R-CMD-check.yaml` (full suite incl. real
  data) + `pkgdown.yaml`; renv autoloader disabled in CI.
- **pkgdown site** with a screenshot-driven usage guide
  (`vignettes/articles/usage.Rmd`, chromote-captured figures via
  `data-raw/capture-screenshots.R`). Replaced the hand-written
  `USER_GUIDE.md`.
- **Docker** wrapper (Bioconductor base) for server deployment.

### Persistence

- **Settings persist across restarts** — allow-listed fields written as
  JSON to the per-user config dir
  (`tools::R_user_dir("xcmsVisGUI","config")`,
  `R/fct_settings_store.R`). Chosen over an in-package file so a normal
  install is writable. Added a **default EIC tolerance** setting
  (value + ppm/Da).
- **Persistent extraction cache** (`R/fct_cache.R`) — heavy `bindCache`
  results (TIC/BPC + EIC tibbles) go into a **layered memory + disk**
  cache: memory is the fast in-session primary, disk is the persistent
  backing so re-opening the app with the same files + filter is instant.
  The disk layer is a custom cachem-compatible store serialising with
  **qs2 at `compress_level = 0`** (benchmarked: gzip RDS 1.5–4 s vs qs2
  L0 0.1–0.4 s at this app’s 0.5–1.5M-row result sizes, similar file
  size). LRU eviction past ~2 GB / 30 days. The raw `MsExperiment` stays
  in a **session (memory) cache only** — not worth disk-serialising an
  S4 object with a file-backed backend. `clear_ms_caches()` (“Clear
  all”) also resets the disk cache. **No mtime keying** (files aren’t
  overwritten in practice — confirmed with the user).

### Export

- **`rds` export** added alongside png/svg/pdf — saves the ggplot object
  itself (`save_gg()` rds branch), so a figure can be reopened and
  re-tweaked in R.

### Spectrum annotation (adducts / isotopes / in-source fragments)

Single-spectrum annotation overlaid on the Spectrum view
(`R/fct_annotate.R` + `mod_plot_spectrum`). **commonMZ** (GitHub-only,
hence the `Remotes:` field) is the adduct/fragment **dictionary**;
**InterpretMSSpectrum::findMAIN** is the auto **ranker** — both hard
Imports. Three modes share one dictionary so manual and auto annotate
identically: - **Manual anchor** — user designates a peak as a known
ion; we invert to the neutral mass
(`m/z = (nmol·M + massdiff)/|charge|`, massdiff from
[`commonMZ::MZ_CAMERA`](https://rdrr.io/pkg/commonMZ/man/MZ_CAMERA.html))
and project all adducts + M+1 isotopes + in-source neutral losses
([`commonMZ::adducts_fragments`](https://rdrr.io/pkg/commonMZ/man/package.html)),
matching within the shared ppm/Da tol. - **Auto-suggest** — `findMAIN`
(constrained to commonMZ’s quasi-molecular adducts) ranks (M,
main-adduct) hypotheses; the chosen row fills the anchor. - **Difference
network** — peak pairs whose Δm/z matches a dictionary entry.

Why **not** CAMERA / cliqueMS / RAMClustR: those need a multi-sample
feature matrix (coelution/correlation across detected peaks) —
incompatible with this app’s raw-only, one-spectrum-at-a-time model, and
prone to false hits on noisy raw scans. The anchor-first design puts the
molecular-ion decision with the user. The engine is pure (no Shiny) and
unit-tested on synthetic + real (`msdata`) spectra. Click
disambiguation: a *Click → EIC list \| → set anchor* toggle reuses the
existing spectrum-click plumbing. Annotation tolerance reuses the
persisted default-tolerance setting (no new persisted fields).
Re-encodes commonMZ’s Latin-1 origin text to UTF-8.

### xcmsVis — evaluated and declined (for now)

Re-examined whether to delegate plotting to **xcmsVis** (`gplot*` →
ggplot, amendable post-hoc with `+ aes()/geom_/scale_`). **Declined for
the current raw-only scope.** Reasons: 1. **Loadability** — in this R
install, *accessing any exported symbol* segfaults (reproducible, exit
139; likely a lazy-load/Rcpp-ABI issue after Rcpp 1.1.0→1.1.1).
[`library(xcmsVis)`](https://rdrr.io/r/base/library.html) loads but the
first symbol touch crashes — so it isn’t even callable here right now.
2. **Input type** — its methods dispatch on `XChromatograms` /
`XcmsExperiment` / `MChromatograms` (xcms/MSnbase result objects). We
deliberately extract to plain tibbles (cached, computed under
SerialParam); feeding xcmsVis means keeping xcms objects live, which
fights the qs2 tibble cache. 3. **Post-hoc `+` is additive only** — it
can’t rewire mappings already baked into existing layers. The GUI needs
exactly such changes: the `key` aesthetic on the line geom for plotly
click-nav, the seconds→display-unit transform, and ColorBrewer (xcmsVis
uses viridis/topo/gradientn). None retrofit via `+`. 4. **ggplotly
round-trip** isn’t guaranteed (custom `geom_polygon` fills; feature
views compose with **patchwork**, which `ggplotly()` can’t convert). 5.
**Scope** — most `gplot*` functions are peak/feature plots, the
territory we defer (see **Deferred: preprocessing** below).

**Revisit when:** peak picking lands — we’d then have `XcmsExperiment`
objects, the segfault is presumably fixed, and `gplotChromPeaks` /
`gplotFeatureGroups` could back dedicated peak views (adding our own
`key` layer on top is workable on fresh plots). Tracked in
`future_work.md`.

------------------------------------------------------------------------

## Original design (from the former PLAN.md)

The implementation plan is folded in here so there’s one design doc. The
as-built app diverges from it in two big ways (both covered above):
plotting is **not** delegated to xcmsVis (we build ggplots ourselves),
and it’s an R package rather than a sourced `app.R`/`global.R` app dir.
Everything else below held up.

**Locked decisions** (still in force):

| Decision | Choice |
|----|----|
| Deployment | **Local desktop**, single user |
| Scope | **Raw visualisation only** — no peak picking / grouping / alignment (deferred, below) |
| Async engine | **`ExtendedTask` + `mirai`** |
| Colours | **ColorBrewer / viridis** throughout |
| Testing | **Always test on real data** (`msdata` / `faahKO`) |

**Tech stack:** Shiny + `bslib` (`page_navbar`); Shiny modules (one per
plot + ingest/filter/settings); `Spectra`/`MsExperiment`/`xcms` with the
on-disk mzR backend; `DT` for the editable EIC target table; `ggsave`
for vector export (the ggplot is the export source of truth, plotly is
the on-screen widget only).

**Plot catalog** (the five raw-capable views that shipped): TIC/BPC
overlay (`chromatogram(aggregationFun="sum"/"max")`), multi-m/z EIC
(target table → mz-range matrix), click-driven Spectrum (nearest scan +
scan-list browser), 2D MS map + 3D points/surface (plotly-native), and
DDA Precursor ions.

**Design points worth keeping in mind** (resolved during the build): -
mirai workers return **extracted data** (tibbles), not live on-disk
`Spectra` handles — handles don’t cross process boundaries cleanly. -
`gplot(XcmsExperiment)` on raw data was avoided entirely (we extract TIC
/ MS map directly), sidestepping its “requires detected peaks”
coupling. - The Spectra **backend** question (`MsBackendMzR` vs
Memory/Sql/Hdf5) was settled by the perf investigation: on-disk mzR
under `SerialParam`, with header summaries read via raw mzR in workers.
See CLAUDE.md “THE performance story” (the standalone benchmark write-up
was filed as an upstream Bioconductor issue and removed from the repo).

------------------------------------------------------------------------

## Deferred: preprocessing (do NOT build now)

Out of current scope by design — recorded here (formerly PLAN.md §16) as
the brief for a future `mod_preprocess`. References elsewhere to “the
deferred preprocessing scope” point here.

- **Pipeline:** `findChromPeaks` (CentWave / MatchedFilter params UI) →
  `groupChromPeaks` (PeakDensity) → `adjustRtime` (Obiwarp / PeakGroups)
  → `groupFeatures`. Run async (ExtendedTask + mirai); keep the
  processed `XcmsExperiment` alongside the raw data.
- **Unlocks the peak/feature plots** — `gplotChromPeaks`,
  `gplotChromPeakImage`, `ghighlightChromPeaks` (peak overlay on EICs),
  `gplotChromPeakDensity` (param tuning), `gplotFeatureGroups`,
  `gplotAdjustedRtime` (alignment QC). This is the natural moment to
  **reconsider xcmsVis** (see the Decision log): we’d then have
  `XcmsExperiment` objects, which is exactly what its `gplot*` methods
  want.
- `gplotChromPeakDensity` is ideal for interactive `bw` / `minFraction`
  tuning.
- Also deferred: importing an already-processed `XcmsExperiment` /
  `.rds`.
