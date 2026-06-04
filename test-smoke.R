# Smoke test for the mzR data layer: faahKO (CDF) and msdata (mzML).
suppressWarnings(suppressMessages({ library(mzR); library(dplyr) }))
for (f in list.files("R", full.names = TRUE)) source(f)

flt <- list(ms_level = 1L, rt_min = NA_real_, rt_max = NA_real_,
            mz_min = NA_real_, mz_max = NA_real_, polarity = "any", int_min = NA_real_)

check <- function(path, label) {
  cat("\n== ", label, " ==\n", sep = "")
  h <- read_ms_header(path)
  if (!is.null(h$error)) { cat("  header ERROR:", h$error, "\n"); return(invisible()) }
  s <- h$summary
  cat(sprintf("  header: n=%d rt=%.0f-%.0f ms=%s pol=%s\n",
              s$n_spectra, s$rt_min, s$rt_max, s$ms_levels, s$polarities))
  meta <- tibble::tibble(id = "x", name = basename(path), sample_group = "g")
  tic <- compute_chrom(path, meta, flt, "tic")
  pk  <- compute_peaks(path, flt)
  sp  <- get_spectrum_at(path, mean(range(tic$rt)), 1L)
  cat(sprintf("  TIC rows=%d  peaks=%d  spectrum peaks=%d\n",
              nrow(tic), nrow(pk), nrow(sp)))
}

cdf  <- list.files(system.file("cdf", package = "faahKO"), recursive = TRUE,
                   full.names = TRUE, pattern = "CDF$")[1]
mzml <- list.files(system.file("proteomics", package = "msdata"),
                   full.names = TRUE, pattern = "mzML$")[1]
if (!is.na(cdf))  check(cdf,  "faahKO CDF")
if (!is.na(mzml)) check(mzml, "msdata mzML")
cat("\nSMOKE OK\n")
