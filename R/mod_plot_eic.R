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
        selectInput(ns("scale"), "Scale intensity",
                    c("Raw" = "raw",
                      "Normalise each trace (÷ own max)" = "trace",
                      "Normalise per target (÷ target max)" = "target",
                      "Log10 (y-axis)" = "log")),
        helpText("Raw = absolute. Per-trace compares peak shapes regardless of ",
                 "abundance; per-target puts one compound's files on a common 0–1 ",
                 "scale; log compresses the dynamic range. Tooltips always show the ",
                 "raw intensity."),
        checkboxInput(ns("points"), "Show data points", value = FALSE),
        checkboxInput(ns("facet"), "Facet by file", value = FALSE),
        helpText("Click a trace to show its spectrum.")
      ),
      plotlyOutput(ns("plot"), height = "100%")
    )
  )
}

#' @importFrom DT renderDT datatable dataTableProxy replaceData
#' @importFrom dplyr bind_rows left_join
#' @importFrom tibble tibble
#' @importFrom ggplot2 ggplot aes geom_line geom_point scale_color_manual labs theme_bw theme facet_wrap
#' @importFrom plotly renderPlotly
#' @noRd
mod_plot_eic_server <- function(id, rv, dataset, meta, data_key) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # --- Target table: enabled as a checkbox, other columns editable --------
    # The column set is the SAME when empty, so the proxy below can always
    # replaceData() into the table (no branch that renders different columns).
    targets_disp <- reactive({
      tg <- rv$eic_targets
      check <- vapply(seq_len(nrow(tg)), function(i) as.character(tags$input(
        type = "checkbox", checked = if (isTRUE(tg$enabled[i])) "checked" else NULL,
        # Ticking the box must ONLY tick the box. DT delegates row selection off
        # the table, so otherwise one click did two unrelated things: enable the
        # target AND mark its row for "Remove selected". Note DT binds selection
        # on MOUSEDOWN (`tbody tr`), not click — stopping propagation in onclick
        # alone is too late, the row is already selected by then. Hence both.
        onmousedown = "event.stopPropagation()",
        onclick = sprintf(
          "event.stopPropagation();Shiny.setInputValue('%s', {row: %d, checked: this.checked}, {priority:'event'})",
          ns("toggle"), i))), character(1))
      data.frame(` ` = check, label = tg$label, mz = tg$mz, tol = tg$tol,
                 unit = tg$unit, rt_min = tg$rt_min, rt_max = tg$rt_max,
                 check.names = FALSE, stringsAsFactors = FALSE)
    })

    # Rendered ONCE (isolate) — every later update goes through the proxy, so the
    # output never re-runs and the table never flashes its "recalculating" grey.
    # Round only the DISPLAY (formatRound is a rowCallback, so it survives
    # replaceData) — the stored target m/z keeps full precision, and editing a
    # cell doesn't truncate it.
    output$targets <- renderDT({
      isolate(datatable(
        targets_disp(), escape = FALSE, rownames = FALSE, selection = "multiple",
        editable = list(target = "cell", columns = 1:6),   # all but the checkbox
        options = list(dom = "t", paging = FALSE, ordering = FALSE,
                       language = list(emptyTable = "No targets yet."),
                       columnDefs = list(list(className = "dt-center", targets = "_all")))) %>%
        DT::formatRound("mz", 4) %>% DT::formatRound(c("rt_min", "rt_max"), 3))
    })
    targets_proxy <- dataTableProxy("targets")
    push_targets <- function() replaceData(targets_proxy, targets_disp(),
                                           rownames = FALSE, resetPaging = FALSE)

    # Redraw ONLY when rows are added or removed — the checkbox `onclick` carries
    # its row index, so those have to be regenerated. Ticking a box must NOT
    # redraw: the browser already flipped it, and the redraw is what greyed the
    # whole table out on every single click.
    last_nrow <- reactiveVal(NULL)
    observeEvent(targets_disp(), {
      if (identical(nrow(targets_disp()), last_nrow())) return()
      last_nrow(nrow(targets_disp()))
      push_targets()
    }, ignoreInit = TRUE)

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
      # DT's server-side editing leaves the raw <input> in the cell and keeps the
      # old value internally — the server has to push the parsed value back. Row
      # count is unchanged, so the observer above won't do it for us.
      push_targets()
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
      # See TIC: a filter matching no spectra would make chromatogram() error.
      validate(need(length(MsExperiment::spectra(x)) > 0,
                    "No spectra match the current filters."))
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
      idx <- match(df$sample_id, m$id)
      df$sample_group <- m$sample_group[idx]
      df$sample_name <- m$disp_name[idx]   # unique display label (disambiguated)
      cby <- input$color_by
      unit <- rv$settings$time_unit
      df$rt_disp <- rt_to_disp(df$rt, unit)
      df$.color <- df[[cby]]
      pal <- brewer_named(unique(df$.color), rv$settings$qual_palette)
      df$.tip <- sprintf("%s | %s\nscan: %s\nrt: %.4g %s\nint: %.3g",
                         df$target, df$sample_name, ifelse(is.na(df$scan), "?", df$scan),
                         df$rt_disp, unit, df$intensity)
      # Intensity scaling. `y` is what's plotted; the tooltip keeps the raw
      # intensity either way. Normalise within a group by dividing by its max
      # (guarding an all-zero trace); log uses log10(x+1) so the many baseline
      # zeros survive (a plain log scale would drop them and break the line).
      norm <- function(v) { mx <- max(v, na.rm = TRUE)
        if (!is.finite(mx) || mx <= 0) v else v / mx }
      ylab <- "intensity"
      df$y <- switch(input$scale %||% "raw",
        trace  = { ylab <- "intensity (÷ trace max)"
                   stats::ave(df$intensity, interaction(df$target, df$sample_id), FUN = norm) },
        target = { ylab <- "intensity (÷ target max)"
                   stats::ave(df$intensity, df$target, FUN = norm) },
        log    = { ylab <- "log10(intensity + 1)"; log10(df$intensity + 1) },
        df$intensity)
      p <- ggplot(df, aes(
        x = rt_disp, y = y, color = .color,
        group = interaction(target, sample_id), key = sample_id, text = .tip))
      # when not coloring by target, distinguish targets by line type
      if (cby != "target" && length(unique(df$target)) > 1)
        p <- p + geom_line(aes(linetype = target), linewidth = 0.5)
      else
        p <- p + geom_line(linewidth = 0.5)
      if (isTRUE(input$points)) p <- p + geom_point(size = 0.9)
      p <- p +
        scale_color_manual(values = pal) +
        labs(x = rt_axis_label(unit), y = ylab, color = NULL,
                      linetype = NULL) +
        theme_bw() +
        # File names below the plot, not beside it: a right-hand legend of long
        # file names eats the plot width. ggplotly maps this to a horizontal
        # legend under the x axis.
        theme(legend.position = "bottom")
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
