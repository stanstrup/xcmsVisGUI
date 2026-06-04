# Test viridis colorscale + 2D line-segment map construction.
suppressWarnings(suppressMessages(source("global.R")))
for (f in list.files("R", full.names = TRUE)) source(f)
cdf <- list.files(system.file("cdf", package = "faahKO"), recursive = TRUE,
                  full.names = TRUE, pattern = "CDF$")[1]
base <- list(ms_level = 1L, rt_min = NA, rt_max = NA, mz_min = NA, mz_max = NA,
             polarity = "any", int_min = NA, int_max = NA, charge = NA, spectrum_id = "")
pk <- extract_peaks(cdf, base)
pk$rt_disp <- rt_to_disp(pk$rt, "min")

for (pal in c("viridis", "magma", "turbo", "YlOrRd")) {
  cs <- brewer_colorscale(pal)
  cat(sprintf("%-8s colorscale ok: %s (%d stops)\n", pal,
              is.list(cs), length(cs)))
}

# build line-segment traces
cmax <- quantile(pk$intensity, 0.98, names = FALSE)
urt <- sort(unique(pk$rt))
nxt <- c(urt[-1], urt[length(urt)] + diff(urt)[length(urt)-1])
pk$rt1_disp <- rt_to_disp(nxt[match(pk$rt, urt)], "min")
K <- 32L; cols <- brewer_seq("viridis")(K)
pk$grp <- pmax(1L, pmin(K, ceiling(pmin(pk$intensity,cmax)/cmax*K)))
p <- plot_ly(source = "map")
for (g in sort(unique(pk$grp))) {
  d <- pk[pk$grp==g,]
  x <- as.vector(rbind(d$rt_disp, d$rt1_disp, NA)); y <- as.vector(rbind(d$mz, d$mz, NA))
  p <- add_trace(p, x=x, y=y, type="scattergl", mode="lines", line=list(color=cols[g]))
}
cat("line map plotly:", inherits(p, "plotly"), " traces:", length(unique(pk$grp)),
    " segments:", nrow(pk), "\n")
cat("MAP2 OK\n")
