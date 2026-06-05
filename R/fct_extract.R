# Data extraction on Spectra / MsExperiment / xcms.
#
# IMPORTANT: all reads run under BiocParallel SerialParam (registered in global.R
# and in the mirai workers). The default SnowParam backend makes MsBackendMzR
# initialization ~100x slower on Windows — see BENCHMARK.md / SPECTRA_ISSUE.md.

#' Fast file header summary for the file list, via mzR only (~0.1 s/file, no
#' BiocParallel). Runs in a mirai worker. Spectra's read path is avoided here
#' because even under SerialParam it is ~5 s/file (too slow for 100+ files).
#' Returns list(summary=...) or list(error=...).
read_ms_header <- function(path) {
  out <- tryCatch({
    x <- mzR::openMSfile(path)
    on.exit(mzR::close(x))
    h <- mzR::header(x)
    mzs <- suppressWarnings(c(h$lowMZ[h$lowMZ > 0], h$highMZ[h$highMZ > 0]))
    if (!length(mzs)) mzs <- suppressWarnings(h$basePeakMZ[h$basePeakMZ > 0])
    chg <- if ("precursorCharge" %in% colnames(h))
      sort(unique(h$precursorCharge[is.finite(h$precursorCharge) & h$precursorCharge != 0]))
      else integer(0)
    # all-NA retention times (a CDF edge) make min/max return Inf/-Inf, which would
    # leak into the filter range hint — keep non-finite as NA.
    finite_or_na <- function(v) if (is.finite(v)) v else NA_real_
    list(summary = list(
      n_spectra  = nrow(h),
      rt_min     = finite_or_na(suppressWarnings(min(h$retentionTime, na.rm = TRUE))),
      rt_max     = finite_or_na(suppressWarnings(max(h$retentionTime, na.rm = TRUE))),
      mz_min     = if (length(mzs)) min(mzs) else NA_real_,
      mz_max     = if (length(mzs)) max(mzs) else NA_real_,
      ms_levels  = paste(sort(unique(h$msLevel)), collapse = ", "),
      polarities = paste(sort(unique(h$polarity)), collapse = ", "),
      charges    = paste(chg, collapse = ", ")
    ))
  }, error = function(e) list(error = conditionMessage(e)))
  out$path <- path
  out
}

#' Build an MsExperiment from included files, injecting our sample metadata.
build_msexp <- function(files_df) {
  x <- MsExperiment::readMsExperiment(spectraFiles = files_df$path,
                                      BPPARAM = BiocParallel::SerialParam())
  sd <- MsExperiment::sampleData(x)
  sd$sample_id    <- files_df$id
  sd$sample_name  <- files_df$name
  sd$sample_group <- files_df$sample_group
  MsExperiment::sampleData(x) <- sd
  x
}

#' Convert an (M/X)Chromatograms object to a tidy tibble for ggplot.
#' @importFrom tibble tibble
#' @importFrom dplyr bind_rows
#' @noRd
chrom_to_df <- function(chr, meta, labels = NULL) {
  nr <- nrow(chr); nc <- ncol(chr)
  if (is.null(labels)) labels <- paste0("target", seq_len(nr))
  pieces <- vector("list", nr * nc); k <- 0L
  for (i in seq_len(nr)) for (j in seq_len(nc)) {
    cell <- chr[i, j]
    rt  <- xcms::rtime(cell); int <- xcms::intensity(cell)
    if (!length(rt)) next
    k <- k + 1L
    pieces[[k]] <- tibble(
      target = labels[i], sample_id = meta$id[j], sample_name = meta$name[j],
      sample_group = meta$sample_group[j], rt = rt, intensity = int)
  }
  out <- bind_rows(pieces[seq_len(k)])
  out$intensity[is.na(out$intensity)] <- 0
  out
}

#' Cached per-path base Spectra object (MsBackendMzR, lazy). Single-file views
#' (Spectrum, MS map, Precursors) slice/filter from this instead of re-running
#' `Spectra(path, MsBackendMzR())` — a backend header read — on every rt/scan
#' tweak. Filtering returns new subset objects, so the cached object is never
#' mutated. Mirrors `.scan_cache`.
.spectra_cache <- new.env(parent = emptyenv())
get_spectra <- function(path) {
  key <- normalizePath(path, winslash = "/", mustWork = FALSE)
  hit <- get0(key, envir = .spectra_cache, inherits = FALSE)
  if (!is.null(hit)) return(hit)
  sp <- Spectra::Spectra(path, source = Spectra::MsBackendMzR())
  assign(key, sp, envir = .spectra_cache)
  sp
}

#' Extract a single spectrum at a retention time OR a scan (acquisition) number.
#' The global filter `f` is applied (intensity/m/z/polarity/charge/spectrumId);
#' ms_level and the rt/scan selection come from the Spectrum tab controls.
#' @importFrom tibble tibble
#' @noRd
extract_spectrum <- function(path, rt = NA_real_, scan = NA_integer_, f = list()) {
  sp <- get_spectra(path)
  empty <- tibble(mz = numeric(), intensity = numeric(), rt = numeric(),
                          scan = integer())
  one_to_df <- function(one) {
    if (!length(one)) return(empty)
    mzv <- Spectra::mz(one)[[1]]; iv <- Spectra::intensity(one)[[1]]
    if (!length(mzv)) return(empty)
    a <- tryCatch(Spectra::acquisitionNum(one), error = function(e) NA_integer_)
    tibble(mz = mzv, intensity = iv, rt = Spectra::rtime(one)[1], scan = a[1])
  }
  if (!is.null(scan) && is.finite(scan)) {
    # An explicit acquisition-number pick must resolve against the FULL file: the
    # selection filters (ms level, polarity, rt, spectrum id) would otherwise hide
    # the chosen scan (e.g. picking an MS2 scan while the global filter is MS1).
    # Match the nearest acquisition number — NOT a positional index — so the right
    # scan loads regardless of how acquisition numbers are numbered. Only the
    # peak-level intensity / m/z filters still apply to the chosen spectrum.
    anum <- tryCatch(Spectra::acquisitionNum(sp), error = function(e) NULL)
    if (is.null(anum) || !length(anum)) return(empty)
    idx <- which.min(abs(anum - as.integer(scan)))
    pf <- f
    pf$ms_level <- NA_integer_; pf$rt_min <- NA_real_; pf$rt_max <- NA_real_
    pf$polarity <- "any"; pf$spectrum_id <- ""
    return(one_to_df(apply_filters_spectra(sp[idx], pf)))
  }
  # rt-based selection: the global filter chooses which spectrum (ms level etc.).
  ff <- f
  ff$rt_min <- NA_real_; ff$rt_max <- NA_real_     # selection drives rt, not filter
  sp <- apply_filters_spectra(sp, ff)              # ms_level comes from the filter
  if (!length(sp)) return(empty)
  rts <- Spectra::rtime(sp)
  one_to_df(sp[which.min(abs(rts - rt))])
}

#' Extract all peaks (rt, m/z, intensity) from one file as a long tibble (MS map/3D).
#' Applies the full global filter `f` (incl. intensity / spectrumId / charge).
#' @importFrom tibble tibble
#' @noRd
extract_peaks <- function(path, f = list()) {
  sp <- get_spectra(path)
  sp <- apply_filters_spectra(sp, f)
  if (!length(sp)) return(tibble(rt = numeric(), mz = numeric(), intensity = numeric()))
  rt <- Spectra::rtime(sp)
  # peaksData() is an S4 SimpleList; coerce to a base list so do.call(rbind, ...)
  # and vapply work without relying on BiocGenerics::rbind being attached
  # (it isn't, inside the package namespace).
  pd <- as.list(Spectra::peaksData(sp))
  lens <- vapply(pd, nrow, integer(1))
  mat <- do.call(rbind, pd)
  if (is.null(mat)) return(tibble(rt = numeric(), mz = numeric(), intensity = numeric()))
  tibble(rt = rep(rt, lens), mz = mat[, "mz"], intensity = mat[, "intensity"])
}

#' Bin long peak data into an rt x m/z grid for heatmap / surface display.
#' @importFrom tibble tibble
#' @importFrom dplyr group_by summarise
#' @noRd
bin_peaks <- function(df, rt_bin = 10, mz_bin = 1, aggfun = max) {
  if (nrow(df) == 0)
    return(tibble(rt_b = numeric(), mz_b = numeric(), intensity = numeric()))
  df$rt_b <- round(df$rt / rt_bin) * rt_bin
  df$mz_b <- round(df$mz / mz_bin) * mz_bin
  summarise(group_by(df, rt_b, mz_b),
                   intensity = aggfun(intensity), .groups = "drop")
}

#' Cached per-file scan table (rt seconds, acquisition number, MS level) via mzR.
.scan_cache <- new.env(parent = emptyenv())
file_scan_table <- function(path) {
  key <- normalizePath(path, winslash = "/", mustWork = FALSE)
  hit <- get0(key, envir = .scan_cache, inherits = FALSE)
  if (!is.null(hit)) return(hit)
  x <- mzR::openMSfile(path); on.exit(mzR::close(x))
  h <- mzR::header(x)
  col <- function(nm) if (nm %in% colnames(h)) h[[nm]] else NA
  tab <- data.frame(
    scan = h$acquisitionNum, rt = h$retentionTime, msLevel = h$msLevel,
    polarity = col("polarity"), precursorMZ = col("precursorMZ"),
    tic = col("totIonCurrent"), basePeakMZ = col("basePeakMZ"),
    spectrumId = if ("spectrumId" %in% colnames(h)) h$spectrumId else NA_character_,
    stringsAsFactors = FALSE)
  assign(key, tab, envir = .scan_cache)
  tab
}

#' Acquisition number(s) for retention time(s) by matching a file's scan table.
#' Matched on rt rounded to 3 decimals: the Spectra/xcms rtime and the mzR header
#' table agree to ms precision, so 3 decimals is a safe exact-match key. Single
#' home for that contract (used by add_scan_numbers and extract_over_files).
scan_for_rt <- function(rt, scan_table) {
  scan_table$scan[match(round(rt, 3), round(scan_table$rt, 3))]
}

#' Run a per-file `extractor(path)` over the included files, attach the requested
#' sample metadata, optionally join scan numbers by rt, and bind into one tibble.
#' The extractor is wrapped with possibly so an unreadable file is SKIPPED
#' (its name passed to `on_error`) rather than aborting the whole multi-file plot.
#' Keeps the Shiny layer out: the caller supplies `on_error` for any notification.
#' @param files_df included files (needs id, path, name, sample_group)
#' @param extractor function(path) -> tibble with an `rt` column
#' @param cols metadata to attach: any of sample_id / sample_name / sample_group
#' @param scan join acquisition numbers by rt (MS map)
#' @param on_error function(failed_names) called once if any file failed
#' @importFrom purrr possibly
#' @importFrom dplyr bind_rows
#' @noRd
extract_over_files <- function(files_df, extractor, cols = "sample_id",
                               scan = FALSE, on_error = NULL) {
  safe <- possibly(extractor, otherwise = NULL)
  pieces <- lapply(seq_len(nrow(files_df)), function(i) {
    d <- safe(files_df$path[i])
    if (is.null(d)) return(NULL)              # read failed -> skip this file
    if (nrow(d)) {
      if ("sample_id"    %in% cols) d$sample_id    <- files_df$id[i]
      if ("sample_name"  %in% cols) d$sample_name  <- files_df$name[i]
      if ("sample_group" %in% cols) d$sample_group <- files_df$sample_group[i]
      if (scan) d$scan <- scan_for_rt(d$rt, file_scan_table(files_df$path[i]))
    }
    d
  })
  failed <- vapply(pieces, is.null, logical(1))
  if (any(failed) && !is.null(on_error)) on_error(files_df$name[failed])
  bind_rows(pieces)                     # bind_rows drops NULLs
}

#' Empty the per-file caches (.scan_cache + .spectra_cache). Called when the user
#' clears the file list so cached reads don't accumulate across a long session.
#' Path is the cache key; these raw files are effectively immutable, so there is
#' deliberately no mtime check (see ARCHITECTURE_REVIEW.md open question).
clear_ms_caches <- function() {
  rm(list = ls(.scan_cache, all.names = TRUE), envir = .scan_cache)
  rm(list = ls(.spectra_cache, all.names = TRUE), envir = .spectra_cache)
  invisible(NULL)
}

#' Add a `scan` (acquisition number) column to a chromatogram tibble by matching
#' retention time per file. `meta` must carry id + path columns.
add_scan_numbers <- function(df, meta) {
  if (!nrow(df) || is.null(meta$path)) { df$scan <- NA_integer_; return(df) }
  df$scan <- NA_integer_
  for (fid in unique(df$sample_id)) {
    p <- meta$path[meta$id == fid]
    if (!length(p) || is.na(p)) next
    st <- file_scan_table(p)
    idx <- df$sample_id == fid
    df$scan[idx] <- scan_for_rt(df$rt[idx], st)
  }
  df
}

#' Precursor ions (rt, precursor m/z, scan) for MS>1 spectra in a file (DDA map).
#' @importFrom tibble tibble
#' @noRd
extract_precursors <- function(path) {
  sp <- get_spectra(path)
  ms <- Spectra::msLevel(sp); pmz <- Spectra::precursorMz(sp); rt <- Spectra::rtime(sp)
  scn <- tryCatch(Spectra::acquisitionNum(sp), error = function(e) rep(NA_integer_, length(sp)))
  idx <- which(ms > 1 & is.finite(pmz) & pmz > 0)
  tibble(rt = rt[idx], precursorMZ = pmz[idx], scan = scn[idx])
}

#' Polarity label from the integer code Spectra uses (0 neg, 1 pos, -1 unknown).
#' @importFrom dplyr recode
#' @noRd
polarity_label <- function(x) {
  if (length(x) == 0 || is.na(x)) return(NA_character_)
  codes <- trimws(strsplit(as.character(x), ",")[[1]])
  lab <- recode(codes, "0" = "neg", "1" = "pos", "-1" = "", .default = codes)
  lab <- lab[nzchar(lab)]
  if (length(lab) == 0) NA_character_ else paste(unique(lab), collapse = ", ")
}
