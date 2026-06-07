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
  mzH  <- pick("[M+H]+"); mzNa <- pick("[M+Na]+"); frag <- mzH - 18.01056
  spec <- tibble::tibble(mz = c(mzH, mzNa, frag), intensity = c(1000, 400, 250))

  exp_tab <- project_ions(M, "pos")
  expect_true(all(c("adduct", "fragment") %in% exp_tab$type))
  expect_false("isotope" %in% exp_tab$type)          # isotopes are detected, not projected

  res <- match_spectrum(spec, exp_tab, tol = 10, unit = "ppm")
  is_match <- function(nm) isTRUE(res$matched[match(nm, res$label)])
  expect_true(is_match("[M+H]+"))
  expect_true(is_match("[M+Na]+"))
  expect_true(is_match("[M+H-H2O]+"))                # in-source fragment matched
})

test_that("annotate_anchor labels DETECTED isotopes as [+k]", {
  skip_if_not_installed("commonMZ")
  rules <- adduct_rules("pos")
  mzH <- adduct_mz(300.1, rules[rules$name == "[M+H]+", , drop = FALSE])[1]
  # plausible 13C envelope for ~300 Da (M+1 ~23 %, M+2 ~3 %)
  spec <- tibble::tibble(mz = c(mzH, mzH + ISOTOPE_SPACING, mzH + 2 * ISOTOPE_SPACING),
                         intensity = c(1000, 230, 27))
  ann <- annotate_anchor(spec, mzH, "[M+H]+", "pos", tol = 10, unit = "ppm",
                         isotopes = 2)
  iso <- ann$table$label[ann$table$type == "isotope" & ann$table$matched]
  expect_true("[+1]" %in% iso)
  expect_true("[+2]" %in% iso)
})

test_that("is_fragment_rule separates in-source losses from adducts by mass", {
  p <- 1.007276
  expect_true(is_fragment_rule(p - 18.010565, 1))   # [M+H-H2O]+ : net loss
  expect_true(is_fragment_rule(p - 43.989830, 1))   # [M+H-CO2]+ : net loss
  expect_true(is_fragment_rule(-p - 18.010565, -1)) # [M-H-H2O]- : net loss
  expect_false(is_fragment_rule(p, 1))              # [M+H]+  : adds mass
  expect_false(is_fragment_rule(22.989, 1))         # [M+Na]+ : adds mass
  expect_false(is_fragment_rule(34.969, -1))        # [M+Cl]- : adds mass
  expect_false(is_fragment_rule(-p, -1))            # [M-H]-  : deprotonation
  expect_false(is_fragment_rule(-2 * p, -2))        # [M-2H]2-: deprotonation
})

test_that("project_ions includes adducts and in-source fragments, toggleable", {
  skip_if_not_installed("commonMZ")
  tab <- project_ions(300.1, "pos")
  expect_true("[M+H]+" %in% tab$label && "[M+H-H2O]+" %in% tab$label)
  expect_true("fragment" %in% tab$type)
  nof <- project_ions(300.1, "pos", fragments = FALSE)
  expect_true(all(nof$type == "adduct"))
  expect_false("[M+H-H2O]+" %in% nof$label)
})

test_that("project_ions max_charge filters multiply-charged ions", {
  skip_if_not_installed("commonMZ")
  t1 <- project_ions(300.1, "pos", max_charge = 1)
  expect_true(all(abs(t1$charge) <= 1))
  t2 <- project_ions(300.1, "pos", max_charge = 3)
  expect_true(max(abs(t2$charge)) > 1)
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

test_that("difference_network window is the peak accuracy, not ppm of the delta", {
  skip_if_not_installed("commonMZ")
  # A real water-loss ladder at m/z ~425: each rung is 18.0106 but the measured
  # peaks carry ~5 ppm error, so the observed delta is off by ~0.003 Da — far more
  # than ppm-of-18 (0.00018 Da). All three rungs must still be annotated.
  mz <- c(416.3099, 434.3229, 452.3308, 470.3417)
  spec <- tibble::tibble(mz = mz, intensity = c(3556, 4043, 928, 729))
  net <- difference_network(spec, tol = 10, unit = "ppm", top_n = 30)
  rungs <- net[abs(net$delta - 18.0106) < 0.012, ]
  expect_gte(nrow(rungs), 3)                       # 416-434, 434-452, 452-470
  expect_true(all(grepl("H2O", rungs$origin, fixed = TRUE)))
})

test_that("difference_network deisotopes before pairing", {
  skip_if_not_installed("commonMZ")
  # 452 (mono) + 453.003 (M+1) + 470.011 (= 452 + H2O). The M+1 satellite must be
  # dropped, so it forms no edge; the real water-loss edge (452-470) must remain.
  spec <- tibble::tibble(mz = c(452.00000, 453.00336, 470.01057),
                         intensity = c(1000, 250, 600))
  net <- difference_network(spec, tol = 15, unit = "ppm")
  expect_false(any(abs(net$mz_lo - 453.00336) < 0.01 |
                   abs(net$mz_hi - 453.00336) < 0.01))   # 453 (M+1) not paired
  expect_true(any(abs(net$delta - 18.01057) < 0.02))      # water loss kept

  # deisotope() on its own keeps the monoisotope, drops the satellite
  d <- deisotope(spec, iso_tol = 0.02)
  expect_true(452.0 %in% d$mz)
  expect_false(453.00336 %in% d$mz)
})

test_that("difference_network: iso_decreasing keeps a -H2 loss, else drops it", {
  skip_if_not_installed("commonMZ")
  # heavier peak (300) MORE intense than the lighter (297.984): not the isotope
  # direction, so with iso_decreasing the 2.0157 spacing is a -H2 loss, kept.
  spec <- tibble::tibble(mz = c(297.98435, 300.0), intensity = c(200, 1000))
  net_dec <- difference_network(spec, tol = 30, unit = "ppm", iso_decreasing = TRUE)
  expect_true(any(abs(net_dec$delta - 2.01565) < 0.02))
  # treat ALL isotope-spaced deltas as isotopes regardless of direction -> dropped
  net_all <- difference_network(spec, tol = 30, unit = "ppm", iso_decreasing = FALSE)
  expect_equal(nrow(net_all[abs(net_all$delta - 2.01565) < 0.02, ]), 0)
})

test_that("isotope tolerance widens the isotope-spacing match", {
  skip_if_not_installed("commonMZ")
  # spacing 2.030 is 0.0235 off 2*13C; only caught when k*iso_tol covers it
  spec <- tibble::tibble(mz = c(340.2715, 342.3017), intensity = c(600, 60))
  tight <- difference_network(spec, tol = 30, unit = "ppm", iso_tol = 0.005)
  expect_true(any(abs(tight$delta - 2.030) < 0.01))     # not skipped (tight iso tol)
  loose <- difference_network(spec, tol = 30, unit = "ppm", iso_tol = 0.02)
  expect_equal(nrow(loose[abs(loose$delta - 2.030) < 0.01, ]), 0)  # skipped
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
