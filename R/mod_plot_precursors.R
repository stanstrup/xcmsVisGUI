# mod_plot_precursors — precursor-ion map (DDA) for the included MS2 files.
# Each point is a precursor selected for fragmentation. Click a point to show its
# spectrum on the Spectrum tab.

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
        dplyr::bind_rows(lapply(seq_len(nrow(f2)), function(i) {
          d <- extract_precursors(f2$path[i])
          if (nrow(d)) {
            d$sample_id <- f2$id[i]; d$sample_name <- f2$name[i]
            d$sample_group <- f2$sample_group[i]
          }
          d
        }))
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
      p <- ggplot2::ggplot(df, ggplot2::aes(x = rt_disp, y = precursorMZ,
                                            key = sample_id, text = .tip))
      if (identical(cby, "none")) {
        p <- p + ggplot2::geom_point(
          color = brewer_qual(1, rv$settings$qual_palette), alpha = 0.5, size = 1.2)
      } else {
        df$.color <- df[[cby]]
        p <- ggplot2::ggplot(df, ggplot2::aes(x = rt_disp, y = precursorMZ,
                                              color = .color, key = sample_id, text = .tip)) +
          ggplot2::geom_point(alpha = 0.5, size = 1.2) +
          ggplot2::scale_color_manual(
            values = brewer_named(unique(df$.color), rv$settings$qual_palette))
      }
      p + ggplot2::labs(x = rt_axis_label(unit), y = "precursor m/z", color = NULL) +
        ggplot2::theme_bw()
    })

    keep_zoom <- zoom_keeper("prec")
    output$plot <- renderPlotly({
      ggplotly(plot_gg(), source = "prec", tooltip = "text", dynamicTicks = TRUE) %>%
        keep_zoom() %>%
        event_register("plotly_click") %>% event_register("plotly_relayout")
    })

    click <- reactive(suppressWarnings(event_data("plotly_click", source = "prec")))
    observeEvent(click(), {
      ev <- click(); req(ev)
      rv$selection <- list(plot = "prec", file_id = ev$key,
                           rt = rt_to_sec(ev$x, rv$settings$time_unit), mz = ev$y)
    })

    mod_export_server("export", plot_gg, rv, "precursors")
  })
}
