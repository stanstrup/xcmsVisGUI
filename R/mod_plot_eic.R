# mod_plot_eic — multiple extracted ion chromatograms per file.
# An editable target table (label / m/z / tolerance / rt window / enable) drives
# chromatogram extraction; targets are overlaid and colored with ColorBrewer.
# Click a trace to load the spectrum at that retention time.

mod_plot_eic_ui <- function(id) {
  ns <- NS(id)
  card(
    full_screen = TRUE,
    card_header(
      "Extracted ion chromatograms",
      div(class = "float-end", mod_export_ui(ns("export")))
    ),
    layout_sidebar(
      sidebar = sidebar(
        width = 340, position = "right", open = "open",
        DT::DTOutput(ns("targets")),
        div(class = "d-flex gap-2 mt-2",
            actionButton(ns("add"), "Add row", class = "btn-sm btn-outline-primary"),
            actionButton(ns("del"), "Remove selected", class = "btn-sm btn-outline-secondary")),
        hr(),
        textAreaInput(ns("paste"), "Paste m/z values (comma / newline separated)",
                      rows = 3, placeholder = "195.0877, 300.20\n335.10"),
        div(class = "d-flex gap-2",
            numericInput(ns("paste_tol"), "tol", value = 10, min = 0, width = "80px"),
            selectInput(ns("paste_unit"), "unit", c("ppm", "Da"), width = "90px"),
            actionButton(ns("parse"), "Add", class = "btn-sm btn-outline-primary mt-4")),
        hr(),
        checkboxInput(ns("facet"), "Facet by file", value = FALSE),
        helpText("Click a trace to show its spectrum.")
      ),
      plotlyOutput(ns("plot"), height = "100%")
    )
  )
}

mod_plot_eic_server <- function(id, rv, paths, meta, data_key) {
  moduleServer(id, function(input, output, session) {

    # Seed one example row the first time the module is used.
    observe({
      if (nrow(rv$eic_targets) == 0)
        rv$eic_targets <- tibble::tibble(
          label = "target1", mz = 300.2, tol = 10, unit = "ppm",
          rt_min = NA_real_, rt_max = NA_real_, enabled = TRUE)
    })

    # --- Target table (editable) -----------------------------------------
    output$targets <- DT::renderDT({
      DT::datatable(
        rv$eic_targets, rownames = FALSE, selection = "multiple",
        editable = "cell",
        options = list(dom = "t", paging = FALSE, ordering = FALSE,
                       columnDefs = list(list(className = "dt-center", targets = "_all")))
      )
    })
    proxy <- DT::dataTableProxy("targets")

    observeEvent(input$targets_cell_edit, {
      info <- input$targets_cell_edit
      col <- names(rv$eic_targets)[info$col + 1]
      val <- info$value
      rv$eic_targets[[col]][info$row] <-
        if (col %in% c("mz", "tol", "rt_min", "rt_max")) suppressWarnings(as.numeric(val))
        else if (col == "enabled") as.logical(val)
        else as.character(val)
    })

    observeEvent(input$add, {
      n <- nrow(rv$eic_targets) + 1
      rv$eic_targets <- dplyr::bind_rows(rv$eic_targets, tibble::tibble(
        label = paste0("target", n), mz = NA_real_, tol = 10, unit = "ppm",
        rt_min = NA_real_, rt_max = NA_real_, enabled = TRUE))
    })
    observeEvent(input$del, {
      sel <- input$targets_rows_selected
      if (length(sel)) rv$eic_targets <- rv$eic_targets[-sel, ]
    })

    observeEvent(input$parse, {
      vals <- suppressWarnings(as.numeric(trimws(strsplit(input$paste, "[,\n;]+")[[1]])))
      vals <- vals[is.finite(vals)]
      req(length(vals) > 0)
      add <- tibble::tibble(
        label = sprintf("m%.4f", vals), mz = vals,
        tol = input$paste_tol, unit = input$paste_unit,
        rt_min = NA_real_, rt_max = NA_real_, enabled = TRUE)
      rv$eic_targets <- dplyr::bind_rows(rv$eic_targets, add)
      updateTextAreaInput(session, "paste", value = "")
    })

    # --- Extraction -------------------------------------------------------
    enabled_targets <- reactive({
      tg <- rv$eic_targets
      tg[isTRUE_vec(tg$enabled) & is.finite(tg$mz), , drop = FALSE]
    })

    # Cached on (path set + filter + the enabled target rows). Manual EIC
    # extraction (xcms #809) from the mzR cache — sub-second per file.
    eic_df <- reactive({
      p <- paths(); m <- meta()
      tg <- enabled_targets()
      validate(need(nrow(tg) > 0, "Add at least one enabled target with a valid m/z."))
      tol_da <- ifelse(tg$unit == "ppm", tg$mz * tg$tol / 1e6, tg$tol)
      mzmat <- cbind(tg$mz - tol_da, tg$mz + tol_da)
      withProgress(message = "Reading EICs…", value = 0.5, {
        df <- compute_eic(p, m, mzmat, tg$label, rv$filter)
      })
      # Per-target retention-time window (from the table), if set.
      if (any(is.finite(tg$rt_min)) || any(is.finite(tg$rt_max))) {
        lims <- tibble::tibble(target = tg$label, rmin = tg$rt_min, rmax = tg$rt_max)
        df <- dplyr::left_join(df, lims, by = "target")
        df <- df[(is.na(df$rmin) | df$rt >= df$rmin) &
                 (is.na(df$rmax) | df$rt <= df$rmax), ]
        df$rmin <- NULL; df$rmax <- NULL
      }
      df
    }) %>% bindCache(data_key(), enabled_targets())

    plot_gg <- reactive({
      df <- eic_df(); req(nrow(df) > 0)
      lvls <- unique(df$target)
      pal <- brewer_named(lvls, rv$settings$qual_palette)
      df$.tip <- sprintf("%s | %s\nrt: %.0f s\nint: %.3g",
                         df$target, df$sample_name, df$rt, df$intensity)
      p <- ggplot2::ggplot(df, ggplot2::aes(
        x = rt, y = intensity, color = target,
        group = interaction(target, sample_id),
        key = sample_id, text = .tip)) +
        ggplot2::geom_line(linewidth = 0.5) +
        ggplot2::scale_color_manual(values = pal) +
        ggplot2::labs(x = "retention time (s)", y = "intensity", color = NULL) +
        ggplot2::theme_bw()
      if (isTRUE(input$facet) && length(unique(df$sample_id)) > 1)
        p <- p + ggplot2::facet_wrap(~ sample_name, ncol = 1, scales = "free_y")
      p
    })

    output$plot <- renderPlotly({
      ggplotly(plot_gg(), source = "eic", tooltip = "text", dynamicTicks = TRUE) %>%
        event_register("plotly_click")
    })

    click <- reactive(suppressWarnings(event_data("plotly_click", source = "eic")))
    observeEvent(click(), {
      ev <- click(); req(ev)
      rv$selection <- list(plot = "eic", file_id = ev$key, rt = ev$x, mz = NA_real_)
    })

    mod_export_server("export", plot_gg, rv, "eic")
  })
}

# Coerce a possibly-character/NA logical vector to a safe logical.
isTRUE_vec <- function(x) {
  out <- as.logical(x); out[is.na(out)] <- FALSE; out
}
