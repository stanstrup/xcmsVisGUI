# Fast data layer built directly on mzR.
#
# Benchmark on real 30 MB centroided mzML files showed the bottleneck is NOT
# disk or mzR (openMSfile + header + peaks = ~0.6 s) but Spectra's
# MsBackendMzR initialization (~84 s) and xcms::chromatogram() (~93 s). So we
# bypass Spectra/MsExperiment entirely: read each file once with mzR, cache the
# header + peak list in memory, and compute every plot from that (manual EIC per
# xcms issue #809). Repeat operations are then sub-second.

# --- Per-file in-memory cache --------------------------------------------
.ms_cache <- new.env(parent = emptyenv())
ms_cache_cap <- 60L   # ~ files kept in RAM (≈35-70 MB each); oldest evicted

#' Read one file via mzR into a compact structure (header vectors + peak list).
read_ms_data <- function(path) {
  x <- mzR::openMSfile(path)
  on.exit(mzR::close(x))
  h <- mzR::header(x)
  pks <- mzR::peaks(x)
  if (!is.list(pks)) pks <- list(pks)        # single-spectrum files
  list(
    rt          = h$retentionTime,
    msLevel     = h$msLevel,
    polarity    = h$polarity,
    tic         = h$totIonCurrent,
    bpi         = h$basePeakIntensity,
    bpmz        = h$basePeakMZ,
    precursorMZ = h$precursorMZ,
    peaks       = pks
  )
}

#' Cached accessor. Reads + caches on first use; evicts oldest beyond the cap.
get_ms_data <- function(path) {
  key <- normalizePath(path, winslash = "/", mustWork = FALSE)
  hit <- get0(key, envir = .ms_cache, inherits = FALSE)
  if (!is.null(hit)) return(hit)
  d <- read_ms_data(path)
  assign(key, d, envir = .ms_cache)
  ks <- ls(.ms_cache)
  if (length(ks) > ms_cache_cap) rm(list = ks[1], envir = .ms_cache)
  d
}

clear_ms_cache <- function() rm(list = ls(.ms_cache), envir = .ms_cache)

# --- Fast header summary for the file list (async reader) ----------------
#' mzR-only header summary; ~0.1 s/file. Self-contained for use in a mirai worker.
read_ms_header <- function(path) {
  out <- tryCatch({
    x <- mzR::openMSfile(path)
    on.exit(mzR::close(x))
    h <- mzR::header(x)
    mzs <- suppressWarnings(c(h$lowMZ[h$lowMZ > 0], h$highMZ[h$highMZ > 0]))
    if (!length(mzs)) mzs <- suppressWarnings(h$basePeakMZ[h$basePeakMZ > 0])
    list(summary = list(
      n_spectra  = nrow(h),
      rt_min     = suppressWarnings(min(h$retentionTime, na.rm = TRUE)),
      rt_max     = suppressWarnings(max(h$retentionTime, na.rm = TRUE)),
      mz_min     = if (length(mzs)) min(mzs) else NA_real_,
      mz_max     = if (length(mzs)) max(mzs) else NA_real_,
      ms_levels  = paste(sort(unique(h$msLevel)), collapse = ", "),
      polarities = paste(sort(unique(h$polarity)), collapse = ", ")
    ))
  }, error = function(e) list(error = conditionMessage(e)))
  out$path <- path
  out
}

# --- Filtering (on cached structures) ------------------------------------
#' Indices of spectra in `d` passing the rt / MS-level / polarity filter.
filter_scans <- function(d, f) {
  keep <- rep(TRUE, length(d$rt))
  if (!is.null(f$ms_level) && is.finite(f$ms_level)) keep <- keep & d$msLevel == f$ms_level
  if (!is.null(f$rt_min)   && is.finite(f$rt_min))   keep <- keep & d$rt >= f$rt_min
  if (!is.null(f$rt_max)   && is.finite(f$rt_max))   keep <- keep & d$rt <= f$rt_max
  if (!is.null(f$polarity) && !identical(f$polarity, "any")) {
    pol <- if (identical(f$polarity, "pos")) 1L else 0L
    keep <- keep & d$polarity == pol
  }
  which(keep)
}

# whether m/z or intensity constraints require looking at peak data
.has_mz_int_filter <- function(f) {
  (!is.null(f$mz_min) && is.finite(f$mz_min)) ||
  (!is.null(f$mz_max) && is.finite(f$mz_max)) ||
  (!is.null(f$int_min) && is.finite(f$int_min) && f$int_min > 0)
}

# sum intensity of one peak matrix within an m/z window, above an intensity floor
.window_sum <- function(m, lo, hi, int_min = 0) {
  s <- m[, 1] >= lo & m[, 1] <= hi
  if (int_min > 0) s <- s & m[, 2] >= int_min
  if (any(s)) sum(m[s, 2]) else 0
}

# --- Compute: TIC / BPC --------------------------------------------------
#' @param agg "tic" or "bpc"
compute_chrom <- function(paths, meta, f, agg = "tic") {
  mz_int <- .has_mz_int_filter(f)
  lo <- if (is.finite(f$mz_min)) f$mz_min else 0
  hi <- if (is.finite(f$mz_max)) f$mz_max else Inf
  imin <- if (is.finite(f$int_min)) f$int_min else 0
  pieces <- vector("list", length(paths))
  for (i in seq_along(paths)) {
    d <- get_ms_data(paths[i])
    idx <- filter_scans(d, f)
    if (!length(idx)) next
    if (!mz_int) {
      val <- if (agg == "tic") d$tic[idx] else d$bpi[idx]
    } else {
      val <- vapply(d$peaks[idx], function(m) {
        s <- m[, 1] >= lo & m[, 1] <= hi & m[, 2] >= imin
        if (!any(s)) return(0)
        if (agg == "tic") sum(m[s, 2]) else max(m[s, 2])
      }, numeric(1))
    }
    pieces[[i]] <- tibble::tibble(
      target = toupper(agg), sample_id = meta$id[i], sample_name = meta$name[i],
      rt = d$rt[idx], intensity = val)
  }
  dplyr::bind_rows(pieces)
}

# --- Compute: EICs (manual, issue #809) ----------------------------------
#' @param mz_windows two-column matrix of c(low, high) per target
#' @param labels character labels per target (row of mz_windows)
compute_eic <- function(paths, meta, mz_windows, labels, f) {
  imin <- if (is.finite(f$int_min)) f$int_min else 0
  out <- list(); k <- 0L
  for (i in seq_along(paths)) {
    d <- get_ms_data(paths[i])
    idx <- filter_scans(d, f)
    if (!length(idx)) next
    rt <- d$rt[idx]; pk <- d$peaks[idx]
    for (j in seq_len(nrow(mz_windows))) {
      lo <- mz_windows[j, 1]; hi <- mz_windows[j, 2]
      ints <- vapply(pk, .window_sum, numeric(1), lo = lo, hi = hi, int_min = imin)
      k <- k + 1L
      out[[k]] <- tibble::tibble(
        target = labels[j], sample_id = meta$id[i], sample_name = meta$name[i],
        rt = rt, intensity = ints)
    }
  }
  dplyr::bind_rows(out)
}

# --- Compute: long peak table for one file (MS map / 3D) -----------------
compute_peaks <- function(path, f) {
  d <- get_ms_data(path)
  idx <- filter_scans(d, f)
  if (!length(idx)) return(tibble::tibble(rt = numeric(), mz = numeric(),
                                          intensity = numeric()))
  rt <- d$rt[idx]; pk <- d$peaks[idx]
  lens <- vapply(pk, nrow, integer(1))
  mat <- do.call(rbind, pk)
  df <- tibble::tibble(rt = rep(rt, lens), mz = mat[, 1], intensity = mat[, 2])
  if (is.finite(f$mz_min))  df <- df[df$mz >= f$mz_min, , drop = FALSE]
  if (is.finite(f$mz_max))  df <- df[df$mz <= f$mz_max, , drop = FALSE]
  if (is.finite(f$int_min) && f$int_min > 0) df <- df[df$intensity >= f$int_min, , drop = FALSE]
  df
}

#' Bin long peak data into an rt x m/z grid for heatmap / surface display.
bin_peaks <- function(df, rt_bin = 10, mz_bin = 1, aggfun = max) {
  if (nrow(df) == 0)
    return(tibble::tibble(rt_b = numeric(), mz_b = numeric(), intensity = numeric()))
  df$rt_b <- round(df$rt / rt_bin) * rt_bin
  df$mz_b <- round(df$mz / mz_bin) * mz_bin
  dplyr::summarise(dplyr::group_by(df, rt_b, mz_b),
                   intensity = aggfun(intensity), .groups = "drop")
}

# --- Compute: single spectrum at a retention time ------------------------
get_spectrum_at <- function(path, rt, ms_level = 1L) {
  d <- get_ms_data(path)
  idx <- which(d$msLevel == as.integer(ms_level))
  if (!length(idx)) idx <- seq_along(d$rt)
  i <- idx[which.min(abs(d$rt[idx] - rt))]
  m <- d$peaks[[i]]
  tibble::tibble(mz = m[, 1], intensity = m[, 2], rt = d$rt[i])
}

# --- Compute: precursor ions (DDA) ---------------------------------------
compute_precursors <- function(path) {
  d <- get_ms_data(path)
  idx <- which(d$msLevel > 1 & is.finite(d$precursorMZ) & d$precursorMZ > 0)
  tibble::tibble(rt = d$rt[idx], precursorMZ = d$precursorMZ[idx])
}

# --- Misc ----------------------------------------------------------------
#' Polarity label from the integer code mzR uses (0 neg, 1 pos, -1 unknown).
#' `x` may be a comma-separated string of codes (e.g. "0, 1").
polarity_label <- function(x) {
  if (length(x) == 0 || is.na(x)) return(NA_character_)
  codes <- trimws(strsplit(as.character(x), ",")[[1]])
  lab <- dplyr::recode(codes, "0" = "neg", "1" = "pos", "-1" = "", .default = codes)
  lab <- lab[nzchar(lab)]
  if (length(lab) == 0) NA_character_ else paste(unique(lab), collapse = ", ")
}
