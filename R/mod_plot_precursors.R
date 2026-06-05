# mod_plot_precursors — precursor-ion map (DDA) for the included MS2 files.
# Each point is a precursor selected for fragmentation. Click a point to show its
# spectrum on the Spectrum tab.

#' @importFrom plotly plotlyOutput
#' @noRd
mod_plot_precursors_ui <- function(id) {
  ns <- NS(id)
  card(
    full_screen = TRUE,
    card_header("Precursor ions (DDA)",
                div(class = "float-end", mod_export_ui(ns("export")))),
    layout_sidebar(
      sidebar = sidebar(
        width = 240, position = "right", open = "open",
        selectInput(ns("color_by"), "Color by",
                    c("File" = "sample_name", "Sample group" = "sample_group",
                      "None" = "none")),
        helpText("Uses the included files that contain MS2. Click a point to ",
                 "view its spectrum.")
      ),
      plotlyOutput(ns("plot"), height = "100%")
    )
  )
}

#' @importFrom ggplot2 ggplot aes geom_point scale_color_manual labs theme_bw
#' @importFrom plotly renderPlotly
#' @noRd
mod_plot_precursors_server <- function(id, rv, included) {
  moduleServer(id, function(input, output, session) {

    ms2_files <- reactive({
      inc <- included()
      if (nrow(inc) == 0) return(inc)
      has2 <- vapply(strsplit(inc$ms_levels %||% "", ",\\s*"), function(v)
        any(suppressWarnings(as.integer(v)) > 1, na.rm = TRUE), logical(1))
      inc[has2, , drop = FALSE]
    })

    prec_df <- reactive({
      f2 <- ms2_files()
      validate(need(nrow(f2) > 0,
                    "No included file contains MS2 spectra (need DDA data)."))
      withProgress(message = "Reading precursors…", value = 0.5, {
        extract_over_files(f2, extract_precursors,
                           cols = c("sample_id", "sample_name", "sample_group"),
                           on_error = notify_read_failures)
      })
    })

    plot_gg <- reactive({
      df <- prec_df(); validate(need(nrow(df) > 0, "No precursor ions found."))
      unit <- rv$settings$time_unit
      df$rt_disp <- rt_to_disp(df$rt, unit)
      df$.tip <- sprintf("precursor m/z: %.4f\nscan: %s\nrt: %.4g %s | %s",
                         df$precursorMZ, ifelse(is.na(df$scan), "?", df$scan),
                         df$rt_disp, unit, df$sample_name)
      cby <- input$color_by
      p <- ggplot(df, aes(x = rt_disp, y = precursorMZ,
                                            key = sample_id, text = .tip))
      if (identical(cby, "none")) {
        p <- p + geom_point(
          color = brewer_qual(1, rv$settings$qual_palette), alpha = 0.5, size = 1.2)
      } else {
        df$.color <- df[[cby]]
        p <- ggplot(df, aes(x = rt_disp, y = precursorMZ,
                                              color = .color, key = sample_id, text = .tip)) +
          geom_point(alpha = 0.5, size = 1.2) +
          scale_color_manual(
            values = brewer_named(unique(df$.color), rv$settings$qual_palette))
      }
      p + labs(x = rt_axis_label(unit), y = "precursor m/z", color = NULL) +
        theme_bw()
    })

    keep_zoom <- zoom_keeper("prec")
    output$plot <- renderPlotly(finalize_plotly(plot_gg(), "prec", keep_zoom))
    wire_selection("prec", "prec", rv, mz_from = function(ev) ev$y)

    mod_export_server("export", plot_gg, rv, "precursors")
  })
}
