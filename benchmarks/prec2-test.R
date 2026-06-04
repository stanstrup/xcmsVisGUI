suppressWarnings(suppressMessages(source("global.R")))
for (f in list.files("R", full.names = TRUE)) source(f)
mzml <- list.files(system.file("proteomics", package = "msdata"), full.names=TRUE, pattern="mzML$")[1]
pr <- extract_precursors(mzml)
cat("precursors:", nrow(pr), " has scan col:", "scan" %in% names(pr),
    " scan range:", paste(range(pr$scan, na.rm=TRUE), collapse="-"), "\n")
st <- file_scan_table(mzml)
cat("scan table cols:", paste(names(st), collapse=","), "\n")
cat("example spectrumId:", st$spectrumId[1], "\n")
cat("PREC2 OK\n")
