# Fine isotope-pattern engine (R/fct_isotope.R): formula proposal (Rdisop) +
# fine isotopologues and profile envelope (enviPat). Pure, so tested directly.

skip_if_not_installed("Rdisop")
skip_if_not_installed("enviPat")

CAFFEINE_M <- 194.08038   # C8H10N4O2 neutral monoisotopic

test_that("formula_candidates proposes the right formula and honours filters", {
  fc <- formula_candidates(CAFFEINE_M, ppm = 5)
  expect_true("C8H10N4O2" %in% fc$formula)
  hit <- fc[fc$formula == "C8H10N4O2", ]
  expect_lt(abs(hit$ppm_err), 1)
  expect_equal(hit$dbe, 6)
  expect_true(all(fc$valid))                       # valid_only default
  expect_true(all(diff(abs(fc$ppm_err)) >= 0))     # sorted by |error|
  # min_dbe filter drops negative-DBE formulas
  expect_true(all(fc$dbe >= 0))
  expect_equal(nrow(formula_candidates(-1)), 0L)   # bad mass -> empty
})

test_that("scale_formula multiplies element counts", {
  expect_equal(scale_formula("C8H10N4O2", 1), "C8H10N4O2")
  expect_equal(scale_formula("C8H10N4O2", 2), "C16H20N8O4")
  expect_equal(scale_formula("CH4", 3), "C3H12")
})

test_that("isotope_pattern places the ion at the adduct m/z with fine structure", {
  rule <- adduct_rules("pos")[adduct_rules("pos")$name == "[M+H]+", ]
  pat <- isotope_pattern("C8H10N4O2", rule)
  expect_gt(nrow(pat), 3)                          # several isotopologues
  base <- pat$mz[which.max(pat$abundance)]
  expect_equal(base, 195.0877, tolerance = 1e-3)   # [caffeine+H]+
  expect_equal(max(pat$abundance), 1)              # relative to base
  # 13C and 15N isotopologues are distinct masses near M+1 (the "fine" structure)
  m1 <- pat$mz[pat$mz > base + 0.5 & pat$mz < base + 1.5]
  expect_gt(length(unique(round(m1, 3))), 1)
})

test_that("isotope_profile resolves fine structure only at high resolution", {
  rule <- adduct_rules("pos")[adduct_rules("pos")$name == "[M+H]+", ]
  pat <- isotope_pattern("C8H10N4O2", rule)
  peaks <- function(df) sum(diff(sign(diff(df$intensity))) < 0)  # local maxima
  hi <- isotope_profile(pat, resolution = 70000)
  lo <- isotope_profile(pat, resolution = 8000)
  expect_equal(max(hi$intensity), 1)
  expect_gt(peaks(hi), peaks(lo))                  # fine structure merges at low R
  expect_equal(nrow(isotope_profile(pat[0, ], 70000)), 0L)
})

test_that("estimate_resolution recovers R from a synthetic Gaussian peak", {
  R <- 60000; mz0 <- 300
  fwhm <- mz0 / R; sd <- fwhm / (2 * sqrt(2 * log(2)))
  g <- seq(mz0 - 0.2, mz0 + 0.2, length.out = 400)
  prof <- tibble::tibble(mz = g, intensity = exp(-0.5 * ((g - mz0) / sd)^2))
  est <- estimate_resolution(prof, mz0)
  expect_gt(est, R * 0.8); expect_lt(est, R * 1.2)
  expect_true(is.na(estimate_resolution(tibble::tibble(mz = 1, intensity = 1), 1)))
})
