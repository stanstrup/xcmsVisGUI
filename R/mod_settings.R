# mod_settings — backend choice, palette, async pool, export defaults.

#' @importFrom parallel detectCores
#' @noRd
mod_settings_ui <- function(id) {
  ns <- NS(id)
  layout_columns(
    col_widths = c(6, 6),
    card(
      card_header("Data reading"),
      helpText(HTML("Files are read via <code>Spectra</code>/<code>xcms</code> with ",
               "<code>BiocParallel::SerialParam()</code> registered \u2014 the default ",
               "<code>SnowParam</code> backend is ~100\u00d7 slower (see BENCHMARK.md).")),
      sliderInput(ns("daemons"), "Parallel readers (mirai daemons)",
                  min = 1, max = max(2L, detectCores()),
                  value = max(1L, detectCores() - 1L), step = 1)
    ),
    card(
      card_header("Appearance & export"),
      radioButtons(ns("time_unit"), "Retention-time unit", inline = TRUE,
                   choices = c("Minutes" = "min", "Seconds" = "sec"), selected = "min"),
      selectInput(ns("qual_palette"), "Qualitative palette (groups, EICs)",
                  choices = QUAL_PALETTES),
      selectInput(ns("seq_palette"), "Sequential palette (maps, 3D)",
                  choices = SEQ_PALETTES),
      checkboxInput(ns("invert_scale"), "Invert colour scale (light \u2192 dark)",
                    value = TRUE),
      hr(),
      helpText(strong("EIC defaults"), " \u2014 applied to new targets and the paste box."),
      layout_columns(
        col_widths = c(6, 6),
        numericInput(ns("default_tol"), "Default \u00b1 tolerance", value = 10, min = 0),
        selectInput(ns("default_tol_unit"), "Unit", choices = c("ppm", "Da"))
      ),
      hr(),
      selectInput(ns("export_format"), "Default export format",
                  choices = c("png", "svg", "pdf", "rds")),
      layout_columns(
        col_widths = c(4, 4, 4),
        numericInput(ns("export_width"),  "Width",  value = 8, min = 1),
        numericInput(ns("export_height"), "Height", value = 5, min = 1),
        selectInput(ns("export_units"),   "Units",  choices = c("in", "cm", "mm", "px"))
      ),
      numericInput(ns("export_dpi"), "DPI (png)", value = 300, min = 36, max = 1200)
    )
  )
}

#' @importFrom mirai everywhere
#' @noRd
mod_settings_server <- function(id, rv) {
  moduleServer(id, function(input, output, session) {

    # Restore persisted settings into the controls on startup; the per-field
    # observers below then propagate them into rv$settings. Runs once.
    saved <- load_settings()
    if (length(saved)) {
      if (!is.null(saved$time_unit))    updateRadioButtons(session, "time_unit", selected = saved$time_unit)
      if (!is.null(saved$qual_palette)) updateSelectInput(session, "qual_palette", selected = saved$qual_palette)
      if (!is.null(saved$seq_palette))  updateSelectInput(session, "seq_palette", selected = saved$seq_palette)
      if (!is.null(saved$invert_scale)) updateCheckboxInput(session, "invert_scale", value = saved$invert_scale)
      if (!is.null(saved$default_tol))      updateNumericInput(session, "default_tol", value = saved$default_tol)
      if (!is.null(saved$default_tol_unit)) updateSelectInput(session, "default_tol_unit", selected = saved$default_tol_unit)
      if (!is.null(saved$daemons))      updateSliderInput(session, "daemons", value = saved$daemons)
      if (!is.null(saved$export_format))updateSelectInput(session, "export_format", selected = saved$export_format)
      if (!is.null(saved$export_width)) updateNumericInput(session, "export_width", value = saved$export_width)
      if (!is.null(saved$export_height))updateNumericInput(session, "export_height", value = saved$export_height)
      if (!is.null(saved$export_units)) updateSelectInput(session, "export_units", selected = saved$export_units)
      if (!is.null(saved$export_dpi))   updateNumericInput(session, "export_dpi", value = saved$export_dpi)
    }

    # Push each control into its own rv$settings field. Per-field observers (not
    # one observe over all inputs) so changing one setting writes only that field
    # and invalidates only its consumers (rv$settings is a nested reactiveValues).
    observeEvent(input$time_unit,     rv$settings$time_unit     <- input$time_unit)
    observeEvent(input$qual_palette,  rv$settings$qual_palette  <- input$qual_palette)
    observeEvent(input$seq_palette,   rv$settings$seq_palette   <- input$seq_palette)
    observeEvent(input$invert_scale,  rv$settings$invert_scale  <- input$invert_scale)
    observeEvent(input$default_tol,      rv$settings$default_tol      <- input$default_tol)
    observeEvent(input$default_tol_unit, rv$settings$default_tol_unit <- input$default_tol_unit)
    observeEvent(input$export_format, rv$settings$export_format <- input$export_format)
    observeEvent(input$export_width,  rv$settings$export_width  <- input$export_width)
    observeEvent(input$export_height, rv$settings$export_height <- input$export_height)
    observeEvent(input$export_units,  rv$settings$export_units  <- input$export_units)
    observeEvent(input$export_dpi,    rv$settings$export_dpi    <- input$export_dpi)

    # Resize the mirai pool when the user changes the daemon count (debounced).
    daemon_n <- reactive(input$daemons) %>% debounce(800)
    observeEvent(daemon_n(), {
      req(daemon_n())
      rv$settings$daemons <- set_daemons(daemon_n())
      everywhere(suppressWarnings(requireNamespace("mzR", quietly = TRUE)))
    }, ignoreInit = TRUE)

    # Persist settings across restarts (debounced; ignoreInit so loading doesn't
    # immediately rewrite). reactiveValuesToList tracks every field.
    settings_snapshot <- reactive(reactiveValuesToList(rv$settings)) %>% debounce(1000)
    observeEvent(settings_snapshot(), save_settings(settings_snapshot()),
                 ignoreInit = TRUE)
  })
}
