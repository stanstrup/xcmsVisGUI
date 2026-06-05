# xcmsVisGUI

A local Shiny desktop app (packaged as an R package) for interactively visualising
**raw LC-MS data** on the RforMassSpectrometry stack (`Spectra` / `MsExperiment` /
`xcms`). Plots are ggplot2 rendered through plotly for interactivity (click, zoom,
hover); static export is via ggsave.

See [`PLAN.md`](PLAN.md) for the original design and [`ARCHITECTURE_REVIEW.md`](ARCHITECTURE_REVIEW.md)
for the current architecture.

## Status

Working: async file ingestion, settings (ColorBrewer/viridis palette, retention-time
unit, default EIC tolerance, export defaults — persisted across restarts), global
filters (rt / m/z / MS level / polarity / intensity / spectrum-id), and all raw-data
plot views — TIC/BPC, multi-EIC, click-to-spectrum (+ scan-list browser), 2D MS map,
3D (points/surface), and DDA precursor ions. Scope is **raw visualisation only** — no
peak picking / grouping / alignment (deferred; `PLAN.md` §16).

## Running

This is an R package; the app is the exported `run_app()`.

```r
# dev (from a clone, no install needed):
Rscript run.R                       # = pkgload::load_all() + run_app(launch.browser = TRUE)

# or installed:
xcmsVisGUI::run_app()
```

## Tests

```r
testthat::test_local(".")           # or: R CMD check
```

The suite covers the pure helpers and the key invariant that `apply_filters`
(MsExperiment) and `apply_filters_spectra` (Spectra) select the same spectra.
Real-data tests use the `msdata`/`faahKO` Bioconductor packages and skip if absent.
CI runs `R CMD check` on push/PR (`.github/workflows/R-CMD-check.yaml`).

## Dependencies & reproducibility (renv)

Dependencies are pinned with [`renv`](https://rstudio.github.io/renv/) (`renv.lock`),
with Bioconductor support configured. On a fresh clone:

```r
renv::restore()
```

`renv-setup.R` is a one-shot installer/snapshotter for first-time setup.

## Project layout

```
run.R                  # convenience launcher (load_all + run_app)
DESCRIPTION / NAMESPACE # package metadata; NAMESPACE is roxygen-generated
R/
  run_app.R            # app_ui() / app_server() + exported run_app()
  zzz.R                # .onLoad: register BiocParallel SerialParam (the perf fix)
  constants.R          # MS-file constants, palette names, rt-unit helpers
  daemons.R            # mirai daemon pool + per-run setup
  xcmsVisGUI-package.R # roxygen import declarations + globalVariables
  mod_ingest.R         # typed-path / choose.dir / fileInput + async mirai reader + file list
  mod_settings.R       # palette, rt unit, default tolerance, daemon count, export; persistence
  mod_filter.R         # global rt/mz/MS-level/polarity/intensity/spectrum-id filters
  mod_plot_tic_bpc.R   # TIC/BPC overlay, colour by group/sample, click->spectrum
  mod_plot_eic.R       # editable multi-m/z target table -> overlaid EICs
  mod_plot_spectrum.R  # spectrum at a clicked rt / picked scan + scan-list browser
  mod_plot_map.R       # 2D MS map + 3D points/surface (plotly-native)
  mod_plot_precursors.R# DDA precursor-ion map
  mod_export.R         # reusable png/svg/pdf export modal
  fct_extract.R        # data extraction (summaries, chromatograms, peaks, spectra)
  fct_filters.R        # compose filter state into Spectra/xcms calls
  fct_export.R         # ggsave-based export
  fct_palettes.R       # ColorBrewer / viridis helpers
  fct_settings_store.R # persist settings to the per-user config dir
  utils_reactive.R     # central reactive state (rv) + plotly/zoom helpers
tests/testthat/        # unit + real-data tests
```
