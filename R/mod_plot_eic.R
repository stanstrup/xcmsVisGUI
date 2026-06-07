# mod_plot_eic — multiple extracted ion chromatograms.
# A target table (label / m/z / tolerance / rt window / enable) drives extraction;
# traces are overlaid and colored by target, file, or group (ColorBrewer).
# Click a trace to load the spectrum at that retention time.

#' @importFrom DT DTOutput
#' @importFrom plotly plotlyOutput
#' @noRd
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
        width = 420, position = "right", open = "open",
        # Compact the target table so its columns fit the sidebar without scroll.
        tags$style(HTML(sprintf(
          "#%s table.dataTable{font-size:11px} #%s td,#%s th{padding:2px 4px;white-space:nowrap}",
          ns("targets"), ns("targets"), ns("targets")))),
        DTOutput(ns("targets")),
        div(class = "d-flex gap-2 mt-2",
            actionButton(ns("add"), "Add row", class = "btn-sm btn-outline-primary"),
            actionButton(ns("del"), "Remove selected", class = "btn-sm btn-outline-secondary")),
        hr(),
        helpText(strong("Paste m/z values"), " \u2014 these are ", strong("added"),
                 " to the target list above."),
        textAreaInput(ns("paste"), NULL, rows = 3,
                      placeholder = "195.0877, 300.20\n335.10"),
        div(class = "d-flex gap-2",
            numericInput(ns("paste_tol"), "\u00b1 tol", value = 10, min = 0, width = "80px"),
            selectInput(ns("paste_unit"), "unit", c("ppm", "Da"), width = "90px"),
            actionButton(ns("parse"), "Add to list", class = "btn-sm btn-outline-primary mt-4")),
        helpText("tol is \u00b1 half-window: window = m/z \u00b1 m/z\u00b7ppm/1e6 (or \u00b1 Da). ",
                 "So 10 ppm spans 20 ppm total \u2014 increase it if EICs look too narrow."),
        hr(),
        selectInput(ns("color_by"), "Color by",
                    c("File" = "sample_name", "Target" = "target",
                      "Sample group" = "sample_group")),
        checkboxInput(ns("points"), "Show data points", value = FALSE),
        checkboxInput(ns("facet"), "Facet by file", value = FALSE),
        helpText("Click a trace to show its spectrum.")
      ),
      plotlyOutput(ns("plot"), height = "100%")
    )
  )
}

#' @importFrom DT renderDT datatable
#' @importFrom dplyr bind_rows left_join
#' @importFrom tibble tibble
#' @importFrom ggplot2 ggplot aes geom_line geom_point scale_color_manual labs theme_bw facet_wrap
#' @importFrom plotly renderPlotly
#' @noRd
mod_plot_eic_server <- function(id, rv, dataset, meta, data_key) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # --- Target table: enabled as a checkbox, other columns editable --------
    output$targets <- renderDT({
      tg <- rv$eic_targets
      if (nrow(tg) == 0) return(datatable(tg[, c("label","mz")], rownames = FALSE,
                                              options = list(dom = "t")))
      check <- vapply(seq_len(nrow(tg)), function(i) as.character(tags$input(
        type = "checkbox", checked = if (isTRUE(tg$enabled[i])) "checked" else NULL,
        onclick = sprintf(
          "Shiny.setInputValue('%s', {row: %d, checked: this.checked}, {priority:'event'})",
          ns("toggle"), i))), character(1))
      disp <- data.frame(` ` = check, label = tg$label, mz = tg$mz, tol = tg$tol,
                         unit = tg$unit, rt_min = tg$rt_min, rt_max = tg$rt_max,
                         check.names = FALSE, stringsAsFactors = FALSE)
      # Round only the DISPLAY (DT render) — the stored target m/z keeps full
      # precision, so editing a cell doesn't truncate it.
      datatable(
        disp, escape = FALSE, rownames = FALSE, selection = "multiple",
        editable = list(target = "cell", columns = 1:6),   # all but the checkbox
        options = list(dom = "t", paging = FALSE, ordering = FALSE,
                       columnDefs = list(list(className = "dt-center", targets = "_all")))) %>%
        DT::formatRound("mz", 4) %>% DT::formatRound(c("rt_min", "rt_max"), 3)
    })

    observeEvent(input$toggle, {
      i <- input$toggle$row
      if (i >= 1 && i <= nrow(rv$eic_targets))
        rv$eic_targets$enabled[i] <- isTRUE(input$toggle$checked)
    })

    observeEvent(input$targets_cell_edit, {
      info <- input$targets_cell_edit
      # display col 0 is the checkbox; data columns start at 1 -> map to names
      col <- c("label","mz","tol","unit","rt_min","rt_max")[info$col]
      req(!is.na(col))
      val <- info$value
      rv$eic_targets[[col]][info$row] <-
        if (col %in% c("mz","tol","rt_min","rt_max")) suppressWarnings(as.numeric(val))
        else as.character(val)
    })

    observeEvent(input$add, {
      n <- nrow(rv$eic_targets) + 1
      rv$eic_targets <- bind_rows(rv$eic_targets, new_eic_target(
        NA_real_, tol = rv$settings$default_tol, unit = rv$settings$default_tol_unit,
        label = paste0("target", n)))
    })

    # Seed the paste tolerance/unit controls from the default-tolerance setting.
    observeEvent(rv$settings$default_tol,
                 updateNumericInput(session, "paste_tol", value = rv$settings$default_tol))
    observeEvent(rv$settings$default_tol_unit,
                 updateSelectInput(session, "paste_unit", selected = rv$settings$default_tol_unit))
    observeEvent(input$del, {
      sel <- input$targets_rows_selected
      if (length(sel)) rv$eic_targets <- rv$eic_targets[-sel, ]
    })

    observeEvent(input$parse, {
      vals <- suppressWarnings(as.numeric(trimws(strsplit(input$paste, "[,\n;]+")[[1]])))
      vals <- vals[is.finite(vals)]
      req(length(vals) > 0)
      rv$eic_targets <- bind_rows(rv$eic_targets,
        new_eic_target(vals, tol = input$paste_tol, unit = input$paste_unit))
      updateTextAreaInput(session, "paste", value = "")
    })

    # --- Extraction -------------------------------------------------------
    enabled_targets <- reactive({
      tg <- rv$eic_targets
      tg[isTRUE_vec(tg$enabled) & is.finite(tg$mz), , drop = FALSE]
    })

    eic_df <- reactive({
      x <- dataset(); req(x)
      tg <- enabled_targets()
      validate(need(nrow(tg) > 0, "Add at least one enabled target with a valid m/z."))
      unit <- rv$settings$time_unit
      tol_da <- ifelse(tg$unit == "ppm", tg$mz * tg$tol / 1e6, tg$tol)
      mzmat <- cbind(tg$mz - tol_da, tg$mz + tol_da)
      # rt window cells are in the display unit -> seconds for extraction
      rmin_s <- rt_to_sec(tg$rt_min, unit); rmax_s <- rt_to_sec(tg$rt_max, unit)
      rtr <- numeric()
      if (any(is.finite(rmin_s)) || any(is.finite(rmax_s)))
        rtr <- c(min(rmin_s, na.rm = TRUE), max(rmax_s, na.rm = TRUE))
      ms <- chrom_ms_level(rv$filter)
      withProgress(message = "Extracting EICs\u2026", value = 0.5, {
        chr <- if (length(rtr) == 2) xcms::chromatogram(x, mz = mzmat, rt = rtr, msLevel = ms)
               else xcms::chromatogram(x, mz = mzmat, msLevel = ms)
        df <- add_scan_numbers(chrom_to_df(chr, meta(), labels = tg$label), meta())
      })
      # per-target rt clipping (display unit -> seconds)
      if (any(is.finite(rmin_s)) || any(is.finite(rmax_s))) {
        lims <- tibble(target = tg$label, rmin = rmin_s, rmax = rmax_s)
        df <- left_join(df, lims, by = "target")
        df <- df[(is.na(df$rmin) | df$rt >= df$rmin) &
                 (is.na(df$rmax) | df$rt <= df$rmax), ]
        df$rmin <- NULL; df$rmax <- NULL
      }
      df
    }) %>% bindCache(data_key(), enabled_targets(), rv$settings$time_unit)

    plot_gg <- reactive({
      df <- eic_df(); req(nrow(df) > 0)
      m <- meta()
      df$sample_group <- m$sample_group[match(df$sample_id, m$id)]
      cby <- input$color_by
      unit <- rv$settings$time_unit
      df$rt_disp <- rt_to_disp(df$rt, unit)
      df$.color <- df[[cby]]
      pal <- brewer_named(unique(df$.color), rv$settings$qual_palette)
      df$.tip <- sprintf("%s | %s\nscan: %s\nrt: %.4g %s\nint: %.3g",
                         df$target, df$sample_name, ifelse(is.na(df$scan), "?", df$scan),
                         df$rt_disp, unit, df$intensity)
      p <- ggplot(df, aes(
        x = rt_disp, y = intensity, color = .color,
        group = interaction(target, sample_id), key = sample_id, text = .tip))
      # when not coloring by target, distinguish targets by line type
      if (cby != "target" && length(unique(df$target)) > 1)
        p <- p + geom_line(aes(linetype = target), linewidth = 0.5)
      else
        p <- p + geom_line(linewidth = 0.5)
      if (isTRUE(input$points)) p <- p + geom_point(size = 0.9)
      p <- p +
        scale_color_manual(values = pal) +
        labs(x = rt_axis_label(unit), y = "intensity", color = NULL,
                      linetype = NULL) +
        theme_bw()
      if (isTRUE(input$facet) && length(unique(df$sample_id)) > 1)
        p <- p + facet_wrap(~ sample_name, ncol = 1, scales = "free_y")
      p
    })

    keep_zoom <- zoom_keeper("eic")
    output$plot <- renderPlotly(finalize_plotly(plot_gg(), "eic", keep_zoom))
    wire_selection("eic", "eic", rv)

    mod_export_server("export", plot_gg, rv, "eic")
  })
}

# Coerce a possibly-character/NA logical vector to a safe logical.
isTRUE_vec <- function(x) {
  out <- as.logical(x); out[is.na(out)] <- FALSE; out
}
