# mod_plot_msmap — 2D rt x m/z intensity heatmap for one file.
# Respects the global rt/mz/MS-level filter; sequential ColorBrewer fill.
# Click a cell to load the spectrum at that retention time.

mod_plot_msmap_ui <- function(id) {
  ns <- NS(id)
  card(
    full_screen = TRUE,
    card_header(
      "2D MS map",
      div(class = "float-end", mod_export_ui(ns("export")))
    ),
    layout_sidebar(
      sidebar = sidebar(
        width = 240, position = "right", open = "open",
        selectInput(ns("file"), "File", choices = NULL),
        numericInput(ns("rt_bin"), "rt bin (s)", value = 10, min = 1),
        numericInput(ns("mz_bin"), "m/z bin", value = 1, min = 0.01, step = 0.1),
        selectInput(ns("agg"), "Aggregate", c("max", "sum")),
        checkboxInput(ns("logc"), "log10 intensity", value = TRUE),
        helpText("Click a cell to show its spectrum.")
      ),
      plotlyOutput(ns("plot"), height = "100%")
    )
  )
}

mod_plot_msmap_server <- function(id, rv, included) {
  moduleServer(id, function(input, output, session) {

    observe({
      inc <- included()
      choices <- stats::setNames(inc$id, inc$name)
      updateSelectInput(session, "file", choices = choices,
                        selected = isolate(input$file) %||% choices[1])
    })

    sel_file <- reactive({
      req(input$file)
      f <- rv$files[rv$files$id == input$file, ]
      req(nrow(f) == 1); f
    })

    # Peaks come from the mzR cache; the filter is applied inside compute_peaks.
    peaks <- reactive({
      f <- sel_file()
      withProgress(message = "Reading peaks…", value = 0.5, {
        compute_peaks(f$path, rv$filter)
      })
    }) %>% bindCache(input$file, rv$filter)

    binned <- reactive({
      df <- peaks()
      validate(need(nrow(df) > 0, "No peaks in the current filter range."))
      aggfun <- if (input$agg == "sum") sum else max
      bin_peaks(df, rt_bin = input$rt_bin, mz_bin = input$mz_bin, aggfun = aggfun)
    })

    plot_gg <- reactive({
      b <- binned(); req(nrow(b) > 0)
      b$fill_val <- if (isTRUE(input$logc)) log10(b$intensity + 1) else b$intensity
      b$.tip <- sprintf("rt: %.0f s\nm/z: %.3f\nint: %.3g", b$rt_b, b$mz_b, b$intensity)
      ggplot2::ggplot(b, ggplot2::aes(x = rt_b, y = mz_b, fill = fill_val,
                                      key = rt_b, text = .tip)) +
        ggplot2::geom_tile(width = input$rt_bin, height = input$mz_bin) +
        ggplot2::scale_fill_gradientn(
          colours = brewer_seq(rv$settings$seq_palette)(9)) +
        ggplot2::labs(x = "retention time (s)", y = "m/z",
                      fill = if (isTRUE(input$logc)) "log10 int" else "int") +
        ggplot2::theme_bw()
    })

    output$plot <- renderPlotly({
      ggplotly(plot_gg(), source = "msmap", tooltip = "text", dynamicTicks = TRUE) %>%
        event_register("plotly_click")
    })

    click <- reactive(suppressWarnings(event_data("plotly_click", source = "msmap")))
    observeEvent(click(), {
      ev <- click(); req(ev)
      rv$selection <- list(plot = "msmap", file_id = input$file,
                           rt = ev$x, mz = ev$y)
    })

    mod_export_server("export", plot_gg, rv, "msmap")
  })
}
