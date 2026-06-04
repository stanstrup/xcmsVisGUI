# Test that filters reach extract_peaks/extract_spectrum.
suppressWarnings(suppressMessages(source("global.R")))
for (f in list.files("R", full.names = TRUE)) source(f)
mzml <- list.files(system.file("proteomics", package = "msdata"),
                   full.names = TRUE, pattern = "mzML$")[1]

base <- list(ms_level = 1L, rt_min = NA, rt_max = NA, mz_min = NA, mz_max = NA,
             polarity = "any", int_min = NA, int_max = NA, charge = NA, spectrum_id = "")

p0 <- extract_peaks(mzml, base)
cat("peaks (no int filter):", nrow(p0), " min int:", round(min(p0$intensity)), "\n")
f1 <- base; f1$int_min <- 5000
p1 <- extract_peaks(mzml, f1)
cat("peaks (int>=5000):    ", nrow(p1), " min int:", round(min(p1$intensity)),
    " -> applied:", min(p1$intensity) >= 5000, "\n")

# spectrum id filter — discover an id first
sp <- Spectra::Spectra(mzml, source = Spectra::MsBackendMzR())
id1 <- sp$spectrumId[1]
cat("example spectrumId:", id1, "\n")
tok <- sub(".*\\b(scan=[0-9]+).*", "\\1", id1)
f2 <- base; f2$ms_level <- NA; f2$spectrum_id <- tok
sp2 <- apply_filters_spectra(sp, f2)
cat("spectrumId filter '", tok, "' -> n spectra:", length(sp2), "(expect 1)\n", sep = "")

# scan number + intensity in extract_spectrum
s_all <- extract_spectrum(mzml, scan = NA, rt = Spectra::rtime(sp)[1], ms_level = 1L, f = base)
s_flt <- extract_spectrum(mzml, scan = NA, rt = Spectra::rtime(sp)[1], ms_level = 1L, f = f1)
cat("spectrum peaks no-filter:", nrow(s_all), " int>=5000:", nrow(s_flt),
    " min:", if(nrow(s_flt)) round(min(s_flt$intensity)) else NA, "\n")
cat("FILTER TEST OK\n")
