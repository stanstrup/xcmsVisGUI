# Pure-helper unit tests — no MS data, fast. Covers the small functions where
# silent breakage hides (time units, filter schema, binning, range hints, colour).

# --- rt unit conversion (global.R) ----------------------------------------
expect_equal(rt_factor("min"), 60, "rt_factor min = 60")
expect_equal(rt_factor("sec"), 1, "rt_factor sec = 1")
expect_equal(rt_to_disp(120, "min"), 2, "120 s = 2 min")
expect_equal(rt_to_sec(2, "min"), 120, "2 min = 120 s")
expect_equal(rt_to_sec(rt_to_disp(137.5, "min"), "min"), 137.5, "min round-trip")
expect_equal(rt_to_sec(rt_to_disp(137.5, "sec"), "sec"), 137.5, "sec round-trip")
expect_identical(rt_axis_label("sec"), "retention time (s)", "sec axis label")

# --- filter schema (fct_filters.R) ----------------------------------------
ef <- empty_filter()
expect_identical(names(ef),
  c("rt_min","rt_max","mz_min","mz_max","ms_level","polarity","int_min",
    "int_max","spectrum_id"), "empty_filter field names")
expect_equal(ef$ms_level, 1L, "empty_filter defaults to MS1")
expect(is.na(ef$rt_min) && is.na(ef$mz_max), "empty_filter ranges are NA")

mf <- make_filter(list(rt_min = 1.5, rt_max = NA, mz_min = 100, ms_level = "2",
                       polarity = "pos", spectrum_id = "x"), "min")
expect_equal(mf$rt_min, 90, "make_filter converts rt 1.5 min -> 90 s")
expect(is.na(mf$rt_max), "make_filter blank rt_max -> NA")
expect_equal(mf$ms_level, 2L, "make_filter ms_level '2' -> 2L")
expect_identical(mf$polarity, "pos", "make_filter keeps polarity")
expect_identical(mf$spectrum_id, "x", "make_filter keeps spectrum_id")
expect(is.na(make_filter(list(ms_level = "all"), "min")$ms_level),
       "make_filter ms_level 'all' -> NA")

expect_equal(chrom_ms_level(list(ms_level = 2L)), 2L, "chrom_ms_level set")
expect_equal(chrom_ms_level(list(ms_level = NA_integer_)), 1L, "chrom_ms_level unset -> 1")

# --- .flt_mz / .flt_int (fct_filters.R) -----------------------------------
expect_equal(.flt_mz(list(mz_min = 100, mz_max = 200)), c(100, 200), ".flt_mz both")
expect_equal(.flt_mz(list(mz_min = NA, mz_max = 200)), c(0, 200), ".flt_mz open low")
expect(is.null(.flt_int(list(int_min = NA, int_max = NA))), ".flt_int none -> NULL")
expect_equal(.flt_int(list(int_min = 5000, int_max = NA)), c(5000, Inf), ".flt_int min only")

# --- bin_peaks (fct_extract.R) --------------------------------------------
df <- tibble::tibble(rt = c(1, 2, 11, 12), mz = c(100.1, 100.4, 100.2, 250.6),
                     intensity = c(10, 20, 5, 7))
b <- bin_peaks(df, rt_bin = 10, mz_bin = 1, aggfun = max)
# rt 1,2 -> bin 0; 11,12 -> bin 10; mz ~100 -> 100, 250.6 -> 251
top <- b[b$rt_b == 0 & b$mz_b == 100, ]
expect_equal(nrow(top), 1, "bin_peaks aggregates rt 1,2 / mz 100 into one cell")
expect_equal(top$intensity, 20, "bin_peaks aggfun=max picks 20")
expect_equal(nrow(bin_peaks(df[0, ], 10, 1)), 0, "bin_peaks empty in -> empty out")

# --- combined_ranges (fct_filters.R) --------------------------------------
fdf <- tibble::tibble(
  rt_min = c(10, 20), rt_max = c(300, 280),
  mz_min = c(100.5, 90.2), mz_max = c(900, 1000.1),
  ms_levels = c("1, 2", "1, 3"), polarities = c("1", "0, 1"),
  charges = c("1, 2", "2"))
cr <- combined_ranges(fdf)
expect_equal(cr$rt, c(10, 300), "combined_ranges rt span")
expect_equal(cr$mz, c(90.2, 1000.1), "combined_ranges mz span")
expect_identical(cr$ms_levels, c("1", "2", "3"), "combined_ranges ms levels union")
expect_identical(cr$charges, c(1L, 2L), "combined_ranges charges union")

# --- polarity_label (fct_extract.R) ---------------------------------------
expect_identical(polarity_label("0, 1"), "neg, pos", "polarity 0,1 -> neg, pos")
expect_identical(polarity_label("1"), "pos", "polarity 1 -> pos")
expect(is.na(polarity_label("-1")), "polarity -1 -> NA")

# --- isTRUE_vec (mod_plot_eic.R) ------------------------------------------
expect_identical(isTRUE_vec(c(TRUE, NA, FALSE)), c(TRUE, FALSE, FALSE), "isTRUE_vec NA->FALSE")
expect_identical(isTRUE_vec(c("TRUE", "FALSE", NA)), c(TRUE, FALSE, FALSE), "isTRUE_vec chars")

# --- palettes (fct_palettes.R) — ColorBrewer/viridis only -----------------
expect_equal(length(brewer_qual(5, "Set1")), 5, "brewer_qual returns n colours")
expect(all(grepl("^#[0-9A-Fa-f]{6}", brewer_qual(12, "Set1"))),
       "brewer_qual interpolates valid hex beyond palette size")
pn <- brewer_named(c("a", "b", "a"), "Set2")
expect_identical(names(pn), c("a", "b"), "brewer_named keys = unique levels")
