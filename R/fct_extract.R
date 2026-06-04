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
chrom_to_df <- function(chr, meta, labels = NULL) {
  nr <- nrow(chr); nc <- ncol(chr)
  if (is.null(labels)) labels <- paste0("target", seq_len(nr))
  pieces <- vector("list", nr * nc); k <- 0L
  for (i in seq_len(nr)) for (j in seq_len(nc)) {
    cell <- chr[i, j]
    rt  <- xcms::rtime(cell); int <- xcms::intensity(cell)
    if (!length(rt)) next
    k <- k + 1L
    pieces[[k]] <- tibble::tibble(
      target = labels[i], sample_id = meta$id[j], sample_name = meta$name[j],
      sample_group = meta$sample_group[j], rt = rt, intensity = int)
  }
  out <- dplyr::bind_rows(pieces[seq_len(k)])
  out$intensity[is.na(out$intensity)] <- 0
  out
}

#' Extract a single spectrum (m/z + intensity) nearest a retention time.
extract_spectrum <- function(path, rt, ms_level = 1L) {
  sp <- Spectra::Spectra(path, source = Spectra::MsBackendMzR())
  sp <- Spectra::filterMsLevel(sp, as.integer(ms_level))
  rts <- Spectra::rtime(sp)
  if (!length(rts)) return(tibble::tibble(mz = numeric(), intensity = numeric(), rt = numeric()))
  idx <- which.min(abs(rts - rt))
  one <- sp[idx]
  tibble::tibble(mz = Spectra::mz(one)[[1]], intensity = Spectra::intensity(one)[[1]],
                 rt = rts[idx])
}

#' Extract all peaks (rt, m/z, intensity) from one file as a long tibble (MS map/3D).
extract_peaks <- function(path, ms_level = 1L, rt_range = NULL, mz_range = NULL) {
  sp <- Spectra::Spectra(path, source = Spectra::MsBackendMzR())
  sp <- Spectra::filterMsLevel(sp, as.integer(ms_level))
  if (!is.null(rt_range)) sp <- Spectra::filterRt(sp, rt_range)
  rt <- Spectra::rtime(sp)
  pd <- Spectra::peaksData(sp)
  lens <- vapply(pd, nrow, integer(1))
  mat <- do.call(rbind, pd)
  if (is.null(mat)) return(tibble::tibble(rt = numeric(), mz = numeric(), intensity = numeric()))
  df <- tibble::tibble(rt = rep(rt, lens), mz = mat[, "mz"], intensity = mat[, "intensity"])
  if (!is.null(mz_range))
    df <- df[df$mz >= mz_range[1] & df$mz <= mz_range[2], , drop = FALSE]
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

#' Precursor ions (rt + precursor m/z) for MS>1 spectra in a file (DDA map).
extract_precursors <- function(path) {
  sp <- Spectra::Spectra(path, source = Spectra::MsBackendMzR())
  ms <- Spectra::msLevel(sp); pmz <- Spectra::precursorMz(sp); rt <- Spectra::rtime(sp)
  idx <- which(ms > 1 & is.finite(pmz) & pmz > 0)
  tibble::tibble(rt = rt[idx], precursorMZ = pmz[idx])
}

#' Polarity label from the integer code Spectra uses (0 neg, 1 pos, -1 unknown).
polarity_label <- function(x) {
  if (length(x) == 0 || is.na(x)) return(NA_character_)
  codes <- trimws(strsplit(as.character(x), ",")[[1]])
  lab <- dplyr::recode(codes, "0" = "neg", "1" = "pos", "-1" = "", .default = codes)
  lab <- lab[nzchar(lab)]
  if (length(lab) == 0) NA_character_ else paste(unique(lab), collapse = ", ")
}
