# Filter helpers for the global filter state.
# The actual filtering is applied inside the mzR compute_* functions
# (fct_extract.R) via filter_scans(); this file only derives slider bounds.

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
