# ColorBrewer palette helpers (user preference: ColorBrewer everywhere).

#' Build a vector of n distinct qualitative colors from a ColorBrewer palette,
#' interpolating when n exceeds the palette's native size.
#' @param n number of colors needed
#' @param palette a qualitative ColorBrewer palette name (e.g. "Set1")
#' @importFrom RColorBrewer brewer.pal.info brewer.pal
#' @importFrom grDevices colorRampPalette
#' @noRd
brewer_qual <- function(n, palette = "Set1") {
  if (n < 1) return(character(0))
  max_n <- brewer.pal.info[palette, "maxcolors"]
  if (is.na(max_n)) {
    palette <- "Set1"
    max_n <- brewer.pal.info[palette, "maxcolors"]
  }
  if (n <= max_n) {
    cols <- brewer.pal(max(3L, n), palette)
    return(cols[seq_len(n)])
  }
  colorRampPalette(brewer.pal(max_n, palette))(n)
}

#' A sequential ColorBrewer ramp function for continuous fills (heatmaps/3D).
#' @param palette a sequential ColorBrewer name OR a viridisLite option
#'   (viridis/magma/plasma/inferno/cividis/mako/rocket/turbo)
#' @param invert reverse the scale (so it runs light -> dark)
#' @importFrom viridisLite viridis
#' @importFrom RColorBrewer brewer.pal
#' @importFrom grDevices colorRampPalette
#' @noRd
brewer_seq <- function(palette = "YlOrRd", invert = FALSE) {
  base_fun <- if (palette %in% VIRIDIS_PALETTES)
    function(n) viridis(n, option = palette)
  else {
    base <- tryCatch(brewer.pal(9, palette),
                     error = function(e) brewer.pal(9, "YlOrRd"))
    colorRampPalette(base)
  }
  function(n) { cols <- base_fun(n); if (invert) rev(cols) else cols }
}

#' Named color vector mapping the levels of a grouping variable to brewer colors.
#' @importFrom stats setNames
#' @noRd
brewer_named <- function(levels, palette = "Set1") {
  levels <- unique(as.character(levels))
  setNames(brewer_qual(length(levels), palette), levels)
}

#' A plotly colorscale (list of [position, color]) from a sequential palette.
#' @noRd
brewer_colorscale <- function(palette = "YlOrRd", n = 9, invert = FALSE) {
  cols <- brewer_seq(palette, invert)(n)
  lapply(seq_len(n), function(i) list((i - 1) / (n - 1), cols[i]))
}
