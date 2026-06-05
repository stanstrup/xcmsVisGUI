# Pure-helper unit tests — no MS data, fast. Cover the small functions where
# silent breakage hides (time units, filter schema, binning, ranges, colour).

test_that("rt unit conversion round-trips", {
  expect_equal(rt_factor("min"), 60)
  expect_equal(rt_factor("sec"), 1)
  expect_equal(rt_to_disp(120, "min"), 2)
  expect_equal(rt_to_sec(2, "min"), 120)
  expect_equal(rt_to_sec(rt_to_disp(137.5, "min"), "min"), 137.5)
  expect_equal(rt_to_sec(rt_to_disp(137.5, "sec"), "sec"), 137.5)
  expect_identical(rt_axis_label("sec"), "retention time (s)")
})

test_that("empty_filter / make_filter / chrom_ms_level behave", {
  ef <- empty_filter()
  expect_identical(names(ef),
    c("rt_min","rt_max","mz_min","mz_max","ms_level","polarity","int_min",
      "int_max","spectrum_id"))
  expect_equal(ef$ms_level, 1L)
  expect_true(is.na(ef$rt_min) && is.na(ef$mz_max))

  mf <- make_filter(list(rt_min = 1.5, rt_max = NA, mz_min = 100, ms_level = "2",
                         polarity = "pos", spectrum_id = "x"), "min")
  expect_equal(mf$rt_min, 90)            # 1.5 min -> 90 s
  expect_true(is.na(mf$rt_max))
  expect_equal(mf$ms_level, 2L)
  expect_identical(mf$polarity, "pos")
  expect_identical(mf$spectrum_id, "x")
  expect_true(is.na(make_filter(list(ms_level = "all"), "min")$ms_level))

  expect_equal(chrom_ms_level(list(ms_level = 2L)), 2L)
  expect_equal(chrom_ms_level(list(ms_level = NA_integer_)), 1L)
})

test_that(".flt_mz / .flt_int compose ranges", {
  expect_equal(.flt_mz(list(mz_min = 100, mz_max = 200)), c(100, 200))
  expect_equal(.flt_mz(list(mz_min = NA, mz_max = 200)), c(0, 200))
  expect_null(.flt_int(list(int_min = NA, int_max = NA)))
  expect_equal(.flt_int(list(int_min = 5000, int_max = NA)), c(5000, Inf))
})

test_that("bin_peaks aggregates onto the grid", {
  df <- tibble::tibble(rt = c(1, 2, 11, 12), mz = c(100.1, 100.4, 100.2, 250.6),
                       intensity = c(10, 20, 5, 7))
  b <- bin_peaks(df, rt_bin = 10, mz_bin = 1, aggfun = max)
  top <- b[b$rt_b == 0 & b$mz_b == 100, ]
  expect_equal(nrow(top), 1)
  expect_equal(top$intensity, 20)
  expect_equal(nrow(bin_peaks(df[0, ], 10, 1)), 0)
})

test_that("combined_ranges unions across files", {
  fdf <- tibble::tibble(
    rt_min = c(10, 20), rt_max = c(300, 280),
    mz_min = c(100.5, 90.2), mz_max = c(900, 1000.1),
    ms_levels = c("1, 2", "1, 3"), polarities = c("1", "0, 1"),
    charges = c("1, 2", "2"))
  cr <- combined_ranges(fdf)
  expect_equal(cr$rt, c(10, 300))
  expect_equal(cr$mz, c(90.2, 1000.1))
  expect_identical(cr$ms_levels, c("1", "2", "3"))
  expect_identical(cr$charges, c(1L, 2L))
})

test_that("polarity_label maps codes", {
  expect_identical(polarity_label("0, 1"), "neg, pos")
  expect_identical(polarity_label("1"), "pos")
  expect_true(is.na(polarity_label("-1")))
})

test_that("isTRUE_vec coerces NA/char to safe logical", {
  expect_identical(isTRUE_vec(c(TRUE, NA, FALSE)), c(TRUE, FALSE, FALSE))
  expect_identical(isTRUE_vec(c("TRUE", "FALSE", NA)), c(TRUE, FALSE, FALSE))
})

test_that("palette helpers stay ColorBrewer/viridis", {
  expect_equal(length(brewer_qual(5, "Set1")), 5)
  expect_true(all(grepl("^#[0-9A-Fa-f]{6}", brewer_qual(12, "Set1"))))
  expect_identical(names(brewer_named(c("a", "b", "a"), "Set2")), c("a", "b"))
})

test_that("new_eic_target builds rows with defaults", {
  t1 <- new_eic_target(195.0877)
  expect_identical(names(t1),
    c("label","mz","tol","unit","rt_min","rt_max","enabled"))
  expect_equal(t1$tol, 10)
  expect_identical(t1$unit, "ppm")
  expect_true(t1$enabled)
  t2 <- new_eic_target(c(100, 200), tol = 5, unit = "Da")
  expect_equal(nrow(t2), 2)
  expect_equal(t2$tol, c(5, 5))
})

test_that("settings persistence round-trips on the allow-list", {
  withr::local_envvar(R_USER_CONFIG_DIR = withr::local_tempdir())
  save_settings(list(time_unit = "sec", default_tol = 20, default_tol_unit = "Da",
                     bogus = "x"))
  s <- load_settings()
  expect_identical(s$time_unit, "sec")
  expect_equal(s$default_tol, 20)
  expect_null(s$bogus)
})
