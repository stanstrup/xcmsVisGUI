# mod_plot_map — combined 2D MS map + 3D view for the included file(s).
#
# No separate file selector: it uses whatever is included. Rendering is gated by
# an explicit "Plot" button so it never auto-extracts every included file. 2D map
# draws centroids as rt-width line segments (no binning) with an mzMine-style
# contrast control; 3D offers surface (default) or points.

MAP_POINT_CAP <- 400000L
MAP_LINE_CAP  <- 200000L

mod_plot_map_ui <- function(id) {
  ns <- NS(id)
  card(
    full_screen = TRUE,
    card_header("MS map", div(class = "float-end", mod_export_ui(ns("export")))),
    layout_sidebar(
      sidebar = sidebar(
        width = 260, position = "right", open = "open",
        actionButton(ns("plot"), "Plot", icon = icon("play"), class = "btn-primary"),
        radioButtons(ns("mode"), "View",
                     c("2D map" = "map", "3D surface" = "surface", "3D points" = "points")),
        conditionalPanel(
          sprintf("input['%s'] == 'map'", ns("mode")),
          sliderInput(ns("contrast"), "Contrast (intensity percentile = full colour)",
                      min = 50, max = 100, value = 98, step = 0.5),
          numericInput(ns("psize"), "Line/point size", value = 1.5, min = 0.5, max = 6, step = 0.5)
        ),
        conditionalPanel(
          sprintf("input['%s'] == 'surface'", ns("mode")),
          numericInput(ns("rt_bin"), "rt bin (s)", value = 10, min = 1),
          numericInput(ns("mz_bin"), "m/z bin", value = 1, min = 0.01, step = 0.1)
        ),
        conditionalPanel(
          sprintf("input['%s'] == 'points'", ns("mode")),
          sliderInput(ns("thr"), "Intensity percentile cutoff",
                      min = 0, max = 99, value = 90, step = 1)
        ),
        helpText("Press Plot to (re)render for the included files. 2D map draws ",
                 "exact centroids; lower the contrast to reveal weaker peaks.")
      ),
      plotlyOutput(ns("plot_out"), height = "100%")
    )
  )
}

mod_plot_map_server <- function(id, rv, included) {
  moduleServer(id, function(input, output, session) {

    # Heavy read only on Plot. Combines peaks from all included files.
    peaks_all <- eventReactive(input$plot, {
      inc <- included()
      validate(need(nrow(inc) > 0, "Add and include at least one file."))
      withProgress(message = "Reading peaks…", value = 0.3, {
        pieces <- lapply(seq_len(nrow(inc)), function(i) {
          d <- extract_peaks(inc$path[i], rv$filter)
          if (nrow(d)) d$sample_id <- inc$id[i]
          d
        })
        dplyr::bind_rows(pieces)
      })
    })

    output$plot_out <- renderPlotly({
      if (is.null(input$plot) || input$plot == 0)
        validate("Press ‘Plot’ to render the MS map for the included file(s).")
      pk <- peaks_all()
      validate(need(nrow(pk) > 0, "No peaks in the current filter range."))
      unit <- rv$settings$time_unit
      pk$rt_disp <- rt_to_disp(pk$rt, unit)
      cs <- brewer_colorscale(rv$settings$seq_palette)

      if (input$mode == "map") {
        if (nrow(pk) > MAP_LINE_CAP)
          pk <- pk[order(-pk$intensity)[seq_len(MAP_LINE_CAP)], , drop = FALSE]
        cmax <- stats::quantile(pk$intensity, input$contrast / 100, names = FALSE)
        if (!is.finite(cmax) || cmax <= 0) cmax <- max(pk$intensity)
        # next-scan rt per file gives each centroid its rt width
        if (is.null(pk$sample_id)) pk$sample_id <- "f"
        pk$rt1 <- stats::ave(pk$rt, pk$sample_id, FUN = function(r) {
          u <- sort(unique(r))
          gap <- if (length(u) > 1) diff(u)[length(u) - 1] else 1
          c(u[-1], u[length(u)] + gap)[match(r, u)]
        })
        pk$rt1_disp <- rt_to_disp(pk$rt1, unit)
        K <- 32L; cols <- brewer_seq(rv$settings$seq_palette)(K)
        pk$grp <- pmax(1L, pmin(K, ceiling(pmin(pk$intensity, cmax) / cmax * K)))
        p <- plot_ly(source = "map")
        for (g in sort(unique(pk$grp))) {
          d <- pk[pk$grp == g, , drop = FALSE]
          x <- as.vector(rbind(d$rt_disp, d$rt1_disp, NA_real_))
          y <- as.vector(rbind(d$mz, d$mz, NA_real_))
          p <- add_trace(p, x = x, y = y, type = "scattergl", mode = "lines",
                         line = list(color = cols[g], width = input$psize),
                         hoverinfo = "skip", showlegend = FALSE)
        }
        p <- add_trace(p, x = rep(pk$rt_disp[1], 2), y = rep(pk$mz[1], 2),
                       type = "scattergl", mode = "markers",
                       marker = list(color = c(0, cmax), colorscale = cs, cmin = 0,
                                     cmax = cmax, size = 0.1, colorbar = list(title = "int")),
                       hoverinfo = "skip", showlegend = FALSE)
        p %>% layout(xaxis = list(title = rt_axis_label(unit)), yaxis = list(title = "m/z"),
                     uirevision = "map2d") %>%
          event_register("plotly_click")

      } else if (input$mode == "surface") {
        b <- bin_peaks(pk, rt_bin = input$rt_bin, mz_bin = input$mz_bin, aggfun = max)
        validate(need(nrow(b) > 0, "No peaks to bin."))
        b$rt_disp <- rt_to_disp(b$rt_b, unit)
        rt_ax <- sort(unique(b$rt_disp)); mz_ax <- sort(unique(b$mz_b))
        validate(need(length(rt_ax) > 1 && length(mz_ax) > 1,
                      "Not enough bins for a surface; widen the range or bins."))
        z <- matrix(0, nrow = length(mz_ax), ncol = length(rt_ax),
                    dimnames = list(mz_ax, rt_ax))
        z[cbind(match(b$mz_b, mz_ax), match(b$rt_disp, rt_ax))] <- b$intensity
        plot_ly(x = rt_ax, y = mz_ax, z = z, type = "surface", colorscale = cs) %>%
          layout(uirevision = "map3d", scene = list(
            xaxis = list(title = rt_axis_label(unit), range = range(rt_ax)),
            yaxis = list(title = "m/z", range = range(mz_ax)),
            zaxis = list(title = "intensity")))

      } else {  # 3D points
        thr <- stats::quantile(pk$intensity, input$thr / 100, names = FALSE)
        pk <- pk[pk$intensity >= thr, , drop = FALSE]
        validate(need(nrow(pk) > 0, "Cutoff removed all points; lower it."))
        if (nrow(pk) > MAP_POINT_CAP)
          pk <- pk[order(-pk$intensity)[seq_len(MAP_POINT_CAP)], , drop = FALSE]
        plot_ly(pk, x = ~rt_disp, y = ~mz, z = ~intensity, type = "scatter3d",
                mode = "markers",
                marker = list(size = 2, color = ~intensity, colorscale = cs)) %>%
          layout(uirevision = "map3d", scene = list(
            xaxis = list(title = rt_axis_label(unit), range = range(pk$rt_disp)),
            yaxis = list(title = "m/z", range = range(pk$mz)),
            zaxis = list(title = "intensity")))
      }
    })

    # Click a 2D-map point -> spectrum at that rt (first included file).
    click <- reactive(suppressWarnings(event_data("plotly_click", source = "map")))
    observeEvent(click(), {
      ev <- click(); req(ev, !is.null(ev$x))
      inc <- included(); req(nrow(inc) > 0)
      rv$selection <- list(plot = "map", file_id = inc$id[1],
                           rt = rt_to_sec(ev$x, rv$settings$time_unit), mz = ev$y)
    })

    export_gg <- reactive({
      req(input$mode == "map", input$plot > 0)
      pk <- peaks_all(); req(nrow(pk) > 0)
      unit <- rv$settings$time_unit
      if (nrow(pk) > MAP_LINE_CAP)
        pk <- pk[order(-pk$intensity)[seq_len(MAP_LINE_CAP)], , drop = FALSE]
      pk$rt_disp <- rt_to_disp(pk$rt, unit)
      cmax <- stats::quantile(pk$intensity, input$contrast / 100, names = FALSE)
      ggplot2::ggplot(pk, ggplot2::aes(rt_disp, mz, color = pmin(intensity, cmax))) +
        ggplot2::geom_point(size = input$psize * 0.4) +
        ggplot2::scale_color_gradientn(colours = brewer_seq(rv$settings$seq_palette)(9)) +
        ggplot2::labs(x = rt_axis_label(unit), y = "m/z", color = "int") +
        ggplot2::theme_bw()
    })
    mod_export_server("export", export_gg, rv, "msmap")
  })
}
