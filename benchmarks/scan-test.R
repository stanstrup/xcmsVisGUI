suppressWarnings(suppressMessages(source("global.R")))
for (f in list.files("R", full.names = TRUE)) source(f)
cdf <- list.files(system.file("cdf", package = "faahKO"), recursive = TRUE,
                  full.names = TRUE, pattern = "CDF$")[1]
fdf <- tibble::tibble(id = "x", path = cdf, name = basename(cdf), sample_group = "g")
meta <- fdf[, c("id","name","path","sample_group")]
x <- apply_filters(build_msexp(fdf), list(ms_level=1L, rt_min=NA, rt_max=NA, mz_min=NA,
     mz_max=NA, polarity="any", int_min=NA, int_max=NA, charge=NA, spectrum_id=""))
df <- add_scan_numbers(chrom_to_df(chromatogram(x, aggregationFun="sum"), meta, "TIC"), meta)
cat("TIC rows:", nrow(df), " scans matched:", sum(!is.na(df$scan)),
    " range:", paste(range(df$scan, na.rm=TRUE), collapse="-"), "\n")
cat("SCAN TEST OK\n")
