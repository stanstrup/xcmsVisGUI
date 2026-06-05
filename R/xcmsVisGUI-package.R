#' xcmsVisGUI: interactive raw LC-MS viewer (Shiny)
#'
#' A local desktop Shiny app for visualising raw LC-MS data (TIC/BPC, EICs,
#' spectra, 2D/3D MS maps, DDA precursors). Launch with [run_app()].
#'
#' Most cross-package calls are `::`-qualified (see the `fct_*` files); only the
#' functions used bare in the UI/glue code are imported here. The
#' RforMassSpectrometry stack (Spectra/MsExperiment/xcms/...) is used via `::`.
#'
#' @keywords internal
#' @import shiny
#' @import bslib
#' @import dplyr
#' @import tibble
#' @importFrom plotly plot_ly add_trace layout ggplotly renderPlotly plotlyOutput event_register event_data
#' @importFrom mirai mirai daemons everywhere
#' @importFrom xcms chromatogram
#' @importFrom magrittr %>%
#' @importFrom rlang %||%
"_PACKAGE"
