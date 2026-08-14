# Developer guide

This page collects the contributor-facing details. For the design
rationale and decision log, see
[`ARCHITECTURE_REVIEW.md`](https://github.com/stanstrup/xcmsVisGUI/blob/main/ARCHITECTURE_REVIEW.md)
in the repository.

## Status

Working: async file ingestion; settings (ColorBrewer/viridis palette,
retention-time unit, default EIC tolerance, export defaults — persisted
across restarts); global filters (rt / *m/z* / MS level / polarity /
intensity / repeatable spectrum-id rules); per-view profile-mode peak
picking
([`Spectra::pickPeaks`](https://rdrr.io/pkg/Spectra/man/addProcessing.html),
with S/N / half-window / m/z-refinement); and all raw-data plot views —
TIC/BPC, multi-EIC (with intensity scaling), click-to-spectrum (+
scan-list browser), 2D MS map, 3D points/surface, and DDA precursor
ions. The Spectrum view also does single-spectrum adduct / isotope /
in-source-fragment annotation (manual anchor, findMAIN auto-suggest,
difference network, and formula-based fine isotope patterns via Rdisop +
enviPat).

Scope is **raw visualisation** — profile scans are centroided on the fly
for display/annotation, but there is no cross-sample peak picking /
feature grouping / retention-time alignment (deferred; see the
architecture doc).

Extraction results are cached to disk (qs2), so re-opening the app with
the same files + filter is instant. Figures export as png/svg/pdf, or as
the raw ggplot object (`.rds`) for later tweaking in R.

## Run from a clone

This is an R package; the app is the exported
[`run_app()`](https://stanstrup.github.io/xcmsVisGUI/reference/run_app.md).
From a fresh clone, install the dependencies once into your normal R
library, then launch:

``` r

# install the dependencies (Imports + Suggests + the commonMZ GitHub remote):
# install.packages(c("remotes", "BiocManager"))
# options(repos = BiocManager::repositories())   # so the Bioconductor deps resolve
# remotes::install_deps(dependencies = TRUE)

# then launch from source (load_all live-reloads your edits):
# Rscript run.R           # = pkgload::load_all() + run_app(launch.browser = TRUE)
```

`BiocManager` is needed so the Bioconductor dependencies (Spectra, xcms,
mzR, …) resolve; `remotes` follows the `Remotes:` field to install
`commonMZ` from GitHub. There’s no renv to set up — `DESCRIPTION` is the
single source of truth for dependencies (the same way users install the
package, and the same way CI provisions via
`r-lib/actions/setup-r-dependencies`).

## Tests

``` r

# testthat::test_local(".")   # or: R CMD check
```

The suite covers the pure helpers and the key invariant that
`apply_filters` (MsExperiment) and `apply_filters_spectra` (Spectra)
select the same spectra. Real-data tests use the `msdata` / `faahKO`
Bioconductor packages and skip if absent. CI runs `R CMD check` on
push/PR (`.github/workflows/R-CMD-check.yaml`).

## Regenerating the documentation figures

The figures are captured headlessly with
[`chromote`](https://rstudio.github.io/chromote/) against a running app.
Start the app on port 7799, then run a capture script in a second
process:

``` r

# terminal 1 — serve the app on the port the scripts expect:
# Rscript -e "pkgload::load_all('.'); run_app(port = 7799, launch.browser = FALSE)"

# terminal 2 — full-UI PNG screenshots (sidebar + plot) at 1440x900:
# Rscript data-raw/capture-screenshots.R      # -> vignettes/articles/figures/*.png

# ...or crisp vector SVGs of the PLOT only (no sidebar):
# Rscript data-raw/capture-plots-svg.R        # -> vignettes/articles/figures/svg/*.svg
```

Two scripts because Chrome’s screenshot is **raster only** — good for
the full UI, but not vector. For SVG, `capture-plots-svg.R` calls
plotly’s own `Plotly.toImage(format = "svg")` on each plot’s graph div,
which is true vector for the line/scatter plots (TIC, EIC, spectra,
precursors). The 2-D MS map draws with scattergl (WebGL) for speed, so
its “SVG” embeds a raster image for the points — use the PNG for that
one, or export from a non-gl view. Both scripts include files by driving
the DataTable Shiny binding directly
(`$('#..').data('datatable') .shinyMethods.selectRows`), since a
synthetic click on the All button doesn’t fire under chromote.

The formula-based isotope-pattern overlay (`isotope.png`) is captured
too. Driving that mode headlessly needs two things the script handles:
the `conditionalPanel` annotation widgets don’t transmit their values
until interacted with, so the script sets them explicitly with
`Shiny.setInputValue(..., {priority: "event"})`; and the
candidate-formula table renders client-side and computes even while
hidden (see `suspendWhenHidden = FALSE` on `iso_cands` in
`mod_plot_spectrum.R`), so it is populated by the time the shot is
taken. The plot is zoomed to the anchor’s isotope cluster **last**
(after the inputs settle) so no pending re-render resets the range.

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
      fct_filters.R        # compose filter state into Spectra/xcms calls; profile peak-picking
      fct_annotate.R       # the single-spectrum annotation engine (pure, testable)
      fct_isotope.R        # fine isotope-pattern engine: Rdisop formulas + enviPat envelope
      fct_export.R         # ggsave-based export (+ rds = the ggplot object itself)
      fct_palettes.R       # ColorBrewer / viridis helpers
      fct_cache.R          # layered mem+disk (qs2) cache backing bindCache, persistent across restarts
      fct_settings_store.R # persist settings to the per-user config dir
      utils_reactive.R     # central reactive state (rv) + plotly/zoom + peak-picking UI helpers
    tests/testthat/        # unit + real-data tests
    data-raw/              # throwaway scripts, incl. capture-screenshots.R (chromote)
