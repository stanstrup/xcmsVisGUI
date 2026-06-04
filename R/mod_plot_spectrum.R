# mod_plot_spectrum — spectrum viewer. Pick a file + rt/scan, or have a click on a
# chromatogram/MS-map set them. MS level comes from the global filter.

mod_plot_spectrum_ui <- function(id) {
  ns <- NS(id)
  card(
    full_screen = TRUE,
    card_header("Spectrum", div(class = "float-end", mod_export_ui(ns("export")))),
    layout_sidebar(
      sidebar = sidebar(
        width = 240, position = "right", open = "open",
        selectInput(ns("file"), "File", choices = NULL),
        numericInput(ns("rt"), "Jump to retention time", value = NA, step = 0.1),
        numericInput(ns("scan"), "…or scan (acquisition) number", value = NA, step = 1),
        helpText("Nearest scan is shown (out-of-range scan snaps to the last). ",
                 "MS level and intensity/spectrum-id filters come from the global ",
                 "filter. Clicking a chromatogram/MS-map sets these controls.")
      ),
      plotlyOutput(ns("plot"), height = "100%")
    )
  )
}

mod_plot_spectrum_server <- function(id, rv, included) {
  moduleServer(id, function(input, output, session) {

    observe({
      inc <- included()
      choices <- if (nrow(inc)) stats::setNames(inc$id, inc$name) else character(0)
      updateSelectInput(session, "file", choices = choices,
                        selected = isolate(input$file) %||% (choices[1] %||% NULL))
    })

    sel_file <- reactive({
      req(input$file)
      f <- rv$files[rv$files$id == input$file, ]
      req(nrow(f) == 1); f
    })

    # Cap the scan box at the file's spectrum count.
    observeEvent(sel_file(), {
      n <- sel_file()$n_spectra
      if (is.finite(n)) updateNumericInput(session, "scan", max = n)
    })

    # A click sets file + rt (and clears scan so rt wins).
    observeEvent(rv$selection, {
      s <- rv$selection; req(s, s$file_id)
      if (s$file_id %in% rv$files$id) updateSelectInput(session, "file", selected = s$file_id)
      if (!is.null(s$rt) && is.finite(s$rt)) {
        updateNumericInput(session, "rt",
                           value = round(rt_to_disp(s$rt, rv$settings$time_unit), 4))
        updateNumericInput(session, "scan", value = NA)
      }
    })

    spec_df <- reactive({
      f <- sel_file()
      use_scan <- !is.null(input$scan) && is.finite(input$scan)
      rt_disp <- input$rt
      validate(need(use_scan || is.finite(rt_disp),
                    "Enter a retention time or scan number, or click a chromatogram."))
      rt_sec <- if (is.finite(rt_disp)) rt_to_sec(rt_disp, rv$settings$time_unit) else NA_real_
      withProgress(message = "Reading spectrum…", value = 0.5, {
        extract_spectrum(f$path, rt = rt_sec,
                         scan = if (use_scan) as.integer(input$scan) else NA_integer_,
                         f = rv$filter)
      })
    })

    plot_gg <- reactive({
      df <- spec_df(); req(nrow(df) > 0)
      unit <- rv$settings$time_unit
      df$.tip <- sprintf("m/z: %.4f\nint: %.3g", df$mz, df$intensity)
      ggplot2::ggplot(df, ggplot2::aes(x = mz, ymin = 0, ymax = intensity, text = .tip)) +
        ggplot2::geom_linerange(linewidth = 0.4,
                                color = brewer_qual(1, rv$settings$qual_palette)) +
        ggplot2::labs(x = "m/z", y = "intensity",
                      title = sprintf("%s — scan %s @ rt %.4g %s",
                                      sel_file()$name,
                                      if (is.na(df$scan[1])) "?" else df$scan[1],
                                      rt_to_disp(df$rt[1], unit), unit)) +
        ggplot2::theme_classic()
    })

    output$plot <- renderPlotly({
      ggplotly(plot_gg(), source = "spec", tooltip = "text", dynamicTicks = TRUE) %>%
        layout(uirevision = "spec")
    })

    mod_export_server("export", plot_gg, rv, "spectrum")
  })
}
