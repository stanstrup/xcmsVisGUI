# xcmsVisGUI

A local Shiny desktop app for interactively visualising **raw LC-MS data** on the
RforMassSpectrometry stack (`Spectra` / `MsExperiment` / `xcms`), with all plotting
delegated to [**xcmsVis**](https://github.com/stanstrup/xcmsVis) (ggplot → plotly).

See [`PLAN.md`](PLAN.md) for the full design.

## Status

Working: async file ingestion, settings (Spectra backend / ColorBrewer palette),
global filters (rt / m/z / MS level / polarity / intensity), and all raw-data plot
views — TIC/BPC, multi-EIC, click-to-spectrum, 2D MS map, 3D (points/surface), and
DDA precursor ions. Remaining: a unified export modal and the deferred preprocessing
module (`PLAN.md` §16, §18).

## Running

```r
# from the project directory
Rscript run.R
# or, in an R session:
shiny::runApp()
```

## Dependencies & reproducibility (renv)

Dependencies are pinned with [`renv`](https://rstudio.github.io/renv/). The lockfile
(`renv.lock`) records **xcmsVis from its GitHub repo** (`github::stanstrup/xcmsVis`),
so the environment restores identically on another machine.

**First boot is self-healing:** on a fresh clone, `global.R` detects an empty library
and runs `renv::restore()` automatically before the app starts. To restore manually:

```r
renv::restore()
```

Bioconductor support is configured in renv (release 3.21).

## Project layout

```
app.R            # bslib page_navbar shell, wires modules
global.R         # packages, mirai pool, palettes, first-boot renv restore
run.R            # convenience launcher
DESCRIPTION      # declared deps incl. Remotes: github::stanstrup/xcmsVis
R/
  mod_ingest.R         # shinyFiles picker + ExtendedTask/mirai async reader + file list
  mod_settings.R       # Spectra backend, palette, daemon count, export defaults
  mod_filter.R         # global rt/mz/MS-level/polarity/intensity filters
  mod_plot_tic_bpc.R   # TIC/BPC overlay, color by group/sample, click->spectrum
  mod_plot_eic.R       # editable multi-m/z target table -> overlaid EICs
  mod_plot_spectrum.R  # spectrum at the clicked retention time
  mod_plot_msmap.R     # 2D rt x m/z intensity heatmap
  mod_plot_3d.R        # 3D scatter / surface
  mod_plot_precursors.R# DDA precursor-ion map (xcmsVis::gplotPrecursorIons)
  fct_extract.R        # data extraction (summaries, chromatograms, peaks, spectra)
  fct_filters.R        # compose filter state into Spectra/xcms calls
  fct_export.R         # ggsave-based png/svg/pdf export
  fct_palettes.R       # ColorBrewer helpers
  utils_reactive.R     # central reactive state (rv)
```
