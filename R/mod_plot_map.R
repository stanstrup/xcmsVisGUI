# mod_plot_map — combined 2D MS map + 3D view for one file (single file selector).
#
# 2D map: actual centroids (no binning) drawn with WebGL (scattergl), with an
#         mzMine-style contrast control (the intensity mapped to full colour).
# 3D:     surface (default; binned, since a surface needs a grid) or points.
# Respects the global rt/m/z/MS-level filter; rt shown in the chosen time unit.

MAP_POINT_CAP <- 400000L   # scattergl stays smooth up to a few hundred k points
MAP_LINE_CAP  <- 200000L   # line segments are 3x the vertices, so a tighter cap

mod_plot_map_ui <- function(id) {
  ns <- NS(id)
  card(
    full_screen = TRUE,
    card_header("MS map", div(class = "float-end", mod_export_ui(ns("export")))),
    layout_sidebar(
      sidebar = sidebar(
        width = 260, position = "right", open = "open",
        radioButtons(ns("mode"), "View",
                     c("2D map" = "map", "3D surface" = "surface", "3D points" = "points")),
        conditionalPanel(
          sprintf("input['%s'] == 'map'", ns("mode")),
          sliderInput(ns("contrast"), "Contrast (intensity percentile = full colour)",
                      min = 50, max = 100, value = 98, step = 0.5),
          numericInput(ns("psize"), "Point size", value = 3, min = 1, max = 10)
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
        helpText("2D map draws each centroid as a segment across its scan's rt ",
                 "width (no binning); lower the contrast to reveal weaker peaks. ",
                 "Apply rt/m/z filters to zoom (top ",
                 format(MAP_LINE_CAP, big.mark = ","), " peaks shown for speed).")
      ),
      plotlyOutput(ns("plot"), height = "100%")
    )
  )
}

mod_plot_map_server <- function(id, rv, included) {
  moduleServer(id, function(input, output, session) {

    sel_file <- reactive({
      req(rv$active_file)
      f <- rv$files[rv$files$id == rv$active_file, ]
      req(nrow(f) == 1); f
    })

    # All centroids passing the global filter, cached on (file + filter).
    peaks <- reactive({
      f <- sel_file()
      withProgress(message = "Reading peaks…", value = 0.5, {
        extract_peaks(f$path, rv$filter)
      })
    }) %>% bindCache(rv$active_file, rv$filter)

    output$plot <- renderPlotly({
      pk <- peaks()
      validate(need(nrow(pk) > 0, "No peaks in the current filter range."))
      unit <- rv$settings$time_unit
      pk$rt_disp <- rt_to_disp(pk$rt, unit)
      cs <- brewer_colorscale(rv$settings$seq_palette)

      if (input$mode == "map") {
        # Each centroid is drawn as a horizontal segment spanning its scan's rt
        # width (rt -> next scan rt), so scans connect into traces (not dots).
        if (nrow(pk) > MAP_LINE_CAP)
          pk <- pk[order(-pk$intensity)[seq_len(MAP_LINE_CAP)], , drop = FALSE]
        cmax <- stats::quantile(pk$intensity, input$contrast / 100, names = FALSE)
        if (!is.finite(cmax) || cmax <= 0) cmax <- max(pk$intensity)
        urt <- sort(unique(pk$rt))
        nxt <- if (length(urt) > 1)
                 c(urt[-1], urt[length(urt)] + diff(urt)[length(urt) - 1]) else urt + 1
        pk$rt1_disp <- rt_to_disp(nxt[match(pk$rt, urt)], unit)
        K <- 32L; cols <- brewer_seq(rv$settings$seq_palette)(K)
        lev <- pmin(pk$intensity, cmax) / cmax
        pk$grp <- pmax(1L, pmin(K, ceiling(lev * K)))
        p <- plot_ly(source = "map")
        for (g in sort(unique(pk$grp))) {
          d <- pk[pk$grp == g, , drop = FALSE]
          x <- as.vector(rbind(d$rt_disp, d$rt1_disp, NA_real_))
          y <- as.vector(rbind(d$mz, d$mz, NA_real_))
          p <- add_trace(p, x = x, y = y, type = "scattergl", mode = "lines",
                         line = list(color = cols[g], width = input$psize),
                         hoverinfo = "skip", showlegend = FALSE)
        }
        # tiny hidden trace just to carry the colourbar
        p <- add_trace(p, x = rep(pk$rt_disp[1], 2), y = rep(pk$mz[1], 2),
                       type = "scattergl", mode = "markers",
                       marker = list(color = c(0, cmax), colorscale = cs, cmin = 0,
                                     cmax = cmax, size = 0.1, colorbar = list(title = "int")),
                       hoverinfo = "skip", showlegend = FALSE)
        p %>% layout(xaxis = list(title = rt_axis_label(unit)),
                     yaxis = list(title = "m/z")) %>%
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
          layout(scene = list(
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
          layout(scene = list(
            xaxis = list(title = rt_axis_label(unit), range = range(pk$rt_disp)),
            yaxis = list(title = "m/z", range = range(pk$mz)),
            zaxis = list(title = "intensity")))
      }
    })

    # Click a 2D-map point -> spectrum at that rt.
    click <- reactive(suppressWarnings(event_data("plotly_click", source = "map")))
    observeEvent(click(), {
      ev <- click(); req(ev, !is.null(ev$x))
      rv$selection <- list(plot = "map", file_id = rv$active_file,
                           rt = rt_to_sec(ev$x, rv$settings$time_unit), mz = ev$y)
    })

    # Export: 2D map only (3D is plotly-native). Rebuild a ggplot for the map.
    export_gg <- reactive({
      req(input$mode == "map")
      pk <- peaks(); req(nrow(pk) > 0)
      unit <- rv$settings$time_unit
      if (nrow(pk) > MAP_POINT_CAP)
        pk <- pk[order(-pk$intensity)[seq_len(MAP_POINT_CAP)], , drop = FALSE]
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
