# Smoke test for the Spectra+SerialParam data layer: faahKO (CDF) + msdata (mzML).
suppressWarnings(suppressMessages(source("global.R")))
for (f in list.files("R", full.names = TRUE)) source(f)

flt <- list(ms_level = 1L, rt_min = NA_real_, rt_max = NA_real_,
            mz_min = NA_real_, mz_max = NA_real_, polarity = "any", int_min = NA_real_)

check <- function(path, label) {
  cat("\n== ", label, " ==\n", sep = "")
  h <- read_ms_header(path)
  stopifnot("header read failed" = is.null(h$error))
  s <- h$summary
  cat(sprintf("  header: n=%d rt=%.0f-%.0f ms=%s\n",
              s$n_spectra, s$rt_min, s$rt_max, s$ms_levels))
  files_df <- tibble::tibble(id = "x", path = path, name = basename(path), sample_group = "g")
  meta <- files_df[, c("id", "name", "sample_group")]
  x   <- apply_filters(build_msexp(files_df), flt)
  tic <- chrom_to_df(chromatogram(x, aggregationFun = "sum"), meta, "TIC")
  pk  <- extract_peaks(path)
  sp  <- extract_spectrum(path, mean(range(tic$rt)), 1L)
  cat(sprintf("  TIC rows=%d  peaks=%d  spectrum peaks=%d\n",
              nrow(tic), nrow(pk), nrow(sp)))
  # Assert (don't just eyeball): extraction returns data with the right columns.
  stopifnot(
    "header has spectra" = s$n_spectra > 0,
    "TIC non-empty"      = nrow(tic) > 0,
    "TIC columns"        = all(c("rt", "intensity", "sample_id") %in% names(tic)),
    "peaks non-empty"    = nrow(pk) > 0,
    "peaks columns"      = all(c("rt", "mz", "intensity") %in% names(pk)),
    "spectrum non-empty" = nrow(sp) > 0,
    "spectrum columns"   = all(c("mz", "intensity", "rt", "scan") %in% names(sp)))
}

cat("main bpparam:", class(BiocParallel::bpparam())[1], "(expect SerialParam)\n")
cdf  <- list.files(system.file("cdf", package = "faahKO"), recursive = TRUE,
                   full.names = TRUE, pattern = "CDF$")[1]
mzml <- list.files(system.file("proteomics", package = "msdata"),
                   full.names = TRUE, pattern = "mzML$")[1]
if (!is.na(cdf))  check(cdf,  "faahKO CDF")
if (!is.na(mzml)) check(mzml, "msdata mzML")
mirai::daemons(0)
cat("\nSMOKE OK\n")
