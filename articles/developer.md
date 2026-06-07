# Developer guide

This page collects the contributor-facing details. For the design
rationale and decision log, see
[`ARCHITECTURE_REVIEW.md`](https://github.com/stanstrup/xcmsVisGUI/blob/main/ARCHITECTURE_REVIEW.md)
in the repository.

## Status

Working: async file ingestion; settings (ColorBrewer/viridis palette,
retention-time unit, default EIC tolerance, export defaults — persisted
across restarts); global filters (rt / *m/z* / MS level / polarity /
intensity / repeatable spectrum-id rules); and all raw-data plot views —
TIC/BPC, multi-EIC, click-to-spectrum (+ scan-list browser), 2D MS map,
3D points/surface, and DDA precursor ions. The Spectrum view also does
single-spectrum adduct / isotope / in-source-fragment annotation (manual
anchor, findMAIN auto-suggest, or difference network).

Scope is **raw visualisation only** — no peak picking / grouping /
alignment (deferred; see the architecture doc).

Extraction results are cached to disk (qs2), so re-opening the app with
the same files + filter is instant. Figures export as png/svg/pdf, or as
the raw ggplot object (`.rds`) for later tweaking in R.

## Run from a clone

This is an R package; the app is the exported
[`run_app()`](https://stanstrup.github.io/xcmsVisGUI/reference/run_app.md).

``` r

# dev (from a clone, no install needed):
# Rscript run.R           # = pkgload::load_all() + run_app(launch.browser = TRUE)

# or installed:
xcmsVisGUI::run_app()
```

## Tests

``` r

# testthat::test_local(".")   # or: R CMD check
```

The suite covers the pure helpers and the key invariant that
`apply_filters` (MsExperiment) and `apply_filters_spectra` (Spectra)
select the same spectra. Real-data tests use the `msdata` / `faahKO`
Bioconductor packages and skip if absent. CI runs `R CMD check` on
push/PR (`.github/workflows/R-CMD-check.yaml`).

## Dependencies & reproducibility (renv)

Dependencies are pinned with [`renv`](https://rstudio.github.io/renv/)
(`renv.lock`), with Bioconductor support configured. On a fresh clone:

``` r

# renv::restore()
```

`renv-setup.R` is a one-shot installer/snapshotter for first-time setup.

## Regenerating the documentation screenshots

The article screenshots are captured headlessly with
[`chromote`](https://rstudio.github.io/chromote/) against a running app
(`run_app(port = 7799)`):

``` r

# source("renv/activate.R")
# source("tools/shoot.R")                              # TIC + Filters (faahKO)
# source("tools/shoot_annot.R")  # args: <mzML-path> <scan>  -> annotation.png
```

They are saved at 1440x900 into `vignettes/articles/figures/`.

## Project layout

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
      mod_filter.R         # global rt/mz/MS-level/polarity/intensity + spectrum-id rules
      mod_plot_tic_bpc.R   # TIC/BPC overlay, colour by group/sample, click->spectrum
      mod_plot_eic.R       # editable multi-m/z target table -> overlaid EICs
      mod_plot_spectrum.R  # spectrum at a clicked rt / picked scan + scan-list browser + annotation
      mod_plot_map.R       # 2D MS map + 3D points/surface (plotly-native)
      mod_plot_precursors.R# DDA precursor-ion map
      mod_export.R         # reusable png/svg/pdf/rds export modal
      fct_extract.R        # data extraction (summaries, chromatograms, peaks, spectra)
      fct_filters.R        # compose filter state into Spectra/xcms calls
      fct_annotate.R       # the single-spectrum annotation engine (pure, testable)
      fct_export.R         # ggsave-based export (+ rds = the ggplot object itself)
      fct_palettes.R       # ColorBrewer / viridis helpers
      fct_cache.R          # layered mem+disk (qs2) cache backing bindCache, persistent across restarts
      fct_settings_store.R # persist settings to the per-user config dir
      utils_reactive.R     # central reactive state (rv) + plotly/zoom helpers
    tests/testthat/        # unit + real-data tests
    tools/                 # screenshot-capture scripts (chromote)
