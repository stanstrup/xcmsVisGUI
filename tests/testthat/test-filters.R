# Filter tests on real data (skip without msdata). Headline: the EQUIVALENCE
# INVARIANT — apply_filters (MsExperiment path: TIC/BPC/EIC) and
# apply_filters_spectra (Spectra path: Spectrum/MS map/Precursors) must select
# the SAME spectra for the same filter. That is what "filters apply everywhere"
# rests on, and is otherwise only kept true by discipline.

skip_if_not_installed("msdata")

msdata_mzml <- function() {
  normalizePath(list.files(system.file("proteomics", package = "msdata"),
                           full.names = TRUE, pattern = "mzML$")[1])
}

# Order-independent fingerprint of a Spectra set.
agg <- function(sp) {
  pd <- as.list(Spectra::peaksData(sp))
  list(n      = length(sp),
       npeaks = sum(vapply(pd, nrow, integer(1))),
       sumint = round(sum(vapply(pd, function(m) sum(m[, "intensity"]), numeric(1)))),
       rts    = sort(round(Spectra::rtime(sp), 3)))
}

test_that("apply_filters and apply_filters_spectra select identical spectra", {
  p <- msdata_mzml()
  fdf <- tibble::tibble(id = "x", path = p, name = basename(p), sample_group = "g")
  raw <- get_spectra(p)
  rts <- Spectra::rtime(raw)
  rt_lo <- as.numeric(stats::quantile(rts, 0.3))
  rt_hi <- as.numeric(stats::quantile(rts, 0.7))
  f <- function(...) modifyList(empty_filter(), list(...))
  # NB: assign spectrum_id_rules directly, never via modifyList — modifyList
  # recurses into the existing empty list() and, the rule list being unnamed,
  # would silently merge it back to list() (no filter). The app sets it directly.
  with_rules <- function(flt, ...) { flt$spectrum_id_rules <- list(...); flt }
  tok <- sub(".*\\b(scan=[0-9]+).*", "\\1", raw$spectrumId[1])

  battery <- list(
    "all levels"       = f(ms_level = NA_integer_),
    "ms_level 1"       = f(ms_level = 1L),
    "ms_level 2"       = f(ms_level = 2L),
    "rt window"        = f(ms_level = NA_integer_, rt_min = rt_lo, rt_max = rt_hi),
    "mz window"        = f(ms_level = NA_integer_, mz_min = 400, mz_max = 800),
    "intensity >=5000" = f(ms_level = NA_integer_, int_min = 5000),
    "polarity pos"     = f(ms_level = NA_integer_, polarity = "pos"),
    "spectrumId"       = with_rules(f(ms_level = NA_integer_),
                                    list(mode = "contains", text = tok)))

  msexp <- build_msexp(fdf)
  for (nm in names(battery)) {
    flt <- battery[[nm]]
    a <- agg(MsExperiment::spectra(apply_filters(msexp, flt)))
    b <- agg(apply_filters_spectra(raw, flt))
    expect_equal(a$n, b$n, info = nm)
    expect_equal(a$npeaks, b$npeaks, info = nm)
    expect_equal(a$sumint, b$sumint, info = nm)
    expect_equal(a$rts, b$rts, info = nm)
  }
})

test_that("filters reach the extraction path", {
  p <- msdata_mzml()
  raw <- get_spectra(p)
  base <- empty_filter()
  p_all <- extract_peaks(p, modifyList(base, list(ms_level = NA_integer_)))
  p_flt <- extract_peaks(p, modifyList(base, list(ms_level = NA_integer_, int_min = 5000)))
  expect_gte(min(p_flt$intensity), 5000)
  expect_lt(nrow(p_flt), nrow(p_all))

  # assign spectrum_id_rules directly (not via modifyList — see the note in the
  # equivalence test above).
  tok <- sub(".*\\b(scan=[0-9]+).*", "\\1", raw$spectrumId[1])
  fl <- modifyList(base, list(ms_level = NA_integer_))
  fl$spectrum_id_rules <- list(list(mode = "contains", text = tok))
  sp2 <- apply_filters_spectra(raw, fl)
  expect_equal(length(sp2), 1)

  # exclude inverts: everything except that one spectrum
  fl$spectrum_id_rules <- list(list(mode = "exclude", text = tok))
  sp3 <- apply_filters_spectra(raw, fl)
  expect_equal(length(sp3), length(raw) - 1)
})
