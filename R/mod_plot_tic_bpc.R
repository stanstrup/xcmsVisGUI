# mod_plot_tic_bpc — TIC/BPC overlay of included files, colored by metadata.
# Click a trace to load that scan's spectrum (rv$selection).

#' @importFrom plotly plotlyOutput
#' @noRd
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
                    c("Sample" = "sample_name", "Sample group" = "sample_group")),
        checkboxInput(ns("points"), "Show data points", value = FALSE),
        helpText("Click a trace to show its spectrum on the Spectrum tab.")
      ),
      plotlyOutput(ns("plot"), height = "100%")
    )
  )
}

#' @importFrom ggplot2 ggplot aes geom_line geom_point scale_color_manual labs theme_bw
#' @importFrom plotly renderPlotly
#' @noRd
mod_plot_tic_bpc_server <- function(id, rv, dataset, meta, data_key) {
  moduleServer(id, function(input, output, session) {

    chrom_label <- reactive(if (input$agg == "sum") "TIC" else "BPC")

    # TIC/BPC via xcms::chromatogram (fast under SerialParam), cached on
    # (path set + filter + aggregation) so group/color changes never re-extract.
    chrom_df <- reactive({
      x <- dataset(); req(x)
      # An over-restrictive filter (e.g. a spectrum-ID rule matching nothing) can
      # leave zero spectra; xcms::chromatogram() would then error "No spectra
      # available" \u2014 show a clear message instead.
      validate(need(length(MsExperiment::spectra(x)) > 0,
                    "No spectra match the current filters."))
      ms <- chrom_ms_level(rv$filter)
      withProgress(message = "Extracting chromatograms\u2026", value = 0.5, {
        chr <- xcms::chromatogram(x, aggregationFun = input$agg, msLevel = ms)
        add_scan_numbers(chrom_to_df(chr, meta(), labels = chrom_label()), meta())
      })
    }) %>% bindCache(data_key(), input$agg)

    # The ggplot (source of truth for export).
    plot_gg <- reactive({
      df <- chrom_df(); req(nrow(df) > 0)
      # Refresh group labels from current metadata (cheap) so renaming a group
      # recolors without re-extracting.
      m <- meta()
      df$sample_group <- m$sample_group[match(df$sample_id, m$id)]
      df$sample_name <- strip_ext(df$sample_name)   # display label: drop extension
      cby <- input$color_by
      lvls <- unique(df[[cby]])
      pal <- brewer_named(lvls, rv$settings$qual_palette)
      df$.color <- df[[cby]]
      unit <- rv$settings$time_unit
      df$rt_disp <- rt_to_disp(df$rt, unit)
      df$.tip <- sprintf("%s\nscan: %s\nrt: %.4g %s\nint: %.3g",
                         df$sample_name, ifelse(is.na(df$scan), "?", df$scan),
                         df$rt_disp, unit, df$intensity)
      p <- ggplot(df, aes(
        x = rt_disp, y = intensity, group = sample_id, color = .color,
        key = sample_id, text = .tip)) +
        geom_line(linewidth = 0.5)
      if (isTRUE(input$points)) p <- p + geom_point(size = 0.9)
      p +
        scale_color_manual(values = pal) +
        labs(x = rt_axis_label(unit), y = "intensity",
                      color = NULL,
                      title = paste0(chrom_label(), " \u2014 ", length(unique(df$sample_id)),
                                     " file(s)")) +
        theme_bw()
    })

    keep_zoom <- zoom_keeper("tic")
    output$plot <- renderPlotly(finalize_plotly(plot_gg(), "tic", keep_zoom))
    # Click -> selection that drives the Spectrum tab.
    wire_selection("tic", "tic", rv)

    mod_export_server("export", plot_gg, rv, reactive(tolower(chrom_label())))
  })
}
