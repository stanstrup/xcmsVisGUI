# mod_plot_spectrum — spectrum viewer. Works independently (pick a file + rt) and
# is also driven by clicks on a chromatogram/MS-map (which set the controls).

mod_plot_spectrum_ui <- function(id) {
  ns <- NS(id)
  card(
    full_screen = TRUE,
    card_header(
      "Spectrum",
      div(class = "float-end", mod_export_ui(ns("export")))
    ),
    layout_sidebar(
      sidebar = sidebar(
        width = 240, position = "right", open = "open",
        selectInput(ns("file"), "File", choices = NULL),
        selectInput(ns("ms_level"), "MS level", choices = c(1), selected = 1),
        numericInput(ns("rt"), "Jump to retention time", value = NA, step = 0.1),
        helpText("Shows the nearest scan. Clicking a chromatogram or MS-map ",
                 "point sets these controls automatically.")
      ),
      plotlyOutput(ns("plot"), height = "100%")
    )
  )
}

mod_plot_spectrum_server <- function(id, rv, included) {
  moduleServer(id, function(input, output, session) {

    # Keep the file choices in sync with included files.
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

    # MS-level choices follow the selected file.
    observeEvent(sel_file(), {
      lv <- strsplit(sel_file()$ms_levels %||% "1", ",\\s*")[[1]]
      lv <- lv[nzchar(lv)]; if (!length(lv)) lv <- "1"
      updateSelectInput(session, "ms_level", choices = lv,
                        selected = isolate(input$ms_level) %||% lv[1])
    })

    # A click anywhere sets the controls (file + rt in display unit).
    observeEvent(rv$selection, {
      s <- rv$selection; req(s, s$file_id)
      if (s$file_id %in% rv$files$id)
        updateSelectInput(session, "file", selected = s$file_id)
      if (!is.null(s$rt) && is.finite(s$rt))
        updateNumericInput(session, "rt", value = round(rt_to_disp(s$rt, rv$settings$time_unit), 4))
    })

    spec_df <- reactive({
      f <- sel_file()
      rt_disp <- input$rt
      validate(need(is.finite(rt_disp), "Enter a retention time, or click a chromatogram."))
      rt_sec <- rt_to_sec(rt_disp, rv$settings$time_unit)
      ms <- as.integer(input$ms_level %||% 1L)
      withProgress(message = "Reading spectrum…", value = 0.5, {
        extract_spectrum(f$path, rt = rt_sec, ms_level = ms)
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
                      title = sprintf("%s — scan at rt %.4g %s",
                                      sel_file()$name, rt_to_disp(df$rt[1], unit), unit)) +
        ggplot2::theme_classic()
    })

    output$plot <- renderPlotly({
      ggplotly(plot_gg(), source = "spec", tooltip = "text", dynamicTicks = TRUE)
    })

    mod_export_server("export", plot_gg, rv, "spectrum")
  })
}
