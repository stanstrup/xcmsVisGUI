# Compose the global filter state into Spectra/xcms filter calls.
#
# Two entry points so single-file views (spectrum, MS map) get the SAME filters
# as the multi-file chromatogram views:
#   apply_filters         -> MsExperiment (TIC/BPC/EIC via chromatogram)
#   apply_filters_spectra -> Spectra      (spectrum, peak map)

# Does the filter ask to constrain m/z?  (intensity handled separately)
.flt_mz <- function(f) c(if (is.finite(f$mz_min)) f$mz_min else 0,
                         if (is.finite(f$mz_max)) f$mz_max else Inf)
.flt_int <- function(f) {
  has_min <- !is.null(f$int_min) && is.finite(f$int_min) && f$int_min > 0
  has_max <- !is.null(f$int_max) && is.finite(f$int_max)
  if (!has_min && !has_max) return(NULL)
  c(if (has_min) f$int_min else 0, if (has_max) f$int_max else Inf)
}

#' Apply the global filter `f` to an MsExperiment.
apply_filters <- function(x, f) {
  if (!is.null(f$ms_level) && is.finite(f$ms_level))
    x <- xcms::filterMsLevel(x, as.integer(f$ms_level))
  if (isTRUE(is.finite(f$rt_min) || is.finite(f$rt_max)))
    x <- xcms::filterRt(x, rt = c(if (is.finite(f$rt_min)) f$rt_min else -Inf,
                                  if (is.finite(f$rt_max)) f$rt_max else Inf))
  if (isTRUE(is.finite(f$mz_min) || is.finite(f$mz_max)))
    x <- Spectra::filterMzRange(x, mz = .flt_mz(f))
  if (!is.null(f$polarity) && !identical(f$polarity, "any"))
    x <- MsExperiment::filterSpectra(x, Spectra::filterPolarity,
                                     polarity = if (identical(f$polarity, "pos")) 1L else 0L)
  ii <- .flt_int(f)
  if (!is.null(ii))
    x <- MsExperiment::filterSpectra(x, Spectra::filterIntensity, intensity = ii)
  if (!is.null(f$charge) && is.finite(f$charge))
    x <- MsExperiment::filterSpectra(x, Spectra::filterPrecursorCharge,
                                     z = as.integer(f$charge))
  if (!is.null(f$spectrum_id) && nzchar(f$spectrum_id))
    x <- MsExperiment::filterSpectra(x, .filter_spectrumid, pat = f$spectrum_id)
  x
}

#' Apply the global filter `f` to a Spectra object.
apply_filters_spectra <- function(sp, f) {
  if (!is.null(f$ms_level) && is.finite(f$ms_level))
    sp <- Spectra::filterMsLevel(sp, as.integer(f$ms_level))
  if (isTRUE(is.finite(f$rt_min) || is.finite(f$rt_max)))
    sp <- Spectra::filterRt(sp, rt = c(if (is.finite(f$rt_min)) f$rt_min else -Inf,
                                       if (is.finite(f$rt_max)) f$rt_max else Inf))
  if (isTRUE(is.finite(f$mz_min) || is.finite(f$mz_max)))
    sp <- Spectra::filterMzRange(sp, mz = .flt_mz(f))
  if (!is.null(f$polarity) && !identical(f$polarity, "any"))
    sp <- Spectra::filterPolarity(sp, if (identical(f$polarity, "pos")) 1L else 0L)
  ii <- .flt_int(f)
  if (!is.null(ii)) sp <- Spectra::filterIntensity(sp, intensity = ii)
  if (!is.null(f$charge) && is.finite(f$charge))
    sp <- Spectra::filterPrecursorCharge(sp, z = as.integer(f$charge))
  if (!is.null(f$spectrum_id) && nzchar(f$spectrum_id))
    sp <- .filter_spectrumid(sp, f$spectrum_id)
  sp
}

# Keep spectra whose spectrumId matches a (fixed-string) pattern, e.g.
# "function=1 process=0 scan=7". Used for Waters-style function/scanEvent subset.
.filter_spectrumid <- function(sp, pat) {
  ids <- tryCatch(sp$spectrumId, error = function(e) NULL)
  if (is.null(ids)) return(sp)
  sp[grepl(pat, ids, fixed = TRUE)]
}

#' Combined data ranges across the included files (for input hints).
combined_ranges <- function(files_df) {
  rng <- function(lo, hi) {
    lo <- suppressWarnings(min(lo, na.rm = TRUE))
    hi <- suppressWarnings(max(hi, na.rm = TRUE))
    if (!is.finite(lo) || !is.finite(hi)) NULL else c(lo, hi)
  }
  split_vals <- function(x) {
    x <- as.character(x); x <- x[!is.na(x) & nzchar(x)]
    unique(unlist(strsplit(x, ",\\s*")))
  }
  list(
    rt = rng(files_df$rt_min, files_df$rt_max),
    mz = rng(files_df$mz_min, files_df$mz_max),
    ms_levels  = sort(split_vals(files_df$ms_levels)),
    polarities = setdiff(split_vals(files_df$polarities), c("", NA))
  )
}
