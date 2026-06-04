# Validate the SPECTRA_ISSUE.md reprex.
suppressWarnings(suppressMessages({ library(Spectra); library(BiocParallel) }))
f <- system.file("sciex/20171016_POOL_POS_1_105-134.mzML", package = "msdata")
cat("file exists:", nzchar(f) && file.exists(f), "->", basename(f), "\n")

register(SnowParam(workers = 4))
cat("SnowParam(4): ", system.time(Spectra(f, source = MsBackendMzR()))["elapsed"], "s\n")
register(SerialParam())
cat("SerialParam : ", system.time(Spectra(f, source = MsBackendMzR()))["elapsed"], "s\n")
