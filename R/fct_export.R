# Plot export. The ggplot is the source of truth, so static exports are crisp
# vectors (svg/pdf) or high-DPI raster (png) regardless of the on-screen plotly,
# and "rds" saves the ggplot object itself for further editing/replotting in R.

#' Save a ggplot to file using the user's export settings.
#' @param gg a ggplot object
#' @param file destination path
#' @param settings rv$settings list (format/width/height/units/dpi)
#' @importFrom ggplot2 ggsave
#' @importFrom grDevices cairo_pdf svg
#' @noRd
save_gg <- function(gg, file, settings) {
  fmt <- settings$export_format %||% "png"
  # "rds": save the ggplot object itself (readRDS() it to tweak/replot in R).
  if (identical(fmt, "rds")) { saveRDS(gg, file); return(invisible(file)) }
  args <- list(
    filename = file, plot = gg,
    width = settings$export_width %||% 8,
    height = settings$export_height %||% 5,
    units = settings$export_units %||% "in"
  )
  if (fmt == "png") {
    args$device <- "png"; args$dpi <- settings$export_dpi %||% 300
  } else if (fmt == "pdf") {
    args$device <- cairo_pdf
  } else if (fmt == "svg") {
    # Prefer svglite; fall back to grDevices::svg (cairo) if unavailable.
    args$device <- if (requireNamespace("svglite", quietly = TRUE)) "svg" else svg
  }
  do.call(ggsave, args)
}
