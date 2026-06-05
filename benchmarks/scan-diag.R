suppressWarnings(suppressMessages(source("global.R")))
for (f in list.files("R", full.names = TRUE)) source(f)
p <- normalizePath(list.files(system.file("proteomics", package = "msdata"),
                              full.names = TRUE, pattern = "mzML$")[1])
st <- file_scan_table(p)
cat("ROWS", nrow(st), "ACQRANGE", min(st$scan), max(st$scan),
    "MS1", sum(st$msLevel == 1), "MS2", sum(st$msLevel == 2), "\n")
flt <- list(ms_level = 1L, rt_min = NA_real_, rt_max = NA_real_, mz_min = NA_real_,
            mz_max = NA_real_, polarity = "any", int_min = NA_real_,
            int_max = NA_real_, spectrum_id = "")

# 1) Pick an MS2 scan while global filter = MS1 (the reported bug).
ms2scan <- st$scan[st$msLevel == 2][3]
d <- extract_spectrum(p, rt = NA_real_, scan = as.integer(ms2scan), f = flt)
cat("MS2-pick:  WANT", ms2scan, "GOT", d$scan[1],
    if (identical(as.integer(d$scan[1]), as.integer(ms2scan))) "OK\n" else "WRONG\n")

# 2) Pick an MS1 scan (matches the filter).
ms1scan <- st$scan[st$msLevel == 1][5]
d <- extract_spectrum(p, rt = NA_real_, scan = as.integer(ms1scan), f = flt)
cat("MS1-pick:  WANT", ms1scan, "GOT", d$scan[1],
    if (identical(as.integer(d$scan[1]), as.integer(ms1scan))) "OK\n" else "WRONG\n")

# 3) rt-based selection still respects the ms_level filter (nearest MS1 to rt).
rt_target <- st$rt[st$msLevel == 1][10]
d <- extract_spectrum(p, rt = rt_target, scan = NA_integer_, f = flt)
exp_scan <- st$scan[st$msLevel == 1][10]
cat("rt-pick:   WANT", exp_scan, "GOT", d$scan[1],
    if (identical(as.integer(d$scan[1]), as.integer(exp_scan))) "OK\n" else "WRONG\n")

mirai::daemons(0)
