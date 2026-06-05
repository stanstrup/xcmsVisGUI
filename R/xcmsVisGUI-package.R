#' xcmsVisGUI: interactive raw LC-MS viewer (Shiny)
#'
#' A local desktop Shiny app for visualising raw LC-MS data (TIC/BPC, EICs,
#' spectra, 2D/3D MS maps, DDA precursors). Launch with [run_app()].
#'
#' Import policy: every used function is declared with a per-function
#' `@importFrom` so the code calls bare names. Two deliberate exceptions:
#'   * `shiny` and `bslib` are imported whole (`@import`) — they are the UI
#'     framework used in essentially every function and have no conflicts with
#'     our other imports; enumerating them per function adds noise, not safety.
#'   * the RforMassSpectrometry S4 stack (Spectra/xcms/MsExperiment/BiocParallel/
#'     mzR) is called with `::`. Those packages export many overlapping generics
#'     (`rtime`, `intensity`, `mz`, `filterMsLevel`, `spectra`, ...) and some
#'     collide with base (`close`, `filter`); `::` keeps the intended method
#'     source explicit and dispatch unambiguous — the "unresolvable conflict" case.
#' `%>%` (magrittr) and `%||%` (rlang) are imported here once as operators.
#'
#' @keywords internal
#' @import shiny
#' @import bslib
#' @importFrom magrittr %>%
#' @importFrom rlang %||%
#' @importFrom utils globalVariables
"_PACKAGE"

# Quiet R CMD check's "no visible binding" NOTE for the non-standard-evaluation
# column names used by dplyr/ggplot2 aes() in the plot modules.
globalVariables(c(
  ".color", ".tip", "intensity", "mz", "mz_b", "precursorMZ", "rt_b", "rt_disp",
  "sample_id", "sample_name", "target", "y0", "y1"))
