# mod_plot_spectrum — shows the spectrum at the retention time last clicked on a
# chromatogram (rv$selection), reading just the one scan from the source file.

mod_plot_spectrum_ui <- function(id) {
  ns <- NS(id)
  card(
    full_screen = TRUE,
    card_header(
      "Spectrum",
      div(class = "float-end", mod_export_ui(ns("export")))
    ),
    uiOutput(ns("info")),
    plotlyOutput(ns("plot"), height = "100%")
  )
}

mod_plot_spectrum_server <- function(id, rv) {
  moduleServer(id, function(input, output, session) {

    sel_file <- reactive({
      s <- rv$selection
      req(s, s$file_id)
      f <- rv$files[rv$files$id == s$file_id, ]
      req(nrow(f) == 1)
      f
    })

    spec_df <- reactive({
      s <- rv$selection; req(s)
      f <- sel_file()
      withProgress(message = "Reading spectrum…", value = 0.5, {
        extract_spectrum(f$path, rt = s$rt, ms_level = 1L)
      })
    })

    output$info <- renderUI({
      s <- rv$selection
      if (is.null(s) || is.null(s$file_id))
        return(p(class = "text-muted",
                 "Click a chromatogram trace (TIC/BPC or EIC) to show its spectrum."))
      f <- sel_file()
      tags$small(class = "text-muted",
                 sprintf("%s — nearest scan to rt %.0f s (from %s view)",
                         f$name, s$rt, s$plot))
    })

    plot_gg <- reactive({
      df <- spec_df(); req(nrow(df) > 0)
      df$.tip <- sprintf("m/z: %.4f\nint: %.3g", df$mz, df$intensity)
      ggplot2::ggplot(df, ggplot2::aes(x = mz, ymin = 0, ymax = intensity, text = .tip)) +
        ggplot2::geom_linerange(linewidth = 0.4,
                                color = brewer_qual(1, rv$settings$qual_palette)) +
        ggplot2::labs(x = "m/z", y = "intensity",
                      title = sprintf("rt %.1f s", df$rt[1])) +
        ggplot2::theme_classic()
    })

    output$plot <- renderPlotly({
      ggplotly(plot_gg(), source = "spec", tooltip = "text", dynamicTicks = TRUE)
    })

    mod_export_server("export", plot_gg, rv, "spectrum")
  })
}
