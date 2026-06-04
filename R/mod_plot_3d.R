# mod_plot_3d — rt x m/z x intensity in 3D (plotly native).
# Points mode (thresholded scatter3d) or surface mode (binned grid). Operates on
# one file within the global filter window; keep the intensity threshold high to
# stay responsive.

mod_plot_3d_ui <- function(id) {
  ns <- NS(id)
  card(
    full_screen = TRUE,
    card_header("3D view (rt × m/z × intensity)"),
    layout_sidebar(
      sidebar = sidebar(
        width = 250, position = "right", open = "open",
        selectInput(ns("file"), "File", choices = NULL),
        radioButtons(ns("mode"), "Mode",
                     c("Points (scatter3d)" = "points", "Surface" = "surface")),
        numericInput(ns("rt_bin"), "rt bin (s)", value = 10, min = 1),
        numericInput(ns("mz_bin"), "m/z bin", value = 1, min = 0.01, step = 0.1),
        sliderInput(ns("thr"), "Intensity percentile cutoff",
                    min = 0, max = 99, value = 90, step = 1),
        helpText("Higher cutoff = fewer points = snappier. Apply rt/m/z filters ",
                 "to zoom first.")
      ),
      plotlyOutput(ns("plot"), height = "100%")
    )
  )
}

mod_plot_3d_server <- function(id, rv, included) {
  moduleServer(id, function(input, output, session) {

    observe({
      inc <- included()
      choices <- stats::setNames(inc$id, inc$name)
      updateSelectInput(session, "file", choices = choices,
                        selected = isolate(input$file) %||% choices[1])
    })

    sel_file <- reactive({
      req(input$file)
      f <- rv$files[rv$files$id == input$file, ]
      req(nrow(f) == 1); f
    })

    # Cache the expensive peak read on (file + filter); binning is cheap.
    peaks <- reactive({
      f <- sel_file(); flt <- rv$filter
      rtr <- if (is.finite(flt$rt_min) && is.finite(flt$rt_max))
               c(flt$rt_min, flt$rt_max) else NULL
      mzr <- if (is.finite(flt$mz_min) && is.finite(flt$mz_max))
               c(flt$mz_min, flt$mz_max) else NULL
      withProgress(message = "Reading peaks…", value = 0.5, {
        extract_peaks(f$path, ms_level = flt$ms_level %||% 1L,
                      rt_range = rtr, mz_range = mzr)
      })
    }) %>% bindCache(input$file, rv$filter)

    binned <- reactive({
      df <- peaks()
      validate(need(nrow(df) > 0, "No peaks in the current filter range."))
      bin_peaks(df, rt_bin = input$rt_bin, mz_bin = input$mz_bin, aggfun = max)
    })

    output$plot <- renderPlotly({
      b <- binned(); req(nrow(b) > 0)
      thr <- stats::quantile(b$intensity, input$thr / 100, names = FALSE)
      cols <- brewer_seq(rv$settings$seq_palette)(9)

      if (input$mode == "points") {
        b <- b[b$intensity >= thr, , drop = FALSE]
        validate(need(nrow(b) > 0, "Cutoff removed all points; lower it."))
        plot_ly(b, x = ~rt_b, y = ~mz_b, z = ~intensity, type = "scatter3d",
                mode = "markers",
                marker = list(size = 2, color = ~intensity, colorscale = "YlOrRd",
                              colorbar = list(title = "int"))) %>%
          layout(scene = list(xaxis = list(title = "rt (s)"),
                              yaxis = list(title = "m/z"),
                              zaxis = list(title = "intensity")))
      } else {
        # Surface needs a regular grid: pivot bins to a matrix (rt × m/z).
        rt_ax <- sort(unique(b$rt_b)); mz_ax <- sort(unique(b$mz_b))
        validate(need(length(rt_ax) > 1 && length(mz_ax) > 1,
                      "Not enough bins for a surface; widen the range or bins."))
        z <- matrix(0, nrow = length(mz_ax), ncol = length(rt_ax),
                    dimnames = list(mz_ax, rt_ax))
        z[cbind(match(b$mz_b, mz_ax), match(b$rt_b, rt_ax))] <- b$intensity
        plot_ly(x = rt_ax, y = mz_ax, z = z, type = "surface",
                colorscale = list(c(0, 1), c(cols[1], cols[9]))) %>%
          layout(scene = list(xaxis = list(title = "rt (s)"),
                              yaxis = list(title = "m/z"),
                              zaxis = list(title = "intensity")))
      }
    })
  })
}
