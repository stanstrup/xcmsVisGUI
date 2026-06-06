# xcmsVisGUI — Implementation Plan

A local Shiny desktop app — a lightweight, raw-data-focused “mzMine
viewer” — built on the RforMassSpectrometry stack (`Spectra` /
`MsExperiment` / `xcms`) with all plotting delegated to **xcmsVis**
(`gplot*` → ggplot → plotly). Point it at mzML/mzXML/CDF files, explore
them interactively, filter richly, and export publication-quality
figures.

## Locked decisions

| Decision | Choice |
|----|----|
| Deployment | **Local desktop** (single user, like mscurate) |
| Scope | **Raw visualization only** — no peak picking / grouping / alignment (deferred, see §16) |
| Async engine | **`ExtendedTask` + `mirai`** |
| Colors | **ColorBrewer** palettes throughout (`RColorBrewer`, e.g. Set1/Set2/Dark2) |
| Testing | **Always test on real data** using xcmsVis’s own example datasets (§15) |

### Scope note on “all xcmsVis plots”

Six of xcmsVis’s eleven `gplot*` functions need a *processed*
`XcmsExperiment` (detected peaks / features / RT alignment) and cannot
run on raw data. The five **raw-capable** plots are core (§7). The
peak/feature plots are **wired but disabled** with a tooltip, so a
future Preprocess module (§16) lights them up without rework.

## 2. Tech stack

| Concern | Choice | Why |
|----|----|----|
| App framework | **Shiny + `bslib`** (`page_navbar` / `page_sidebar`, cards) | Modern layout, theming |
| Module system | **Shiny modules** (`moduleServer`) | One module per plot + ingest/filter/settings; testable |
| MS data | `Spectra`, `MsExperiment`, `xcms` (`chromatogram()`), on-disk backend | Matches xcmsVis; low RAM |
| Plotting | **xcmsVis `gplot*`** → [`plotly::ggplotly()`](https://rdrr.io/pkg/plotly/man/ggplotly.html) | Single source of truth; ggplot kept for vector export |
| Async | **`ExtendedTask` + `mirai`** | Non-blocking reads, per-file progress |
| File picking | **`shinyFiles`** path picker + dropzone for small files | Multi-GB files read in place, no upload |
| Tables/input | `DT` (editable EIC table), `shinyWidgets` | EIC list entry, file list with checkboxes |
| Colors | `RColorBrewer` | Consistent qualitative/sequential palettes |
| Export | [`ggplot2::ggsave`](https://ggplot2.tidyverse.org/reference/ggsave.html) (svg/pdf/png) + optional plotly/kaleido | Vector quality from the ggplot |

## 3. Project structure

    xcmsVisGUI/
    ├── app.R                      # shinyApp(ui, server) — thin entry
    ├── global.R                   # library(), mirai daemons, conflicts, constants, palettes
    ├── R/
    │   ├── mod_ingest.R           # shinyFiles + dropzone, ExtendedTask reader, file list + include checkboxes
    │   ├── mod_settings.R         # backend choice, palette, defaults, daemon count
    │   ├── mod_filter.R           # global rt/mz/msLevel/polarity/intensity filters
    │   ├── mod_plot_tic_bpc.R     # TIC/BPC, single + multi-file overlay
    │   ├── mod_plot_eic.R         # EIC list module (centerpiece)
    │   ├── mod_plot_spectrum.R    # click-driven spectrum view
    │   ├── mod_plot_msmap.R       # 2D heatmap (rt×mz×int)
    │   ├── mod_plot_3d.R          # 3D scatter/surface
    │   ├── mod_plot_precursors.R  # gplotPrecursorIons (DDA)
    │   ├── mod_export.R           # download modal: format/dpi/size
    │   ├── fct_extract.R          # Spectra/chromatogram helpers (run in mirai)
    │   ├── fct_filters.R          # compose Spectra filter* calls
    │   ├── fct_palettes.R         # ColorBrewer helpers
    │   └── utils_reactive.R       # shared reactiveVals / data model
    └── tests/                     # testServer() module tests + real-data smoke tests

## 4. Data model (central reactive state)

A single `reactiveValues` (`rv`), populated incrementally as files
finish loading:

``` r

rv$files      # tibble: id, path, name, sample_group, include (logical),
              #          status, n_spectra, rt_range, mz_range, ms_levels, polarities
rv$msexp      # MsExperiment (on-disk), grows as files arrive
rv$eic_targets# tibble: label, mz, tol, unit, rt_min, rt_max, color, enabled
rv$selection  # last plotly_click: {plot, file_id, rt, mz} → drives spectrum
rv$filter     # current global filter state
rv$settings   # backend, palette, daemon count, default export size/dpi
```

Plots read only **included** files (`rv$files$include`) intersected with
the active filter.

## 5. File selection / inclusion

- File list (`DT` or `shinyWidgets`) shows each loaded file with a
  **checkbox to include/exclude** from plotting, plus status badge,
  n_spectra, rt/mz ranges, and an editable `sample_group`.
- “Select all / none / invert” controls.
- Excluded files stay loaded (cheap, on-disk) but are filtered out of
  every plot’s data source.
- `sample_group` drives ColorBrewer coloring in overlay plots.

## 6. Settings tab (`mod_settings`)

- **Spectra backend selector** — the key setting. Options to expose and
  let the user compare:
  - `MsBackendMzR` (default; on-disk, low RAM, re-reads from file)
  - `MsBackendMemory` / `setBackend(MsBackendMemory())` (fast re-plot,
    high RAM — good for small data)
  - `MsBackendSql` (SQLite-backed; scales to many files, persistent)
  - `MsBackendHdf5Peaks` (if available; on-disk peaks)
  - *Open question: which gives the best experience — benchmark on real
    data during build (§15).*
- Global **ColorBrewer palette** choice (qualitative for groups,
  sequential for heatmaps/3D).
- Default export size/format/DPI.
- `mirai` daemon count.
- Intensity-threshold / bin-size defaults for MS map & 3D.

## 7. Plot catalog (raw-capable, core)

| Tab | xcmsVis fn | Data path | Interactivity |
|----|----|----|----|
| **TIC / BPC** | `gplot(XcmsExperiment)` (BPI) + `chromatogram(aggregationFun="sum"/"max")` → `gplotChromatogramsOverlay` | per-file or overlay included files, color by `sample_group` (ColorBrewer) | hover, zoom; click→spectrum |
| **EIC (multi)** | `chromatogram(mz=matrix, rt=)` → `gplotChromatogramsOverlay` / `gplot` | EIC target table (§9) → mz matrix; one file or overlay | click point → spectrum at RT |
| **Spectrum** | custom ggplot (`geom_linerange`) | nearest scan to clicked RT | hover m/z/int; box-select → new EIC target |
| **MS map (2D)** | `gplot(XcmsExperiment)` MS-map half | binned rt×mz heatmap (ColorBrewer sequential), one file | zoom defines 3D window |
| **3D** | plotly (see §10) | binned/thresholded rt×mz×int | rotate, zoom |
| **Precursor ions** | `gplotPrecursorIons` | DDA MS2 precursors, per file | hover precursor m/z/RT |

**Gated extension (disabled, raw-only):** `gplotChromPeaks`,
`gplotChromPeakImage`, `ghighlightChromPeaks`, `gplotChromPeakDensity`,
`gplotFeatureGroups`, `gplotAdjustedRtime` — wired but disabled with
tooltip “requires Preprocess module” (§16).

## 8. Async ingestion (ExtendedTask + mirai)

`mirai::daemons(n)` in `global.R`. Per file (incremental list fill):

``` r

read_task <- ExtendedTask$new(function(path, backend) {
  mirai::mirai({
    sp <- Spectra::Spectra(path, source = backend)
    list(path = path,
         summary = list(n = length(sp),
                        rt = range(Spectra::rtime(sp)),
                        mz = range(unlist(Spectra::mz(sp))),
                        ms = unique(Spectra::msLevel(sp)),
                        pol = unique(Spectra::polarity(sp))))
  }, path = path, backend = backend)
})
```

- Header/summary read first → files appear fast; peak data stays
  on-disk, pulled lazily.
- Workers return **extracted data** (tibbles), not live on-disk
  `Spectra` handles (handles don’t always cross process boundaries
  cleanly — see §17).
- `read_task$status()` drives per-file spinner/badge.

## 9. EIC multi-m/z input (centerpiece UX)

Editable `DT` target table + a “paste list” `textAreaInput` that parses
into it:

    label    | mz       | tol | unit | rt_min | rt_max | color | ✓
    Caffeine | 195.0877 | 10  | ppm  | 60     | 240    | auto  | ☑

- Rows → mz range matrix `cbind(mz±tol)` for `chromatogram()`.
- Optional adduct/formula → m/z (reuse `commonMZ`/`rcdk` from mscurate
  if wanted).
- Enabled rows overlay in one `gplotChromatogramsOverlay`, colored per
  row via ColorBrewer; expose `stacked` offset and `transform=log1p`
  toggles (both already in the signature).

## 10. 3D plot — options

| Option | Verdict |
|----|----|
| plotly `scatter3d` (rt, mz, int points) | ✅ Default. Threshold intensity + cap points, operate only on zoomed window. |
| plotly `surface`/`mesh3d` (gridded rt×mz→int) | ✅ Optional “surface” mode; bin to regular grid; good for small window. |
| `rgl` / `rglwidget` | ⚠️ Skip v1 (heavy OpenGL). |

2D MS-map heatmap is always-on default; 3D opt-in on current zoom window
with points/surface toggle + intensity-threshold/bin-size controls.
Sequential ColorBrewer ramp.

## 11. Click → spectrum interaction

Reuse mscurate’s `event_data("plotly_click", source=...)` pattern: click
returns RT → nearest scan via `rtime()` → pull that `Spectra` element →
render `geom_linerange` spectrum in linked card. Box-select on spectrum
can feed a new EIC target back into §9.

## 12. Filtering layer (`mod_filter` + `fct_filters`)

Global sidebar filters composed into lazy `Spectra`/`xcms` calls:

| Filter              | Backend call                            |
|---------------------|-----------------------------------------|
| RT range            | `filterRt()`                            |
| m/z range           | `filterMzRange()` / `chromatogram(mz=)` |
| MS level            | `filterMsLevel()`                       |
| Polarity            | `filterPolarity()`                      |
| Intensity threshold | `filterIntensity()`                     |
| File/sample subset  | include checkboxes (§5)                 |

Plots inherit global filter; may set a local override (e.g. zoom window
for MS map).

## 13. Export system (`mod_export`)

The **ggplot is the source of truth**; plotly is only the on-screen
widget. Each module returns `plot_gg` (reactive ggplot) and renders
`ggplotly(plot_gg())`. “Save plot” modal: - Format: PNG / SVG / PDF -
Size: width, height, units (in/cm/mm/px) - PNG: DPI (72/150/300/600),
scaling - Backend:
`ggsave(file, plot_gg(), device=…, dpi=…, width=…, height=…)` -
Optional: export interactive HTML via
[`htmlwidgets::saveWidget`](https://rdrr.io/pkg/htmlwidgets/man/saveWidget.html).

## 14. File input / drag-and-drop

- Primary: `shinyFiles` picker → server-side paths, no upload, multi-GB
  safe.
- Drag-and-drop dropzone for convenience; browser DnD exposes contents
  not paths, so DnD’d files are temp-copied then read (fine for
  small/medium). Document the tradeoff in UI.

## 15. Testing — always on real data

Use xcmsVis’s own example datasets (verify availability of each during
build): - **faahKO** CDF (MS1):
`dir(system.file("cdf", package = "faahKO"), recursive = TRUE, full.names = TRUE)` -
**MsDataHub** DDA mzML for precursor ions:
`MsDataHub::PestMix1_DDA.mzML()` - **msdata** package mzML files as
additional real samples. - `readMsExperiment(spectraFiles = ...)` to
build the object. - Smoke tests: load → include/exclude → each plot
renders → export writes a valid file. - Benchmark the backend options
(§6) on faahKO to pick a sensible default.

## 16. DEFERRED — Preprocessing (saved for later, do NOT build now)

Out of current scope per user. Notes for a future `mod_preprocess`: -
Steps: `findChromPeaks` (CentWave/MatchedFilter params UI) →
`groupChromPeaks` (PeakDensity) → `adjustRtime` (Obiwarp/PeakGroups) →
`groupFeatures`. - Run async (ExtendedTask + mirai); store the processed
`XcmsExperiment` alongside raw. - Unlocks the six gated plots:
`gplotChromPeaks`, `gplotChromPeakImage`, `ghighlightChromPeaks` (peak
overlay on EICs), `gplotChromPeakDensity` (param tuning),
`gplotFeatureGroups`, `gplotAdjustedRtime` (alignment QC). - xcmsVis
already has working examples/vignettes for all six — copy their data
setup. - Param-tuning UX: `gplotChromPeakDensity` is ideal for
interactive `bw`/`minFraction` tuning. - Pre-processed-data import (load
an existing processed `XcmsExperiment`/`.rds`) also deferred.

## 17. Open questions / risks

- **xcmsVis is a local package** (not on CRAN/Bioc) — install from local
  git path; pin via `renv`. Confirm route.
- **`gplot(XcmsExperiment)` on raw data:** verify BPI/MS-map runs with
  NO `findChromPeaks`. If it hard-requires peaks, extract TIC/MS-map
  directly from `Spectra` and skip xcmsVis there.
- **`mirai` + on-disk `Spectra`:** workers must return extracted *data*,
  not live handles. (Plan assumes this.)
- **Best Spectra backend** is genuinely unknown — benchmark during build
  (§6, §15).

## 18. Phased roadmap

1.  Skeleton: `app.R`, `global.R`, bslib navbar, `mod_ingest`
    (shinyFiles + ExtendedTask/mirai), file list with include
    checkboxes + live status.
2.  Settings tab: backend selector, palette.
3.  Core viz: TIC/BPC + EIC target table + Spectrum (with click
    linkage).
4.  Filtering: global `mod_filter`.
5.  MS map + 3D.
6.  Precursor ions (DDA).
7.  Export modal.
8.  Polish: theming, drag-drop, caching, `testServer` + real-data smoke
    tests.
9.  *(Later, deferred §16)* Preprocess module → unlocks gated plots.
