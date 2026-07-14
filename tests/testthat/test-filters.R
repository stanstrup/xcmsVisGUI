# Filter tests on real data (skip without msdata). Headline: the EQUIVALENCE
# INVARIANT — apply_filters (MsExperiment path: TIC/BPC/EIC) and
# apply_filters_spectra (Spectra path: Spectrum/MS map/Precursors) must select
# the SAME spectra for the same filter. That is what "filters apply everywhere"
# rests on, and is otherwise only kept true by discipline.
#
# The one deliberate exception is `centroid`: peak-picking is spectrum-level, so
# apply_filters_spectra applies it and apply_filters (chromatograms) does not.
# The equivalence battery therefore pins centroid = "off" — it is about which
# SPECTRA get selected. Centroiding is covered on its own below.

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
  f <- function(...) modifyList(empty_filter(), list(centroid = "off", ...))
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

# --- profile mode ------------------------------------------------------------

test_that("spec_mode_label reads the per-spectrum centroided counts", {
  expect_equal(spec_mode_label(0, 5), "centroid")
  expect_equal(spec_mode_label(5, 0), "profile")
  expect_equal(spec_mode_label(2, 3), "mixed")
  expect_true(is.na(spec_mode_label(0, 0)))    # nothing declared (CDF)
})

test_that("profile detection is per MS level, so mixed files keep their centroids", {
  # MS3TMT11.mzML is the mixed case this design exists for: profile MS1 +
  # already-centroided MS2/MS3. Peak-picking the whole file would gut the MS2s.
  p <- msdata_mzml()
  raw <- get_spectra(p)
  cen <- Spectra::centroided(raw)
  skip_if_not(any(cen) && any(!cen), "test file is not mixed-mode")

  prof_lv <- profile_ms_levels(raw)
  expect_true(is_profile_spectra(raw))
  # exactly the levels that carry non-centroided spectra
  expect_setequal(prof_lv, unique(Spectra::msLevel(raw)[!cen]))
  expect_false(any(prof_lv %in% Spectra::msLevel(raw)[cen & !is.na(cen)]))

  # The centroided levels must come through peak-for-peak untouched.
  f_auto <- modifyList(empty_filter(), list(ms_level = NA_integer_, centroid = "auto"))
  npk <- function(sp) vapply(as.list(Spectra::peaksData(sp)), nrow, integer(1))
  keep <- which(cen)
  expect_equal(npk(apply_filters_spectra(raw, f_auto)[keep]), npk(raw[keep]))

  # ...while the profile level really is reduced to centroids.
  pr <- which(!cen)
  expect_lt(sum(npk(apply_filters_spectra(raw, f_auto)[pr])), sum(npk(raw[pr])))
})

test_that("the centroid policy is honoured: off leaves profile spectra raw", {
  p <- msdata_mzml()
  raw <- get_spectra(p)
  skip_if_not(any(!Spectra::centroided(raw)), "test file has no profile spectra")
  pr <- which(!Spectra::centroided(raw))
  f <- function(mode) modifyList(empty_filter(),
                                 list(ms_level = NA_integer_, centroid = mode))
  npeaks <- function(mode) sum(vapply(
    as.list(Spectra::peaksData(apply_filters_spectra(raw, f(mode))[pr])),
    nrow, integer(1)))
  raw_n <- sum(vapply(as.list(Spectra::peaksData(raw[pr])), nrow, integer(1)))

  expect_equal(npeaks("off"), raw_n)      # untouched
  expect_lt(npeaks("auto"), raw_n)        # picked
  expect_lt(npeaks("on"), raw_n)          # forced
})

test_that("spectrum_filter resolves auto to raw, and passes on/off through", {
  f <- function(mode) modifyList(empty_filter(), list(centroid = mode))
  expect_identical(spectrum_filter(f("auto"))$centroid, "off")   # raw in Spectrum
  expect_identical(spectrum_filter(f("on"))$centroid,   "on")    # user's word
  expect_identical(spectrum_filter(f("off"))$centroid,  "off")
  # the MS map path (rv$filter, unmodified) still picks under auto
  expect_identical(f("auto")$centroid, "auto")
})

test_that("the profile line survives ggplotly as ONE trace (not shattered per point)", {
  # Regression: the `text` tooltip is unique per row, so ggplot inferred a group
  # per row and geom_line became 19,720 single-point "lines" -> plotly drew an
  # empty plot (axes, title, no data). Only an explicit `group` prevents it.
  # Assert on the BUILT plotly object: ggplot_build alone cannot see this.
  df <- tibble::tibble(mz = seq(100, 110, length.out = 200),
                       intensity = runif(200, 0, 1e5),
                       sample_name = "s")
  df$.tip <- sprintf("m/z: %.4f", df$mz)
  trace_len <- function(g)
    length(plotly::plotly_build(plotly::ggplotly(g, tooltip = "text",
                                                 dynamicTicks = TRUE))$x$data[[1]]$x)

  grouped <- ggplot2::ggplot(df, ggplot2::aes(x = mz, y = intensity, text = .tip,
                                              group = sample_name)) +
    ggplot2::geom_line(linewidth = 0.3)
  expect_equal(trace_len(grouped), nrow(df))

  # the ungrouped form is what broke: plotly gets ~2n coords of segment soup
  ungrouped <- ggplot2::ggplot(df, ggplot2::aes(x = mz, y = intensity, text = .tip)) +
    ggplot2::geom_line(linewidth = 0.3)
  expect_gt(trace_len(ungrouped), nrow(df))
})

test_that("extract_spectrum reports whether its peaks are still profile", {
  p <- msdata_mzml()
  raw <- get_spectra(p)
  pr <- which(!Spectra::centroided(raw))
  skip_if_not(length(pr) > 0, "test file has no profile spectra")
  lv <- Spectra::msLevel(raw)[pr[1]]
  rt <- Spectra::rtime(raw)[pr[1]]
  f <- function(mode) modifyList(empty_filter(),
                                 list(ms_level = lv, centroid = mode))

  d_off  <- extract_spectrum(p, rt = rt, f = f("off"))
  d_auto <- extract_spectrum(p, rt = rt, f = f("auto"))
  expect_true(all(d_off$profile))     # raw trace -> the plot draws a line
  expect_false(any(d_auto$profile))   # picked    -> the plot draws sticks
  expect_lt(nrow(d_auto), nrow(d_off))
})
