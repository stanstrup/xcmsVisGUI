# Composition root: UI, server, and the exported launcher. (Formerly app.R +
# the side-effecting tail of global.R.)

#' Build the app UI (bslib page_navbar with a shared Files+Filters sidebar and
#' one nav panel per plot module).
#' @noRd
app_ui <- function() {
  page_navbar(
    title = "xcmsVisGUI",
    theme = bs_theme(version = 5, preset = "flatly"),
    id = "main_nav",
    sidebar = sidebar(
      width = 360,
      # Tighten the default bslib accordion chrome so the Files/Filters panels
      # waste less vertical space (smaller header + body padding).
      tags$style(HTML(paste0(
        ".sidebar .accordion-body{padding:0.4rem 0.6rem} ",
        ".sidebar .accordion-button{padding:0.4rem 0.75rem}"))),
      accordion(
        accordion_panel("Files", icon = icon("folder-open"), mod_ingest_ui("ingest")),
        accordion_panel("Filters", icon = icon("filter"), mod_filter_ui("filter"))
      )
    ),

    nav_panel("TIC / BPC", icon = icon("chart-area"), mod_plot_tic_bpc_ui("tic")),
    nav_panel("EIC", icon = icon("wave-square"), mod_plot_eic_ui("eic")),
    nav_panel("Spectrum", icon = icon("bars"), mod_plot_spectrum_ui("spec")),
    nav_panel("MS map", icon = icon("border-all"), mod_plot_map_ui("map")),
    nav_panel("Precursors", icon = icon("crosshairs"), mod_plot_precursors_ui("prec")),

    nav_spacer(),
    nav_panel(
      "Settings", icon = icon("gear"),
      mod_settings_ui("settings")
    )
  )
}

#' App server: builds the central reactive graph (included files -> data_key ->
#' raw_msexp (cached) -> dataset) and wires it into every module.
#' @importFrom tibble tibble
#' @noRd
app_server <- function(input, output, session) {
  rv <- make_rv()

  mod_settings_server("settings", rv)
  mod_ingest_server("ingest", rv)

  # Included, successfully-read files.
  included <- reactive({
    f <- rv$files
    f[f$include & f$status == "ready", , drop = FALSE]
  })

  mod_filter_server("filter", rv, included)

  # Cache key for extraction reactives: only the included PATH SET and the
  # global filter should trigger re-extraction (not status/group edits).
  data_key <- reactive(list(paths = sort(included()$path), filter = rv$filter))

  # Raw MsExperiment cached on the path set (built under SerialParam, so fast);
  # the global filter is applied lazily on top. Kept in the in-memory SESSION
  # cache — the MsExperiment is an S4 object with a file-backed backend, not
  # worth disk-serialising (unlike the tibble results from chrom_df / eic_df,
  # which use the default app-level disk cache set in setup_runtime()).
  raw_msexp <- reactive({
    inc <- included()
    validate(need(nrow(inc) > 0, "Add files and tick at least one to include."))
    build_msexp(inc)
  }) %>% bindCache(sort(included()$path), cache = "session")

  dataset <- reactive({
    x <- raw_msexp()           # force here so validate() surfaces cleanly
    apply_filters(x, rv$filter)
  })
  meta <- reactive({
    inc <- included()
    tibble(id = inc$id, name = inc$name, path = inc$path,
           sample_group = inc$sample_group)
  })

  mod_plot_tic_bpc_server("tic", rv, dataset, meta, data_key)
  mod_plot_eic_server("eic", rv, dataset, meta, data_key)
  mod_plot_spectrum_server("spec", rv, included)
  mod_plot_map_server("map", rv, included)
  mod_plot_precursors_server("prec", rv, included)
}

#' Launch xcmsVisGUI.
#'
#' Performs the one-time runtime setup (mirai daemon pool, large-upload option;
#' SerialParam is registered on package load) and starts the Shiny app. The
#' daemon pool is torn down when the app stops.
#'
#' @param ... passed to [shiny::runApp()] (e.g. `port`, `launch.browser`).
#' @return Invisibly, the result of [shiny::runApp()].
#' @export
#' @importFrom mirai daemons
#' @examples
#' if (interactive()) run_app()
run_app <- function(...) {
  setup_runtime()
  on.exit(try(daemons(0), silent = TRUE), add = TRUE)
  runApp(shinyApp(app_ui(), app_server), ...)
}
