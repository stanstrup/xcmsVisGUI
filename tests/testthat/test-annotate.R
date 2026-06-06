# Spectrum-annotation engine (R/fct_annotate.R). The dictionary maths and peak
# matching are tested on synthetic spectra with a known neutral mass. Tests that
# need the external dictionary / ranker SKIP when commonMZ / InterpretMSSpectrum
# are absent (they are hard Imports, but CI may lack the GitHub-only commonMZ).

test_that("tol_to_da gives ppm and Da half-windows", {
  expect_equal(tol_to_da(200, 10, "ppm"), 200 * 10 / 1e6)
  expect_equal(tol_to_da(200, 0.01, "Da"), 0.01)
  expect_equal(tol_to_da(c(100, 500), 5, "ppm"), c(100, 500) * 5 / 1e6)
})

test_that("centroid_peaks collapses a profile peak to its apex, above the floor", {
  # a profile-mode peak (tight spacing) apexing at 100.02, plus a far noise point
  df <- tibble::tibble(
    mz  = c(100.000, 100.002, 100.004, 100.006, 100.008, 200.0),
    intensity = c(10, 60, 100, 55, 8, 2))
  cp <- centroid_peaks(df, rel_floor = 0.05, mz_gap = 0.01)  # floor = 5
  expect_equal(cp$mz, 100.004)                 # one apex; shoulders collapsed
  expect_equal(cp$intensity, 100)
  expect_false(200.0 %in% cp$mz)               # below 5% floor
})

test_that("neutral_mass and adduct_mz invert each other", {
  # [M+H]+: charge 1, nmol 1, massdiff = proton mass
  hp <- data.frame(charge = 1, nmol = 1, massdiff = 1.007276)
  M <- neutral_mass(301.107276, hp)
  expect_equal(M, 300.1, tolerance = 1e-6)
  expect_equal(adduct_mz(M, hp), 301.107276, tolerance = 1e-9)

  # [M+2H]2+ and [2M+H]+ algebra
  h2 <- data.frame(charge = 2, nmol = 1, massdiff = 2.014552)
  expect_equal(adduct_mz(300.1, h2), (300.1 + 2.014552) / 2, tolerance = 1e-9)
  dimer <- data.frame(charge = 1, nmol = 2, massdiff = 1.007276)
  expect_equal(neutral_mass(601.207276, dimer), 300.1, tolerance = 1e-6)
})

test_that("match_spectrum flags hits, misses and honours tolerance", {
  expected <- tibble::tibble(label = c("a", "b", "c"), type = "adduct",
                             mz = c(200.0, 300.0, 400.0), charge = 1)
  # peak for a is exact; for b it is 12 ppm high; c absent
  spec <- tibble::tibble(mz = c(200.0, 300.0 * (1 + 12e-6)),
                         intensity = c(500, 800))
  m10 <- match_spectrum(spec, expected, tol = 10, unit = "ppm")
  expect_identical(m10$matched, c(TRUE, FALSE, FALSE))
  expect_equal(m10$intensity[1], 500)
  expect_lt(abs(m10$ppm_err[1]), 1e-6)
  m15 <- match_spectrum(spec, expected, tol = 15, unit = "ppm")
  expect_true(m15$matched[2])
  expect_equal(m15$ppm_err[2], 12, tolerance = 1e-3)
})

test_that("adduct_rules + project_ions + match round-trip on a planted spectrum", {
  skip_if_not_installed("commonMZ")
  M <- 300.1
  rules <- adduct_rules("pos")
  pick <- function(nm) adduct_mz(M, rules[rules$name == nm, , drop = FALSE])[1]
  mzH  <- pick("[M+H]+"); mzNa <- pick("[M+Na]+")
  iso1 <- mzH + ISOTOPE_SPACING                 # M+1 of [M+H]+ (charge 1)
  frag <- mzH - 18.01057                         # in-source water loss
  spec <- tibble::tibble(mz = c(mzH, mzNa, iso1, frag),
                         intensity = c(1000, 400, 150, 250))

  exp_tab <- project_ions(M, "pos", isotopes = 1L, losses = TRUE)
  expect_true(all(c("adduct", "isotope", "fragment") %in% exp_tab$type))

  res <- match_spectrum(spec, exp_tab, tol = 10, unit = "ppm")
  is_match <- function(nm) isTRUE(res$matched[match(nm, res$label)])
  expect_true(is_match("[M+H]+"))
  expect_true(is_match("[M+Na]+"))
  expect_true(is_match("[M+H]+ [+1]"))           # isotope label format
  expect_true(any(res$type == "fragment" & res$matched))
})

test_that("annotate_anchor recovers the neutral mass from a chosen adduct", {
  skip_if_not_installed("commonMZ")
  rules <- adduct_rules("pos")
  mzH <- adduct_mz(300.1, rules[rules$name == "[M+H]+", , drop = FALSE])[1]
  spec <- tibble::tibble(mz = c(mzH, mzH + ISOTOPE_SPACING), intensity = c(1000, 150))
  ann <- annotate_anchor(spec, anchor_mz = mzH, adduct = "[M+H]+", mode = "pos",
                         tol = 10, unit = "ppm")
  expect_equal(ann$M, 300.1, tolerance = 1e-4)
  expect_true(isTRUE(ann$table$matched[match("[M+H]+", ann$table$label)]))
})

test_that("difference_network finds a water-loss edge", {
  skip_if_not_installed("commonMZ")
  spec <- tibble::tibble(mz = c(200.0, 218.01057, 999.0),
                         intensity = c(1000, 600, 900))
  net <- difference_network(spec, tol = 10, unit = "ppm", top_n = 30)
  expect_gte(nrow(net), 1)
  hit <- net[abs(net$delta - 18.01057) < 0.01, ]
  expect_equal(nrow(hit), 1)
  expect_match(hit$origin, "H2O", fixed = TRUE)
})

test_that("rank_anchors suggests the right molecular ion via findMAIN", {
  skip_if_not_installed("commonMZ")
  skip_if_not_installed("InterpretMSSpectrum")
  rules <- adduct_rules("pos")
  pm <- function(nm) adduct_mz(300.1, rules[rules$name == nm, , drop = FALSE])[1]
  spec <- tibble::tibble(
    mz  = c(pm("[M+H]+"), pm("[M+H]+") + ISOTOPE_SPACING, pm("[M+Na]+"), pm("[M+K]+")),
    intensity = c(1000, 160, 400, 120))
  rk <- rank_anchors(spec, mode = "pos", ppm = 5, top_n = 5)
  expect_gt(nrow(rk), 0)
  expect_equal(rk$neutral_mass[1], 300.1, tolerance = 0.01)
})
