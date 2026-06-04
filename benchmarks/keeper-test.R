# Validate the Spectra+SerialParam app data layer on the real urine files,
# including the mirai worker read path.
suppressWarnings(suppressMessages(source("global.R")))
for (f in list.files("R", full.names = TRUE)) source(f)

d <- "C:/Users/tmh331/Desktop/gits/Mcourse_new/data/2023/incognito_urine_A_vs_C_pos"
files <- list.files(d, pattern = "mzML$", full.names = TRUE)[1:2]
files_df <- tibble::tibble(id = c("f1","f2"), path = files,
                           name = basename(files), sample_group = c("A","C"))
meta <- files_df[, c("id","name","sample_group")]
flt <- list(ms_level = 1L, rt_min = NA_real_, rt_max = NA_real_, mz_min = NA_real_,
            mz_max = NA_real_, polarity = "any", int_min = NA_real_)
tm <- function(l, e) { t <- system.time(v <- force(e))["elapsed"]
  cat(sprintf("%-38s %6.2f s\n", l, t)); invisible(v) }

cat("main-process bpparam:", class(BiocParallel::bpparam())[1], "\n\n")

# Worker read path (mirai + mzR header summary)
m <- mirai::mirai(read_ms_header(p), read_ms_header = read_ms_header, p = files[1])
tm("worker read_ms_header (mirai)", m[])

# Main-process Spectra/xcms path
x   <- tm("build_msexp x2", build_msexp(files_df))
xf  <- tm("apply_filters", apply_filters(x, flt))
tic <- tm("chromatogram TIC + tidy",
          chrom_to_df(chromatogram(xf, aggregationFun = "sum"), meta, "TIC"))
eic <- tm("chromatogram EIC 3mz + tidy",
          chrom_to_df(chromatogram(xf, mz = rbind(c(100,100.02),c(200,200.02),c(300,300.02))),
                      meta, c("a","b","c")))
tm("extract_peaks 1 file", extract_peaks(files[1]))
tm("extract_spectrum", extract_spectrum(files[1], 200, 1L))

cat("\nTIC rows:", nrow(tic), " EIC rows:", nrow(eic), "\n")
mirai::daemons(0)
cat("KEEPER OK\n")
