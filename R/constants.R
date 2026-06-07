# Package constants and retention-time unit helpers (formerly in global.R).

# Recognised MS file types.
MS_FILE_EXTS  <- c("mzML", "mzXML", "CDF", "cdf", "mzml", "mzxml")
MS_FILE_REGEX <- "\\.(mzML|mzXML|CDF)$"

# Drop the MS file extension for display *in plots* (legends/facets/tooltips) —
# it's noise there and wastes horizontal space. The file list keeps the full
# name (extension distinguishes mzML/CDF and matches what's on disk).
strip_ext <- function(x) sub(MS_FILE_REGEX, "", x, ignore.case = TRUE)

# ColorBrewer qualitative palettes for groups/EIC traces, viridis/sequential for maps.
QUAL_PALETTES <- c("Set1", "Set2", "Set3", "Dark2", "Paired", "Accent",
                   "Pastel1", "Pastel2")
VIRIDIS_PALETTES <- c("viridis", "magma", "plasma", "inferno", "cividis",
                      "mako", "rocket", "turbo")
SEQ_PALETTES  <- c(VIRIDIS_PALETTES, "YlOrRd", "YlGnBu", "Blues", "Spectral")

# Mass spacing between the M+1 and M (13C - 12C) isotopologues, used to project
# isotope peaks in spectrum annotation. Divided by the charge for the observed
# m/z spacing. (Adduct mass offsets themselves come from commonMZ::MZ_CAMERA,
# whose massdiff already folds in the proton/electron mass.)
ISOTOPE_SPACING <- 1.0033548

# Default PER-STEP isotope m/z tolerance (Da): how far a peak may sit from the
# theoretical M+k position (k * 13C spacing / charge) and still count as an
# isotope. Real MS2 isotope centroids drift well beyond the tight adduct window
# and the error compounds with k, so the window scales as k * this. User-tunable
# via the annotation "Isotope tol" control.
ISO_TOL_DA <- 0.015

# --- Retention-time unit helpers ------------------------------------------
# Data is always handled internally in SECONDS (xcms/Spectra native). These
# convert to/from the user-facing display unit (minutes by default).
rt_factor     <- function(unit) if (identical(unit, "sec")) 1 else 60  # sec per display-unit
rt_to_disp    <- function(rt_sec, unit) rt_sec / rt_factor(unit)
rt_to_sec     <- function(rt_disp, unit) rt_disp * rt_factor(unit)
rt_axis_label <- function(unit) if (identical(unit, "sec")) "retention time (s)" else
  "retention time (min)"
