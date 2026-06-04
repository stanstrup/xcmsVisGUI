# Verify the full Spectra/xcms path is fast under SerialParam.
suppressWarnings(suppressMessages({
  library(Spectra); library(MsExperiment); library(xcms); library(BiocParallel)
}))
f <- "C:/Users/tmh331/Desktop/gits/Mcourse_new/data/2023/incognito_urine_A_vs_C_pos/18052015-005.mzML"
tm <- function(l, e) { t <- system.time(v <- force(e))["elapsed"]
  cat(sprintf("%-44s %7.2f s\n", l, t)); invisible(v) }

cat("default bpparam class:", class(bpparam())[1],
    " workers:", tryCatch(bpnworkers(bpparam()), error=function(e) NA), "\n\n")

register(SerialParam())
sp  <- tm("Spectra() [SerialParam]", Spectra(f, source = MsBackendMzR()))
xe  <- tm("readMsExperiment() [SerialParam]",
          readMsExperiment(spectraFiles = f, BPPARAM = SerialParam()))
tm("chromatogram() TIC [SerialParam]",
   chromatogram(xe, aggregationFun = "sum", BPPARAM = SerialParam()))
tm("chromatogram() EIC [SerialParam]",
   chromatogram(xe, mz = rbind(c(300.1, 300.2)), BPPARAM = SerialParam()))
cat("DONE\n")
