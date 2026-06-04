# Pinpoint WHERE the time goes inside Spectra/MsBackendMzR construction.
suppressWarnings(suppressMessages({ library(Spectra); library(xcms) }))
f <- "C:/Users/tmh331/Desktop/gits/Mcourse_new/data/2023/incognito_urine_A_vs_C_pos/18052015-005.mzML"

cat("sessionInfo (key pkgs):\n")
for (p in c("Spectra","MsCoreUtils","ProtGenerics","mzR","S4Vectors","BiocParallel"))
  cat(sprintf("  %-14s %s\n", p, as.character(packageVersion(p))))

rp <- tempfile(fileext = ".rprof")
Rprof(rp, interval = 0.02, line.profiling = TRUE, memory.profiling = TRUE)
sp <- Spectra(f, source = MsBackendMzR())
Rprof(NULL)
s <- summaryRprof(rp, lines = "show")

cat("\n== top by SELF time ==\n")
print(utils::head(s$by.self, 25))
cat("\n== top by TOTAL time ==\n")
print(utils::head(s$by.total, 20))
cat("\ntotal sampled time:", s$sampling.time, "s\n")
cat("DONE\n")
