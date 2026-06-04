# xcmsVisGUI — local desktop raw LC-MS viewer.
# Entry point. Shiny auto-sources R/*.R but NOT global.R for app.R-style apps,
# so we source it explicitly before building the UI.
source("global.R")

ui <- page_navbar(
  title = "xcmsVisGUI",
  theme = bs_theme(version = 5, preset = "flatly"),
  id = "main_nav",
  sidebar = sidebar(
    width = 360,
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
  ),

  header = useShinyjs()
)

server <- function(input, output, session) {
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
  # the global filter is applied lazily on top.
  raw_msexp <- reactive({
    inc <- included()
    validate(need(nrow(inc) > 0, "Add files and tick at least one to include."))
    build_msexp(inc)
  }) %>% bindCache(sort(included()$path))

  dataset <- reactive({
    x <- raw_msexp()           # force here so validate() surfaces cleanly
    apply_filters(x, rv$filter)
  })
  meta <- reactive({
    inc <- included()
    tibble::tibble(id = inc$id, name = inc$name, sample_group = inc$sample_group)
  })

  mod_plot_tic_bpc_server("tic", rv, dataset, meta, data_key)
  mod_plot_eic_server("eic", rv, dataset, meta, data_key)
  mod_plot_spectrum_server("spec", rv, included)
  mod_plot_map_server("map", rv, included)
  mod_plot_precursors_server("prec", rv, included)
}

shinyApp(ui, server)
