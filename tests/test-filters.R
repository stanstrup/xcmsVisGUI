# Filter tests on real data (gated on msdata). The headline is the EQUIVALENCE
# INVARIANT: apply_filters (MsExperiment path, used by TIC/BPC/EIC) and
# apply_filters_spectra (Spectra path, used by Spectrum/MS map/Precursors) must
# select the SAME spectra for the same filter — that is what "filters apply
# everywhere" depends on, and it is otherwise only maintained by discipline.

if (!requireNamespace("msdata", quietly = TRUE)) {
  skip("msdata not installed — filter tests need real data")
} else {
  p <- normalizePath(list.files(system.file("proteomics", package = "msdata"),
                                full.names = TRUE, pattern = "mzML$")[1])
  fdf <- tibble::tibble(id = "x", path = p, name = basename(p), sample_group = "g")
  raw <- get_spectra(p)
  rts <- Spectra::rtime(raw)
  rt_lo <- as.numeric(stats::quantile(rts, 0.3))
  rt_hi <- as.numeric(stats::quantile(rts, 0.7))

  # Aggregate fingerprint of a Spectra set — order-independent invariants.
  agg <- function(sp) {
    pd <- Spectra::peaksData(sp)
    list(n      = length(sp),
         npeaks = sum(vapply(pd, nrow, integer(1))),
         sumint = round(sum(vapply(pd, function(m) sum(m[, "intensity"]), numeric(1)))),
         rts    = sort(round(Spectra::rtime(sp), 3)))
  }

  f <- function(...) modifyList(empty_filter(), list(...))
  tok <- sub(".*\\b(scan=[0-9]+).*", "\\1", raw$spectrumId[1])

  battery <- list(
    "all levels"      = f(ms_level = NA_integer_),
    "ms_level 1"      = f(ms_level = 1L),
    "ms_level 2"      = f(ms_level = 2L),
    "rt window"       = f(ms_level = NA_integer_, rt_min = rt_lo, rt_max = rt_hi),
    "mz window"       = f(ms_level = NA_integer_, mz_min = 400, mz_max = 800),
    "intensity >=5000"= f(ms_level = NA_integer_, int_min = 5000),
    "polarity pos"    = f(ms_level = NA_integer_, polarity = "pos"),
    "spectrumId"      = f(ms_level = NA_integer_, spectrum_id = tok)
  )

  msexp <- build_msexp(fdf)
  for (nm in names(battery)) {
    flt <- battery[[nm]]
    a <- agg(MsExperiment::spectra(apply_filters(msexp, flt)))
    b <- agg(apply_filters_spectra(raw, flt))
    expect_equal(a$n, b$n, paste0("equiv n spectra [", nm, "]"))
    expect_equal(a$npeaks, b$npeaks, paste0("equiv n peaks [", nm, "]"))
    expect_equal(a$sumint, b$sumint, paste0("equiv sum intensity [", nm, "]"))
    expect_equal(a$rts, b$rts, paste0("equiv rtimes [", nm, "]"))
  }

  # Filters genuinely reach the extraction path (not just no-ops).
  base <- empty_filter()
  p_all <- extract_peaks(p, modifyList(base, list(ms_level = NA_integer_)))
  p_flt <- extract_peaks(p, modifyList(base, list(ms_level = NA_integer_, int_min = 5000)))
  expect(min(p_flt$intensity) >= 5000, "int_min filter raises min intensity in extract_peaks")
  expect(nrow(p_flt) < nrow(p_all), "int_min filter removes peaks")

  sp2 <- apply_filters_spectra(raw, modifyList(base, list(ms_level = NA_integer_, spectrum_id = tok)))
  expect_equal(length(sp2), 1, paste0("spectrumId '", tok, "' selects exactly one spectrum"))
}
