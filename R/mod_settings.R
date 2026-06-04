# mod_settings — backend choice, palette, async pool, export defaults.

mod_settings_ui <- function(id) {
  ns <- NS(id)
  layout_columns(
    col_widths = c(6, 6),
    card(
      card_header("Data reading"),
      helpText(HTML("Files are read via <code>Spectra</code>/<code>xcms</code> with ",
               "<code>BiocParallel::SerialParam()</code> registered — the default ",
               "<code>SnowParam</code> backend is ~100× slower (see BENCHMARK.md).")),
      sliderInput(ns("daemons"), "Parallel readers (mirai daemons)",
                  min = 1, max = max(2L, parallel::detectCores()),
                  value = max(1L, parallel::detectCores() - 1L), step = 1)
    ),
    card(
      card_header("Appearance & export"),
      radioButtons(ns("time_unit"), "Retention-time unit", inline = TRUE,
                   choices = c("Minutes" = "min", "Seconds" = "sec"), selected = "min"),
      selectInput(ns("qual_palette"), "Qualitative palette (groups, EICs)",
                  choices = QUAL_PALETTES),
      selectInput(ns("seq_palette"), "Sequential palette (maps, 3D)",
                  choices = SEQ_PALETTES),
      checkboxInput(ns("invert_scale"), "Invert colour scale (light → dark)",
                    value = TRUE),
      hr(),
      selectInput(ns("export_format"), "Default export format",
                  choices = c("png", "svg", "pdf")),
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

mod_settings_server <- function(id, rv) {
  moduleServer(id, function(input, output, session) {

    # Push every control into rv$settings so other modules react to changes.
    observe({
      rv$settings$time_unit     <- input$time_unit
      rv$settings$qual_palette  <- input$qual_palette
      rv$settings$seq_palette   <- input$seq_palette
      rv$settings$invert_scale  <- input$invert_scale
      rv$settings$export_format <- input$export_format
      rv$settings$export_width  <- input$export_width
      rv$settings$export_height <- input$export_height
      rv$settings$export_units  <- input$export_units
      rv$settings$export_dpi    <- input$export_dpi
    })

    # Resize the mirai pool when the user changes the daemon count (debounced).
    daemon_n <- reactive(input$daemons) %>% debounce(800)
    observeEvent(daemon_n(), {
      req(daemon_n())
      rv$settings$daemons <- set_daemons(daemon_n())
      mirai::everywhere(suppressPackageStartupMessages(library(mzR)))
    }, ignoreInit = TRUE)
  })
}
