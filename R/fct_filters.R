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

#' The global filter as a default list — the single source of truth for its
#' shape. Used by make_rv() (initial state) and as the base make_filter() fills.
#' ms_level defaults to 1 (MS1) at startup; everything else is unconstrained.
#' `centroid` is the profile-mode policy — see should_centroid().
#' @noRd
empty_filter <- function() {
  list(rt_min = NA_real_, rt_max = NA_real_,
       mz_min = NA_real_, mz_max = NA_real_,
       ms_level = 1L, polarity = "any",
       int_min = NA_real_, int_max = NA_real_,
       centroid = "auto",
       spectrum_id_rules = list())
}

#' Build a filter list from the mod_filter UI inputs. rt inputs are in `unit`
#' (display) and stored in seconds; blank/non-finite numerics become NA (no
#' constraint); ms_level "all"/blank -> NA. Keeps the input->filter coercion in
#' one place so adding a field touches the schema and the appliers only.
#' @noRd
make_filter <- function(inputs, unit) {
  num <- function(v) if (is.null(v) || !is.finite(v)) NA_real_ else v
  f <- empty_filter()
  f$rt_min  <- rt_to_sec(num(inputs$rt_min), unit)
  f$rt_max  <- rt_to_sec(num(inputs$rt_max), unit)
  f$mz_min  <- num(inputs$mz_min);  f$mz_max  <- num(inputs$mz_max)
  f$int_min <- num(inputs$int_min); f$int_max <- num(inputs$int_max)
  f$ms_level <- if (is.null(inputs$ms_level) || identical(inputs$ms_level, "all"))
                  NA_integer_ else as.integer(inputs$ms_level)
  f$polarity <- if (!is.null(inputs$polarity)) inputs$polarity else "any"
  f$centroid <- inputs$centroid %||% "auto"
  f$spectrum_id_rules <- inputs$spectrum_id_rules %||% list()
  f
}

#' Effective MS level for chromatogram extraction (TIC/BPC/EIC): the filter's
#' ms_level when set, else 1 — chromatograms default to MS1. Keeps that default
#' in one place instead of inline in each chromatogram view.
#' @noRd
chrom_ms_level <- function(f) {
  if (!is.null(f$ms_level) && is.finite(f$ms_level)) as.integer(f$ms_level) else 1L
}

# --- profile mode ------------------------------------------------------------
# Profile spectra carry every detector sample, so one Orbitrap MS1 scan is ~17k
# points where its centroid list is ~1k. Left raw, the spectrum view draws a
# stick per sample and the MS map reads ~29M points (460 MB) per file. The fix is
# Spectra::pickPeaks() — a LAZY processing step, applied when peaks are read, so
# nothing is materialised until a view actually asks for the data.

#' Which MS levels of `sp` hold PROFILE spectra (integer(0) = none).
#'
#' Resolved per MS LEVEL, not per file, because mixed files are common: a Thermo
#' DDA run is routinely profile MS1 + centroided MS2. Peak-picking such a file
#' wholesale would run pickPeaks over the already-centroided MS2 spectra, and
#' local-maximum detection on a centroid list DISCARDS every peak whose
#' neighbour is more intense — it would quietly gut the MS2 spectra. So we hand
#' the profile levels to pickPeaks(msLevel.=) and it leaves the rest alone.
#'
#' Source of truth is the file's own `centroided` flag (mzML records it per
#' spectrum; mzR and Spectra both surface it). When nothing is declared (CDF,
#' some writers) fall back to Spectra's peak-shape heuristic on a spread of
#' spectra, and treat the file as all-profile or all-centroid on that verdict.
#' Undecidable means centroided — never peak-pick on a guess.
#' @noRd
profile_ms_levels <- function(sp) {
  if (!length(sp)) return(integer(0))
  lev <- Spectra::msLevel(sp)
  cen <- tryCatch(Spectra::centroided(sp),
                  error = function(e) rep(NA, length(sp)))
  if (any(!is.na(cen)))
    return(sort(unique(lev[!is.na(cen) & !cen])))
  idx <- unique(round(seq(1, length(sp), length.out = min(5L, length(sp)))))
  h <- tryCatch(Spectra::isCentroided(sp[idx]), error = function(e) NA)
  h <- h[!is.na(h)]
  if (!length(h) || all(h)) return(integer(0))
  sort(unique(lev))
}

#' Are any of these spectra profile-mode? (Used by the spectrum view to decide
#' between a continuous trace and m/z sticks.)
#' @noRd
is_profile_spectra <- function(sp) length(profile_ms_levels(sp)) > 0

#' The MS levels to peak-pick under the filter's `centroid` policy:
#'   "auto" (default) — the levels detected as profile
#'   "on"             — every level present (force peak picking)
#'   "off"            — none (show the raw profile trace)
#' @noRd
centroid_ms_levels <- function(sp, f) {
  mode <- f$centroid %||% "auto"
  if (identical(mode, "off") || !length(sp)) return(integer(0))
  if (identical(mode, "on")) return(sort(unique(Spectra::msLevel(sp))))
  profile_ms_levels(sp)
}

#' Apply the global filter `f` to an MsExperiment (TIC/BPC/EIC).
#'
#' Deliberately does NOT centroid, even on profile data: a chromatogram sums (or
#' maxes) intensities across an m/z window, which is correct on profile samples
#' and matches the TIC the instrument wrote. Peak-picking first would change the
#' reported intensities for no benefit. Centroiding is a spectrum-level concern —
#' see apply_filters_spectra().
#' @noRd
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
  if (has_id_rules(f))
    x <- MsExperiment::filterSpectra(x, .filter_spectrumid, rules = f$spectrum_id_rules)
  x
}

#' Apply the global filter `f` to a Spectra object (spectrum view, MS map).
#'
#' Ordered in two stages. The SPECTRUM-level filters (ms level, rt, polarity,
#' spectrum id) run first — they only subset spectra, so they make everything
#' after them cheaper. Centroiding then runs on the raw profile trace, and only
#' then do the PEAK-level filters (m/z range, intensity) apply, to the centroids.
#' That order matters: an intensity floor applied to profile samples would clip
#' the flanks off every peak before pickPeaks saw its shape. The peak-level
#' filters commute with each other, so already-centroided files see no change.
#'
#' `Spectra::` qualification on pickPeaks is REQUIRED, not style: attaching xcms
#' pulls in an MSnbase `pickPeaks` generic that masks ProtGenerics', and an
#' unqualified call then fails to dispatch on a Spectra object.
#' @noRd
apply_filters_spectra <- function(sp, f) {
  if (!is.null(f$ms_level) && is.finite(f$ms_level))
    sp <- Spectra::filterMsLevel(sp, as.integer(f$ms_level))
  if (isTRUE(is.finite(f$rt_min) || is.finite(f$rt_max)))
    sp <- Spectra::filterRt(sp, rt = c(if (is.finite(f$rt_min)) f$rt_min else -Inf,
                                       if (is.finite(f$rt_max)) f$rt_max else Inf))
  if (!is.null(f$polarity) && !identical(f$polarity, "any"))
    sp <- Spectra::filterPolarity(sp, if (identical(f$polarity, "pos")) 1L else 0L)
  if (has_id_rules(f))
    sp <- .filter_spectrumid(sp, f$spectrum_id_rules)

  lv <- centroid_ms_levels(sp, f)
  if (length(lv)) sp <- Spectra::pickPeaks(sp, msLevel. = lv)

  if (isTRUE(is.finite(f$mz_min) || is.finite(f$mz_max)))
    sp <- Spectra::filterMzRange(sp, mz = .flt_mz(f))
  ii <- .flt_int(f)
  if (!is.null(ii)) sp <- Spectra::filterIntensity(sp, intensity = ii)
  sp
}

# Does the filter carry any spectrum-ID rule with a non-empty term?
has_id_rules <- function(f) {
  rules <- f$spectrum_id_rules %||% list()
  any(vapply(rules, function(r) nzchar(r$text %||% ""), logical(1)))
}

# Keep spectra by their spectrumId against a list of rules (each
# list(mode = "contains"|"exclude", text = ...)), e.g. require "function=1" and
# exclude "process=0". Used for Waters-style function/scanEvent subsetting.
.filter_spectrumid <- function(sp, rules) {
  ids <- tryCatch(sp$spectrumId, error = function(e) NULL)
  if (is.null(ids)) return(sp)
  sp[match_spectrum_id_rules(ids, rules)]
}

#' Logical keep-mask for spectrum ids given a list of rules. Empty-term rules are
#' ignored; "contains" rules are ANDed (the id must contain the fixed term) and
#' "exclude" rules require the term to be absent. No effective rule keeps all.
#' Pure (no Spectra dependency) so it can be unit-tested directly.
#' @noRd
match_spectrum_id_rules <- function(ids, rules) {
  keep <- rep(TRUE, length(ids))
  for (rule in rules) {
    txt <- rule$text %||% ""
    if (!nzchar(txt)) next
    hit <- grepl(txt, ids, fixed = TRUE)
    keep <- keep & if (identical(rule$mode, "exclude")) !hit else hit
  }
  keep
}

#' Combined data ranges across the included files (for input hints).
#' @noRd
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
    polarities = setdiff(split_vals(files_df$polarities), c("", NA)),
    charges    = sort(as.integer(split_vals(files_df$charges)))
  )
}
