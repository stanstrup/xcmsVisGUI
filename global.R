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
library(shinyFiles)
library(shinyWidgets)
library(shinyjs)
library(plotly)
library(DT)
library(htmlwidgets)
library(RColorBrewer)

library(magrittr)
library(dplyr)
library(tibble)
library(tidyr)
library(purrr)
library(rlang)
library(stringr)
library(fs)

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

# --- Constants ------------------------------------------------------------
MS_FILE_EXTS <- c("mzML", "mzXML", "CDF", "cdf", "mzml", "mzxml")

# ColorBrewer qualitative palettes for groups/EIC traces, sequential for maps.
QUAL_PALETTES <- c("Set1", "Set2", "Dark2", "Paired", "Accent")
SEQ_PALETTES  <- c("YlOrRd", "Viridis-like (YlGnBu)" = "YlGnBu", "Blues", "Spectral")
