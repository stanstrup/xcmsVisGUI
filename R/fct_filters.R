# Compose the global filter state into Spectra/xcms filter calls.
# rt / m/z / MS level filter directly on MsExperiment; polarity and intensity
# go through filterSpectra() (no direct MsExperiment method).

#' Apply the global filter list `f` (rv$filter) to an MsExperiment.
apply_filters <- function(x, f) {
  if (!is.null(f$ms_level) && is.finite(f$ms_level))
    x <- xcms::filterMsLevel(x, as.integer(f$ms_level))
  if (isTRUE(is.finite(f$rt_min) || is.finite(f$rt_max))) {
    rt <- c(if (is.finite(f$rt_min)) f$rt_min else -Inf,
            if (is.finite(f$rt_max)) f$rt_max else  Inf)
    x <- xcms::filterRt(x, rt = rt)
  }
  if (isTRUE(is.finite(f$mz_min) || is.finite(f$mz_max))) {
    mz <- c(if (is.finite(f$mz_min)) f$mz_min else 0,
            if (is.finite(f$mz_max)) f$mz_max else Inf)
    x <- Spectra::filterMzRange(x, mz = mz)
  }
  if (!is.null(f$polarity) && !identical(f$polarity, "any")) {
    pol <- if (identical(f$polarity, "pos")) 1L else 0L
    x <- MsExperiment::filterSpectra(x, Spectra::filterPolarity, polarity = pol)
  }
  has_imin <- !is.null(f$int_min) && is.finite(f$int_min) && f$int_min > 0
  has_imax <- !is.null(f$int_max) && is.finite(f$int_max)
  if (has_imin || has_imax)
    x <- MsExperiment::filterSpectra(x, Spectra::filterIntensity,
                                     intensity = c(if (has_imin) f$int_min else 0,
                                                   if (has_imax) f$int_max else Inf))
  x
}

#' Combined data ranges across the included files (for slider bounds).
#' @param files_df included rows of rv$files (status "ready").
combined_ranges <- function(files_df) {
  rng <- function(lo, hi) {
    lo <- suppressWarnings(min(lo, na.rm = TRUE))
    hi <- suppressWarnings(max(hi, na.rm = TRUE))
    if (!is.finite(lo) || !is.finite(hi)) NULL else c(lo, hi)
  }
  split_vals <- function(x) {
    x <- as.character(x)
    x <- x[!is.na(x) & nzchar(x)]
    unique(unlist(strsplit(x, ",\\s*")))
  }
  ms  <- split_vals(files_df$ms_levels)
  pol <- split_vals(files_df$polarities)
  list(
    rt = rng(files_df$rt_min, files_df$rt_max),
    mz = rng(files_df$mz_min, files_df$mz_max),
    ms_levels  = sort(ms),
    polarities = setdiff(pol, c("", NA))
  )
}
