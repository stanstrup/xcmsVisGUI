# mod_plot_precursors — precursor-ion map for DDA data (xcmsVis::gplotPrecursorIons).
# Plots MS2 precursor m/z vs retention time for one file. Only files that
# actually contain MS2 spectra are offered.

mod_plot_precursors_ui <- function(id) {
  ns <- NS(id)
  card(
    full_screen = TRUE,
    card_header(
      "Precursor ions (DDA)",
      div(class = "float-end", mod_export_ui(ns("export")))
    ),
    layout_sidebar(
      sidebar = sidebar(
        width = 240, position = "right", open = "open",
        selectInput(ns("file"), "File (with MS2)", choices = NULL),
        helpText("Each point is a precursor selected for fragmentation.")
      ),
      plotlyOutput(ns("plot"), height = "100%")
    )
  )
}

mod_plot_precursors_server <- function(id, rv, included) {
  moduleServer(id, function(input, output, session) {

    # Files whose summary reports an MS level > 1.
    ms2_files <- reactive({
      inc <- included()
      if (nrow(inc) == 0) return(inc)
      has2 <- vapply(strsplit(inc$ms_levels %||% "", ",\\s*"), function(v)
        any(suppressWarnings(as.integer(v)) > 1, na.rm = TRUE), logical(1))
      inc[has2, , drop = FALSE]
    })

    observe({
      f2 <- ms2_files()
      choices <- if (nrow(f2)) stats::setNames(f2$id, f2$name) else character(0)
      updateSelectInput(session, "file", choices = choices,
                        selected = isolate(input$file) %||% (choices[1] %||% NULL))
    })

    plot_gg <- reactive({
      validate(need(nrow(ms2_files()) > 0,
                    "No included file contains MS2 spectra (need DDA data)."))
      req(input$file)
      f <- rv$files[rv$files$id == input$file, ]
      req(nrow(f) == 1)
      withProgress(message = "Reading precursors…", value = 0.5, {
        df <- extract_precursors(f$path)
      })
      validate(need(nrow(df) > 0, "No precursor ions found in this file."))
      unit <- rv$settings$time_unit
      df$rt_disp <- rt_to_disp(df$rt, unit)
      df$.tip <- sprintf("precursor m/z: %.4f\nrt: %.4g %s", df$precursorMZ, df$rt_disp, unit)
      ggplot2::ggplot(df, ggplot2::aes(x = rt_disp, y = precursorMZ, text = .tip)) +
        ggplot2::geom_point(color = brewer_qual(1, rv$settings$qual_palette),
                            alpha = 0.5, size = 1.2) +
        ggplot2::labs(x = rt_axis_label(unit), y = "precursor m/z") +
        ggplot2::theme_bw()
    })

    output$plot <- renderPlotly({
      ggplotly(plot_gg(), source = "prec", tooltip = "text", dynamicTicks = FALSE)
    })

    mod_export_server("export", plot_gg, rv, "precursors")
  })
}
