# Package constants and retention-time unit helpers (formerly in global.R).

# Recognised MS file types.
MS_FILE_EXTS  <- c("mzML", "mzXML", "CDF", "cdf", "mzml", "mzxml")
MS_FILE_REGEX <- "\\.(mzML|mzXML|CDF)$"

# ColorBrewer qualitative palettes for groups/EIC traces, viridis/sequential for maps.
QUAL_PALETTES <- c("Set1", "Set2", "Set3", "Dark2", "Paired", "Accent",
                   "Pastel1", "Pastel2")
VIRIDIS_PALETTES <- c("viridis", "magma", "plasma", "inferno", "cividis",
                      "mako", "rocket", "turbo")
SEQ_PALETTES  <- c(VIRIDIS_PALETTES, "YlOrRd", "YlGnBu", "Blues", "Spectral")

# --- Retention-time unit helpers ------------------------------------------
# Data is always handled internally in SECONDS (xcms/Spectra native). These
# convert to/from the user-facing display unit (minutes by default).
rt_factor     <- function(unit) if (identical(unit, "sec")) 1 else 60  # sec per display-unit
rt_to_disp    <- function(rt_sec, unit) rt_sec / rt_factor(unit)
rt_to_sec     <- function(rt_disp, unit) rt_disp * rt_factor(unit)
rt_axis_label <- function(unit) if (identical(unit, "sec")) "retention time (s)" else
  "retention time (min)"
