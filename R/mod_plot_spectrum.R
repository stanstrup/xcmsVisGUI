# mod_plot_spectrum — spectrum viewer driven by the included files (no separate
# file picker). Single view uses the clicked / first included file; Facet and
# Stacked views compare the spectrum at the chosen rt across all included files.
# A scan-list browser shows every scan's metadata.

mod_plot_spectrum_ui <- function(id) {
  ns <- NS(id)
  card(
    full_screen = TRUE,
    card_header(
      "Spectrum",
      div(class = "float-end d-flex gap-2",
          actionButton(ns("scanlist"), "Scan list", class = "btn-sm btn-outline-secondary"),
          mod_export_ui(ns("export")))
    ),
    layout_sidebar(
      sidebar = sidebar(
        width = 250, position = "right", open = "open",
        radioButtons(ns("layout"), "Layout",
                     c("Single file" = "single", "Facet by file" = "facet",
                       "Stacked" = "stacked")),
        numericInput(ns("rt"), "Retention time", value = NA, step = 0.1),
        conditionalPanel(
          sprintf("input['%s'] == 'single'", ns("layout")),
          numericInput(ns("scan"), "…or scan (acquisition) number", value = NA, step = 1)),
        helpText("Single view uses the file you clicked (or the first included). ",
                 "Facet / Stacked compare all included files at the rt. MS level ",
                 "and intensity / spectrum-id filters come from the global filter.")
      ),
      plotlyOutput(ns("plot"), height = "100%")
    )
  )
}

mod_plot_spectrum_server <- function(id, rv, included) {
  moduleServer(id, function(input, output, session) {

    # The file used by the single view: clicked file, else first included.
    cur_file <- reactiveVal(NULL)
    observe({
      inc <- included()
      if (is.null(cur_file()) || !(cur_file() %in% inc$id))
        cur_file(if (nrow(inc)) inc$id[1] else NULL)
    })
    cur_row <- reactive({
      req(cur_file())
      f <- rv$files[rv$files$id == cur_file(), ]; req(nrow(f) == 1); f
    })

    # A click sets the single-view file + rt (clears scan).
    observeEvent(rv$selection, {
      s <- rv$selection; req(s, s$file_id)
      if (s$file_id %in% rv$files$id) cur_file(s$file_id)
      if (!is.null(s$rt) && is.finite(s$rt)) {
        updateNumericInput(session, "rt",
                           value = round(rt_to_disp(s$rt, rv$settings$time_unit), 4))
        updateNumericInput(session, "scan", value = NA)
      }
    })

    # Snap an out-of-range scan back into the input box.
    observeEvent(input$scan, {
      n <- cur_row()$n_spectra
      if (is.finite(input$scan) && is.finite(n) && input$scan > n)
        updateNumericInput(session, "scan", value = n)
      if (is.finite(input$scan) && input$scan < 1)
        updateNumericInput(session, "scan", value = 1)
    })

    one_spectrum <- function(path, rt_sec, scan) {
      extract_spectrum(path, rt = rt_sec,
                       scan = if (is.finite(scan)) as.integer(scan) else NA_integer_,
                       f = rv$filter)
    }

    spec_df <- reactive({
      unit <- rv$settings$time_unit
      use_scan <- identical(input$layout, "single") &&
        !is.null(input$scan) && is.finite(input$scan)
      rt_disp <- input$rt
      validate(need(use_scan || is.finite(rt_disp),
                    "Enter a retention time (or scan number), or click a chromatogram."))
      rt_sec <- if (is.finite(rt_disp)) rt_to_sec(rt_disp, unit) else NA_real_
      withProgress(message = "Reading spectrum…", value = 0.5, {
        if (identical(input$layout, "single")) {
          f <- cur_row()
          d <- one_spectrum(f$path, rt_sec, input$scan); d$sample_name <- f$name; d
        } else {
          inc <- included(); validate(need(nrow(inc) > 0, "Include at least one file."))
          dplyr::bind_rows(lapply(seq_len(nrow(inc)), function(i) {
            d <- one_spectrum(inc$path[i], rt_sec, NA_integer_)
            if (nrow(d)) d$sample_name <- inc$name[i]
            d
          }))
        }
      })
    })

    plot_gg <- reactive({
      df <- spec_df(); req(nrow(df) > 0)
      unit <- rv$settings$time_unit
      col1 <- brewer_qual(1, rv$settings$qual_palette)
      if (identical(input$layout, "stacked")) {
        # normalise each file and offset vertically
        df <- dplyr::group_by(df, sample_name)
        df <- dplyr::mutate(df, intensity = intensity / max(intensity, na.rm = TRUE))
        df <- dplyr::ungroup(df)
        off <- stats::setNames(seq_along(unique(df$sample_name)) - 1, unique(df$sample_name))
        df$y0 <- off[df$sample_name] * 1.1
        df$y1 <- df$y0 + df$intensity
        df$.tip <- sprintf("%s\nm/z: %.4f", df$sample_name, df$mz)
        p <- ggplot2::ggplot(df, ggplot2::aes(x = mz, ymin = y0, ymax = y1,
                                              color = sample_name, text = .tip)) +
          ggplot2::geom_linerange(linewidth = 0.4) +
          ggplot2::scale_color_manual(
            values = brewer_named(unique(df$sample_name), rv$settings$qual_palette)) +
          ggplot2::labs(x = "m/z", y = NULL, color = NULL) +
          ggplot2::theme_classic() +
          ggplot2::theme(axis.text.y = ggplot2::element_blank(),
                         axis.ticks.y = ggplot2::element_blank())
        return(p)
      }
      df$.tip <- sprintf("m/z: %.4f\nint: %.3g", df$mz, df$intensity)
      ttl <- if (identical(input$layout, "single"))
        sprintf("%s — scan %s @ rt %.4g %s", df$sample_name[1],
                if (is.na(df$scan[1])) "?" else df$scan[1],
                rt_to_disp(df$rt[1], unit), unit)
      else sprintf("rt %.4g %s — %d files", rt_to_disp(df$rt[1], unit), unit,
                   length(unique(df$sample_name)))
      p <- ggplot2::ggplot(df, ggplot2::aes(x = mz, ymin = 0, ymax = intensity, text = .tip)) +
        ggplot2::geom_linerange(linewidth = 0.4, color = col1) +
        ggplot2::labs(x = "m/z", y = "intensity", title = ttl) +
        ggplot2::theme_classic()
      if (identical(input$layout, "facet"))
        p <- p + ggplot2::facet_wrap(~ sample_name, ncol = 1, scales = "free_y")
      p
    })

    output$plot <- renderPlotly({
      ggplotly(plot_gg(), source = "spec", tooltip = "text", dynamicTicks = FALSE) %>%
        layout(uirevision = "spec")
    })

    # --- Scan list browser (click a row to load that scan) -----------------
    ns <- session$ns
    scan_tab <- reactive({
      f <- cur_row()
      tab <- file_scan_table(f$path)
      tab$rt_disp <- round(rt_to_disp(tab$rt, rv$settings$time_unit), 4)
      tab
    })
    observeEvent(input$scanlist, {
      showModal(modalDialog(
        title = paste("Scans —", cur_row()$name), size = "xl", easyClose = TRUE,
        helpText("Click a row to load that scan."),
        DT::DTOutput(ns("scantable")),
        footer = modalButton("Close")
      ))
    })
    output$scantable <- DT::renderDT({
      tab <- scan_tab()
      disp <- tab[, c("scan", "rt_disp", "msLevel", "polarity", "precursorMZ",
                      "charge", "tic", "basePeakMZ")]
      names(disp)[2] <- paste0("rt(", rv$settings$time_unit, ")")
      DT::datatable(disp, rownames = FALSE, selection = "single", filter = "top",
                    options = list(pageLength = 15, scrollX = TRUE))
    })
    observeEvent(input$scantable_rows_selected, {
      i <- input$scantable_rows_selected; req(length(i) == 1)
      updateRadioButtons(session, "layout", selected = "single")
      updateNumericInput(session, "scan", value = scan_tab()$scan[i])
      removeModal()
    })

    mod_export_server("export", plot_gg, rv, "spectrum")
  })
}
