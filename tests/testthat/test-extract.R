# Real-data extraction smoke (skip without the Bioc data packages). Asserts the
# whole read/extract pipeline returns non-empty data with the expected columns —
# the check that used to live in test-smoke.R.

run_extract_checks <- function(path) {
  h <- read_ms_header(path)
  expect_null(h$error)
  expect_gt(h$summary$n_spectra, 0)

  fdf <- tibble::tibble(id = "x", path = path, name = basename(path), sample_group = "g")
  meta <- fdf[, c("id", "name", "sample_group")]
  x <- apply_filters(build_msexp(fdf), empty_filter())
  tic <- chrom_to_df(chromatogram(x, aggregationFun = "sum"), meta, "TIC")
  pk <- extract_peaks(path, empty_filter())
  sp <- extract_spectrum(path, rt = mean(range(tic$rt)), scan = NA_integer_, f = empty_filter())

  expect_gt(nrow(tic), 0)
  expect_true(all(c("rt", "intensity", "sample_id") %in% names(tic)))
  expect_gt(nrow(pk), 0)
  expect_true(all(c("rt", "mz", "intensity") %in% names(pk)))
  expect_gt(nrow(sp), 0)
  expect_true(all(c("mz", "intensity", "rt", "scan") %in% names(sp)))
}

test_that("bpparam is SerialParam (the performance fix is active)", {
  expect_s4_class(BiocParallel::bpparam(), "SerialParam")
})

test_that("extraction works on msdata mzML", {
  skip_if_not_installed("msdata")
  p <- normalizePath(list.files(system.file("proteomics", package = "msdata"),
                                full.names = TRUE, pattern = "mzML$")[1])
  run_extract_checks(p)
})

test_that("extraction works on faahKO CDF", {
  skip_if_not_installed("faahKO")
  p <- list.files(system.file("cdf", package = "faahKO"), recursive = TRUE,
                  full.names = TRUE, pattern = "CDF$")[1]
  skip_if(is.na(p))
  run_extract_checks(p)
})

test_that("extract_over_files isolates a bad file", {
  skip_if_not_installed("msdata")
  p <- normalizePath(list.files(system.file("proteomics", package = "msdata"),
                                full.names = TRUE, pattern = "mzML$")[1])
  mixed <- tibble::tibble(id = c("x", "y"), path = c(p, "no/such/file.mzML"),
                          name = c(basename(p), "missing.mzML"),
                          sample_group = c("g", "g"))
  failed <- NULL
  d <- extract_over_files(mixed, extract_precursors,
                          cols = c("sample_id", "sample_name"),
                          on_error = function(nm) failed <<- nm)
  expect_identical(failed, "missing.mzML")
  expect_identical(unique(d$sample_id), "x")
})
