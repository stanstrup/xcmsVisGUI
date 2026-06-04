# Test the merged map module's plot construction on real data.
suppressWarnings(suppressMessages(source("global.R")))
for (f in list.files("R", full.names = TRUE)) source(f)
cdf <- list.files(system.file("cdf", package = "faahKO"), recursive = TRUE,
                  full.names = TRUE, pattern = "CDF$")[1]
pk <- extract_peaks(cdf)
pk$rt_disp <- rt_to_disp(pk$rt, "min")
cs <- brewer_colorscale("YlOrRd")

# 2D map (scattergl)
cmax <- quantile(pk$intensity, 0.98, names = FALSE)
p2 <- plot_ly(pk[order(-pk$intensity)[1:min(nrow(pk),50000)], ], x=~rt_disp, y=~mz,
              type="scattergl", mode="markers",
              marker=list(size=3, color=~intensity, colorscale=cs, cmin=0, cmax=cmax))
cat("2D map plotly:", inherits(p2, "plotly"), "\n")

# surface
b <- bin_peaks(pk, 10, 1, max); b$rt_disp <- rt_to_disp(b$rt_b, "min")
rt_ax <- sort(unique(b$rt_disp)); mz_ax <- sort(unique(b$mz_b))
z <- matrix(0, length(mz_ax), length(rt_ax)); z[cbind(match(b$mz_b,mz_ax), match(b$rt_disp,rt_ax))] <- b$intensity
ps <- plot_ly(x=rt_ax, y=mz_ax, z=z, type="surface", colorscale=cs)
cat("surface plotly:", inherits(ps, "plotly"), " matrix:", nrow(z), "x", ncol(z), "\n")

# precursors on an MS2 file
mzml <- list.files(system.file("proteomics", package="msdata"), full.names=TRUE, pattern="mzML$")[1]
pr <- extract_precursors(mzml)
cat("precursors:", nrow(pr), " mz range:", paste(round(range(pr$precursorMZ),1),collapse="-"), "\n")
cat("MAP TEST OK\n")
