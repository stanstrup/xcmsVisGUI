# mod_plot_tic_bpc — TIC/BPC overlay of included files, colored by metadata.
# Click a trace to load that scan's spectrum (rv$selection).

mod_plot_tic_bpc_ui <- function(id) {
  ns <- NS(id)
  card(
    full_screen = TRUE,
    card_header(
      "Total / base-peak chromatograms",
      div(class = "float-end", mod_export_ui(ns("export")))
    ),
    layout_sidebar(
      sidebar = sidebar(
        width = 230, position = "right", open = "open",
        radioButtons(ns("agg"), "Chromatogram",
                     c("TIC (sum)" = "sum", "BPC (max)" = "max")),
        selectInput(ns("color_by"), "Color by",
                    c("Sample group" = "sample_group", "Sample" = "sample_name")),
        helpText("Click a trace to show its spectrum on the Spectrum tab.")
      ),
      plotlyOutput(ns("plot"), height = "100%")
    )
  )
}

mod_plot_tic_bpc_server <- function(id, rv, dataset, meta, data_key) {
  moduleServer(id, function(input, output, session) {

    chrom_label <- reactive(if (input$agg == "sum") "TIC" else "BPC")

    # TIC/BPC via xcms::chromatogram (fast under SerialParam), cached on
    # (path set + filter + aggregation) so group/color changes never re-extract.
    chrom_df <- reactive({
      x <- dataset(); req(x)
      withProgress(message = "Extracting chromatograms…", value = 0.5, {
        chr <- chromatogram(x, aggregationFun = input$agg, msLevel = 1L)
        chrom_to_df(chr, meta(), labels = chrom_label())
      })
    }) %>% bindCache(data_key(), input$agg)

    # The ggplot (source of truth for export).
    plot_gg <- reactive({
      df <- chrom_df(); req(nrow(df) > 0)
      # Refresh group labels from current metadata (cheap) so renaming a group
      # recolors without re-extracting.
      m <- meta()
      df$sample_group <- m$sample_group[match(df$sample_id, m$id)]
      cby <- input$color_by
      lvls <- unique(df[[cby]])
      pal <- brewer_named(lvls, rv$settings$qual_palette)
      df$.color <- df[[cby]]
      df$.tip <- sprintf("%s\nrt: %.0f s\nint: %.3g",
                         df$sample_name, df$rt, df$intensity)
      ggplot2::ggplot(df, ggplot2::aes(
        x = rt, y = intensity, group = sample_id, color = .color,
        key = sample_id, text = .tip)) +
        ggplot2::geom_line(linewidth = 0.5) +
        ggplot2::scale_color_manual(values = pal) +
        ggplot2::labs(x = "retention time (s)", y = "intensity",
                      color = NULL,
                      title = paste0(chrom_label(), " — ", length(unique(df$sample_id)),
                                     " file(s)")) +
        ggplot2::theme_bw()
    })

    output$plot <- renderPlotly({
      ggplotly(plot_gg(), source = "tic", tooltip = "text", dynamicTicks = TRUE) %>%
        event_register("plotly_click")
    })

    # Click -> selection that drives the Spectrum tab. suppressWarnings hides the
    # benign "source not registered" notice emitted before the plot first renders.
    click <- reactive(suppressWarnings(event_data("plotly_click", source = "tic")))
    observeEvent(click(), {
      ev <- click(); req(ev)
      rv$selection <- list(plot = "tic", file_id = ev$key, rt = ev$x, mz = NA_real_)
    })

    mod_export_server("export", plot_gg, rv, reactive(tolower(chrom_label())))
  })
}
