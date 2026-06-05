# global.R — sourced explicitly from app.R at startup (Shiny auto-loads R/ but
# not global.R for app.R-style apps).

# --- First-boot bootstrap -------------------------------------------------
# renv's .Rprofile has already activated the project library. If the packages
# aren't installed yet (fresh clone on another machine), restore them from the
# lockfile before anything tries to library() them.
if (requireNamespace("renv", quietly = TRUE) &&
    file.exists("renv.lock") &&
    !all(vapply(c("shiny", "xcms", "xcmsVis"),
                requireNamespace, logical(1), quietly = TRUE))) {
  message("xcmsVisGUI: restoring packages from renv.lock (first boot)…")
  renv::restore(prompt = FALSE)
}

# --- Packages -------------------------------------------------------------
library(shiny)
library(bslib)
library(mirai)
library(promises)
library(plotly)
library(DT)
library(htmlwidgets)
library(RColorBrewer)

library(magrittr)
library(dplyr)
library(tibble)
library(purrr)
library(rlang)

# The RforMassSpectrometry stack. xcms pulls in Spectra/MsExperiment.
suppressPackageStartupMessages({
  library(Spectra)
  library(MsExperiment)
  library(xcms)
  library(xcmsVis)
  library(BiocParallel)
})

# CRITICAL: register SerialParam. The default BiocParallel backend (SnowParam on
# Windows) makes MsBackendMzR reads ~100x slower by spawning a socket cluster per
# call — see BENCHMARK.md / SPECTRA_ISSUE.md. SerialParam makes reads sub-second.
register(SerialParam())

# --- Async backend (mirai) ------------------------------------------------
# Daemons power the ExtendedTask file readers. Count is overridable from the
# Settings tab via set_daemons(); we seed a sensible default here.
.default_daemons <- max(1L, parallel::detectCores() - 1L)

set_daemons <- function(n = .default_daemons) {
  n <- max(1L, as.integer(n))
  mirai::daemons(0)        # reset any existing pool
  mirai::daemons(n)
  n
}

# Establish the initial pool. everywhere() ships the packages a worker needs
# to read a file so the mirai expressions don't have to library() each time.
set_daemons()
# Workers only read file-header summaries via mzR (read_ms_header) — fast and
# free of BiocParallel. Heavy plotting/filtering happens in the main process via
# Spectra/xcms under SerialParam.
mirai::everywhere(suppressPackageStartupMessages(library(mzR)))

# Tidy up the pool when the R session ends.
onStop(function() try(mirai::daemons(0), silent = TRUE))

# Allow large drag-and-drop uploads (mzML files are tens of MB).
options(shiny.maxRequestSize = 5 * 1024^3)

# --- Constants ------------------------------------------------------------
MS_FILE_EXTS <- c("mzML", "mzXML", "CDF", "cdf", "mzml", "mzxml")
MS_FILE_REGEX <- "\\.(mzML|mzXML|CDF)$"

# ColorBrewer qualitative palettes for groups/EIC traces, sequential for maps.
QUAL_PALETTES <- c("Set1", "Set2", "Set3", "Dark2", "Paired", "Accent",
                   "Pastel1", "Pastel2")
VIRIDIS_PALETTES <- c("viridis", "magma", "plasma", "inferno", "cividis",
                      "mako", "rocket", "turbo")
SEQ_PALETTES  <- c(VIRIDIS_PALETTES, "YlOrRd", "YlGnBu", "Blues", "Spectral")

# --- Retention-time unit helpers ------------------------------------------
# Data is always handled internally in SECONDS (xcms/Spectra native). These
# convert to/from the user-facing display unit (minutes by default).
rt_factor <- function(unit) if (identical(unit, "sec")) 1 else 60   # sec per display-unit
rt_to_disp <- function(rt_sec, unit) rt_sec / rt_factor(unit)
rt_to_sec  <- function(rt_disp, unit) rt_disp * rt_factor(unit)
rt_axis_label <- function(unit) if (identical(unit, "sec")) "retention time (s)" else
  "retention time (min)"
