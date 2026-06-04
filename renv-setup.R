# One-shot dependency install for the renv library, then snapshot.
# Run with the project's R (renv auto-activates via .Rprofile).
# xcmsVis is pulled from GitHub so the lockfile records the remote and
# is restorable on another machine.

options(
  renv.config.pak.enabled = FALSE,
  Ncpus = max(1L, parallel::detectCores() - 1L)
)

# CRAN packages: app framework, async, UI, plotting, data wrangling.
cran_pkgs <- c(
  "shiny", "bslib", "mirai", "promises",
  "shinyFiles", "shinyWidgets", "shinyjs",
  "plotly", "DT", "htmlwidgets",
  "RColorBrewer",
  "dplyr", "tibble", "tidyr", "purrr", "magrittr", "rlang", "fs", "stringr"
)

# Bioconductor packages: the RforMassSpectrometry stack + real test data.
bioc_pkgs <- paste0("bioc::", c(
  "Spectra", "MsExperiment", "xcms", "MsCoreUtils", "ProtGenerics",
  "MsDataHub", "msdata", "faahKO"
))

# xcmsVis from GitHub -> lockfile records the github remote (restorable elsewhere).
github_pkgs <- "github::stanstrup/xcmsVis"

renv::install(c(cran_pkgs, bioc_pkgs, github_pkgs), prompt = FALSE)

# Snapshot everything actually used into renv.lock.
renv::snapshot(prompt = FALSE)

cat("\n=== renv setup complete ===\n")
