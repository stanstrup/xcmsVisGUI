# mod_plot_spectrum — spectrum viewer driven by the included files (no separate
# file picker). Single view uses the clicked / first included file; Facet and
# Stacked views compare the spectrum at the chosen rt across all included files.
# A scan-list browser shows every scan's metadata. The single view can overlay
# adduct / isotope / in-source-fragment annotations (see R/fct_annotate.R):
# manual anchor, findMAIN auto-suggest, or a peak-difference network.

#' @importFrom DT DTOutput
#' @importFrom plotly plotlyOutput
#' @noRd
mod_plot_spectrum_ui <- function(id) {
  ns <- NS(id)
  single <- function(extra)   # show only in the single-file layout
    sprintf("input['%s'] == 'single'%s", ns("layout"),
            if (nzchar(extra)) paste0(" && ", extra) else "")
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
        width = 420, position = "right", open = "open",
        # Compact the ranked findMAIN table so its six columns fit. Kept inside the
        # sidebar (not a card child) so it isn't wrapped in an empty card body.
        tags$style(HTML(sprintf(
          "#%s table.dataTable{font-size:11px} #%s table.dataTable th,#%s table.dataTable td{padding:2px 5px;white-space:nowrap}",
          ns("ranked"), ns("ranked"), ns("ranked")))),
        radioButtons(ns("layout"), "Layout",
                     c("Single file" = "single", "Facet by file" = "facet",
                       "Stacked" = "stacked")),
        numericInput(ns("rt"), "Retention time", value = NA, step = 0.1),
        conditionalPanel(
          sprintf("input['%s'] == 'single'", ns("layout")),
          numericInput(ns("scan"), "…or scan (acquisition) number", value = NA, step = 1)),
        helpText("Single view uses the file you clicked (or the first included). ",
                 "Facet / Stacked compare all included files at the rt. MS level ",
                 "and intensity / spectrum-id filters come from the global filter."),

        # --- annotation (single view only) ---------------------------------
        conditionalPanel(
          single(""),
          hr(),
          checkboxInput(ns("annotate"), strong("Annotate adducts / fragments"),
                        value = FALSE),
          conditionalPanel(
            single(sprintf("input['%s'] == true", ns("annotate"))),
            radioButtons(ns("click_action"), "Click on a peak", inline = TRUE,
                         c("→ EIC list" = "eic", "→ set anchor" = "anchor")),
            selectInput(ns("ann_mode"), "Mode",
                        c("Manual anchor" = "manual", "Auto-suggest (findMAIN)" = "auto",
                          "Difference network" = "diff")),
            selectInput(ns("ann_pol"), "Ion mode",
                        c("Positive" = "pos", "Negative" = "neg")),
            div(class = "d-flex gap-2",
                numericInput(ns("ann_tol"), "± tol", value = 10, min = 0,
                             width = "90px"),
                selectInput(ns("ann_unit"), "unit", c("ppm", "Da"), width = "90px")),
            numericInput(ns("ann_min_int"), "Min intensity (% of base peak)",
                         value = 0, min = 0, max = 100, step = 0.5),
            numericInput(ns("ann_top_n"), "Annotate only top N peaks (blank = all)",
                         value = NA, min = 1, step = 1),
            # Isotope controls (all modes): how far off the theoretical spacing a
            # peak may sit, and whether to require a decreasing envelope.
            numericInput(ns("ann_iso_tol"), "Isotope tol (mDa, per M+1 step)",
                         value = 15, min = 0, step = 1),
            checkboxInput(ns("ann_iso_dec"), "Isotopes decrease in intensity",
                          value = TRUE),
            # Projection options (manual + auto): isotopes, fragments, max charge.
            conditionalPanel(
              sprintf("input['%s'] != 'diff'", ns("ann_mode")),
              div(class = "d-flex gap-2",
                  numericInput(ns("ann_niso"), "Max isotope M+n", value = 3, min = 0,
                               max = 6, step = 1, width = "120px"),
                  numericInput(ns("ann_max_z"), "Max charge", value = 1, min = 1,
                               max = 5, step = 1, width = "110px")),
              checkboxInput(ns("ann_frag"), "In-source fragments", value = TRUE),
              checkboxInput(ns("ann_ghost"), "Show expected-but-absent", value = FALSE)),
            # Manual-only: the anchor ion. Auto mode drives the anchor from findMAIN.
            conditionalPanel(
              sprintf("input['%s'] == 'manual'", ns("ann_mode")),
              div(class = "d-flex gap-2",
                  numericInput(ns("anchor_mz"), "Anchor m/z", value = NA,
                               step = 0.0001),
                  selectInput(ns("ann_adduct"), "is a", choices = NULL,
                              width = "130px"))),
            conditionalPanel(
              sprintf("input['%s'] == 'auto'", ns("ann_mode")),
              actionButton(ns("suggest"), "Suggest molecular ion",
                           class = "btn-sm btn-outline-primary mb-2"),
              helpText("Each row: findMAIN reads the main-peak m/z as that adduct, ",
                       "giving the neutral mass M and the molecular-ion m/z. The top ",
                       "row is annotated — click another to switch; sort by a column ",
                       "header (e.g. neutral M) to reorder."),
              DTOutput(ns("ranked"))),
            conditionalPanel(
              sprintf("input['%s'] == 'diff'", ns("ann_mode")),
              helpText("Annotates peak pairs whose m/z difference matches a known ",
                       "adduct/fragment. Isotope-spaced pairs are ignored (see the ",
                       "isotope controls). Set the tolerance to your instrument's ",
                       "mass accuracy; raise the minimum intensity to drop noise."))
          )
        )
      ),
      plotlyOutput(ns("plot"), height = "100%")
    )
  )
}

#' @importFrom DT renderDT datatable
#' @importFrom dplyr group_by mutate ungroup bind_rows
#' @importFrom stats setNames
#' @importFrom plotly event_data renderPlotly
#' @importFrom ggplot2 ggplot aes geom_linerange geom_vline geom_point geom_text geom_segment scale_color_manual labs theme_classic theme element_blank facet_wrap
#' @noRd
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

    # Snap an out-of-range scan back into the input box. The box holds an
    # ACQUISITION number, not a 1..n position — clamp to the file's actual
    # acquisition-number range (these can start well above 1 and be non-contiguous).
    observeEvent(input$scan, {
      if (!isTRUE(is.finite(input$scan))) return()
      scans <- file_scan_table(cur_row()$path)$scan
      scans <- scans[is.finite(scans)]
      if (!length(scans)) return()
      if (input$scan < min(scans))
        updateNumericInput(session, "scan", value = min(scans))
      else if (input$scan > max(scans))
        updateNumericInput(session, "scan", value = max(scans))
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
          extract_over_files(inc, function(p) one_spectrum(p, rt_sec, NA_integer_),
                             cols = "sample_name", on_error = notify_read_failures)
        }
      })
    })

    # --- annotation controls --------------------------------------------------
    # Seed tolerance from the shared default-tolerance setting.
    observeEvent(rv$settings$default_tol,
                 updateNumericInput(session, "ann_tol", value = rv$settings$default_tol))
    observeEvent(rv$settings$default_tol_unit,
                 updateSelectInput(session, "ann_unit", selected = rv$settings$default_tol_unit))
    # Adduct choices follow the ion mode (commonMZ quasi-molecular adducts).
    observeEvent(input$ann_pol, {
      q <- quasi_adducts(input$ann_pol)
      updateSelectInput(session, "ann_adduct", choices = q, selected = q[1])
    }, ignoreInit = FALSE)
    # Auto-detect ion mode from the file's majority polarity when the file changes.
    observeEvent(cur_file(), {
      pol <- file_scan_table(cur_row()$path)$polarity
      pol <- pol[is.finite(pol)]
      if (length(pol)) {
        maj <- as.integer(names(sort(table(pol), decreasing = TRUE))[1])
        if (maj %in% c(0L, 1L))
          updateSelectInput(session, "ann_pol", selected = if (maj == 1L) "pos" else "neg")
      }
    }, ignoreInit = TRUE)
    # Default the anchor to the base peak when annotation turns on / spectrum changes.
    observeEvent(list(input$annotate, spec_df()), {
      if (isTRUE(input$annotate) && !isTRUE(is.finite(input$anchor_mz))) {
        df <- spec_df()
        if (nrow(df)) updateNumericInput(session, "anchor_mz",
                                         value = round(df$mz[which.max(df$intensity)], 4))
      }
    }, ignoreInit = TRUE)

    # Minimum intensity threshold as a fraction of the base peak (noise filter).
    ann_floor <- reactive({
      v <- input$ann_min_int
      if (is.null(v) || !is.finite(v) || v < 0) 0 else v / 100
    })
    # Optional cap on how many peaks to annotate (NA = all).
    ann_top <- reactive({
      v <- input$ann_top_n
      if (is.null(v) || !is.finite(v) || v < 1) NA_integer_ else as.integer(v)
    })
    # Peaks above the intensity floor (the noise filter). The top-N cap is applied
    # later to the ANNOTATED peaks, not here — the user wants the N strongest hits,
    # not annotation restricted to the N strongest peaks of the whole spectrum.
    ann_peaks <- function(df) {
      df[is.finite(df$intensity) &
           df$intensity >= ann_floor() * max(df$intensity, na.rm = TRUE), , drop = FALSE]
    }

    # findMAIN ranked hypotheses (auto mode). The selected row (default the top,
    # best-scoring one) becomes the anchor — no manual anchor entry in auto mode.
    ranked <- eventReactive(input$suggest, {
      df <- ann_peaks(spec_df()); validate(need(nrow(df) > 0, "No spectrum."))
      ppm <- if (identical(input$ann_unit, "ppm")) input$ann_tol else 5
      withProgress(message = "Ranking molecular-ion hypotheses…", value = 0.5,
                   rank_anchors(df, mode = input$ann_pol, ppm = ppm, rel_floor = 0,
                                top_n = 25L))
    })
    auto_pick <- reactiveVal(1L)
    observeEvent(ranked(), auto_pick(1L))                       # reset on a new run
    observeEvent(input$ranked_rows_selected, auto_pick(input$ranked_rows_selected))
    output$ranked <- renderDT({
      r <- ranked(); validate(need(nrow(r) > 0, "No hypothesis found."))
      # Show the MAIN PEAK and the implied molecular-ion m/z so each row is
      # readable: "findMAIN reads <main m/z> as <adduct>, so M = <neutral> and the
      # molecular ion [M+H]+/[M-H]- is at <ion>".
      pr <- quasi_adducts(input$ann_pol)[1]
      prule <- adduct_rules(input$ann_pol)[adduct_rules(input$ann_pol)$name == pr, ]
      ion <- adduct_mz(r$neutral_mass, prule)
      disp <- data.frame(
        `main m/z` = round(r$adductmz, 4), `is a` = r$adducthyp,
        `neutral M` = round(r$neutral_mass, 4), pr2 = round(ion, 4),
        peaks = r$adducts_explained, score = round(r$total_score, 2),
        check.names = FALSE)
      names(disp)[4] <- pr                      # the molecular-ion column, e.g. [M+H]+
      # Sortable + scrollable so the full list shows — click the "neutral M" or the
      # molecular-ion header to bring the heaviest (molecular-ion) hypothesis up.
      datatable(disp, rownames = FALSE, selection = "single",
                options = list(dom = "t", paging = FALSE, ordering = TRUE,
                               scrollX = TRUE, scrollY = "260px", scrollCollapse = TRUE))
    })

    # Isotope settings (shared by all modes).
    iso_tol <- reactive({
      v <- input$ann_iso_tol
      if (is.null(v) || !is.finite(v) || v < 0) ISO_TOL_DA else v / 1000
    })
    iso_dec <- reactive(isTRUE(input$ann_iso_dec))

    # The annotation result for the current single spectrum (anchor or diff mode).
    ann_result <- reactive({
      req(isTRUE(input$annotate), identical(input$layout, "single"))
      df <- ann_peaks(spec_df()); req(nrow(df) > 0)
      if (identical(input$ann_mode, "diff")) {
        # diff is O(n^2) over the candidate peaks, so it must cap its INPUT by
        # intensity (top-N, or 30 when blank) — there's no per-result cap here.
        cap <- if (is.na(ann_top())) 30L else ann_top()
        return(list(mode = "diff",
                    edges = difference_network(df, input$ann_tol, input$ann_unit,
                                               top_n = cap, rel_floor = 0,
                                               iso_tol = iso_tol(),
                                               iso_decreasing = iso_dec())))
      }
      # anchor ion: typed (manual) or the picked findMAIN hypothesis (auto)
      if (identical(input$ann_mode, "auto")) {
        r <- ranked(); req(nrow(r) > 0)               # silent until Suggest is run
        pick <- min(auto_pick(), nrow(r))
        anchor <- r$adductmz[pick]; adduct <- r$adducthyp[pick]
      } else {
        req(is.finite(input$anchor_mz),
            isTRUE(input$ann_adduct %in% quasi_adducts(input$ann_pol)))
        anchor <- input$anchor_mz; adduct <- input$ann_adduct
      }
      niso <- suppressWarnings(as.integer(input$ann_niso))
      if (is.na(niso) || niso < 0) niso <- 0L
      maxz <- suppressWarnings(as.integer(input$ann_max_z))
      if (is.na(maxz) || maxz < 1) maxz <- Inf
      a <- annotate_anchor(df, anchor, adduct, input$ann_pol,
                           tol = input$ann_tol, unit = input$ann_unit, isotopes = niso,
                           fragments = isTRUE(input$ann_frag), max_charge = maxz,
                           iso_tol = iso_tol(), iso_decreasing = iso_dec())
      list(mode = "anchor", M = a$M, table = cap_matched(a$table, ann_top()),
           ghost = isTRUE(input$ann_ghost))
    })

    plot_gg <- reactive({
      df <- spec_df(); req(nrow(df) > 0)
      unit <- rv$settings$time_unit
      col1 <- brewer_qual(1, rv$settings$qual_palette)
      if (identical(input$layout, "stacked")) {
        # normalise each file and offset vertically
        df <- group_by(df, sample_name)
        df <- mutate(df, intensity = intensity / max(intensity, na.rm = TRUE))
        df <- ungroup(df)
        off <- setNames(seq_along(unique(df$sample_name)) - 1, unique(df$sample_name))
        df$y0 <- off[df$sample_name] * 1.1
        df$y1 <- df$y0 + df$intensity
        df$.tip <- sprintf("%s\nm/z: %.4f", df$sample_name, df$mz)
        p <- ggplot(df, aes(x = mz, ymin = y0, ymax = y1,
                                              color = sample_name, text = .tip)) +
          geom_linerange(linewidth = 0.4) +
          scale_color_manual(
            values = brewer_named(unique(df$sample_name), rv$settings$qual_palette)) +
          labs(x = "m/z", y = NULL, color = NULL) +
          theme_classic() +
          theme(axis.text.y = element_blank(),
                         axis.ticks.y = element_blank())
        return(p)
      }
      df$.tip <- sprintf("m/z: %.4f\nint: %.3g", df$mz, df$intensity)
      # precursor m/z for the displayed scan (single view), if any
      pmz <- NA_real_
      if (identical(input$layout, "single") && is.finite(df$scan[1])) {
        st <- file_scan_table(cur_row()$path)
        pmz <- st$precursorMZ[match(df$scan[1], st$scan)]
        if (length(pmz) != 1 || !is.finite(pmz) || pmz <= 0) pmz <- NA_real_
      }
      ttl <- if (identical(input$layout, "single"))
        sprintf("%s — scan %s @ rt %.4g %s%s", df$sample_name[1],
                if (is.na(df$scan[1])) "?" else df$scan[1],
                rt_to_disp(df$rt[1], unit), unit,
                if (is.finite(pmz)) sprintf("  •  precursor m/z %.4f", pmz) else "")
      else sprintf("rt %.4g %s — %d files", rt_to_disp(df$rt[1], unit), unit,
                   length(unique(df$sample_name)))
      p <- ggplot(df, aes(x = mz, ymin = 0, ymax = intensity, text = .tip)) +
        geom_linerange(linewidth = 0.4, color = col1) +
        labs(x = "m/z", y = "intensity", title = ttl) +
        theme_classic()
      if (is.finite(pmz))
        p <- p + geom_vline(xintercept = pmz, linetype = "dashed",
                                     color = "#d62728", linewidth = 0.5)
      if (identical(input$layout, "facet"))
        p <- p + facet_wrap(~ sample_name, ncol = 1, scales = "free_y")
      # overlay annotations (single view only)
      if (identical(input$layout, "single") && isTRUE(input$annotate)) {
        ar <- tryCatch(ann_result(), error = function(e) NULL)
        if (!is.null(ar)) p <- annotate_layers(p, ar, df, rv$settings$qual_palette)
      }
      p
    })

    keep_zoom <- zoom_keeper("spec")
    output$plot <- renderPlotly({
      p <- finalize_plotly(plot_gg(), "spec", keep_zoom)
      # ggplotly drops geom_text `angle`, so rotate the label traces here. Build
      # first: trace `mode` ("text") is only populated after plotly_build().
      if (isTRUE(input$annotate)) p <- text_traces_vertical(plotly::plotly_build(p))
      p
    })

    # Click a peak -> set the annotation anchor, or add its m/z to the EIC list.
    click <- reactive(suppressWarnings(event_data("plotly_click", source = "spec")))
    observeEvent(click(), {
      ev <- click(); req(ev, !is.null(ev$x))
      mz <- ev$x
      if (isTRUE(input$annotate) && identical(input$click_action, "anchor") &&
          identical(input$layout, "single")) {
        updateNumericInput(session, "anchor_mz", value = round(mz, 4))
        return()
      }
      rv$eic_targets <- bind_rows(rv$eic_targets, new_eic_target(
        mz, tol = rv$settings$default_tol, unit = rv$settings$default_tol_unit))
      showNotification(sprintf("Added m/z %.4f to the EIC list.", mz),
                       type = "message", duration = 2)
    })

    # --- Scan list browser (typed filters; click a row to load that scan) ---
    ns <- session$ns
    scan_tab <- reactive({
      f <- cur_row()
      tab <- file_scan_table(f$path)
      tab$rt_disp <- round(rt_to_disp(tab$rt, rv$settings$time_unit), 4)
      tab
    })
    # Persisted scan-list filter state (survives modal close/reopen).
    sl <- reactiveValues(scan_min = NA, scan_max = NA, rt_min = NA, rt_max = NA,
                         ms = "all", pol = "any", pmz_min = NA, pmz_max = NA, sid = "")
    for (k in c("scan_min","scan_max","rt_min","rt_max","ms","pol","pmz_min","pmz_max","sid"))
      local({ key <- k; observeEvent(input[[paste0("sl_", key)]], {
        sl[[key]] <- input[[paste0("sl_", key)]] }, ignoreInit = TRUE) })

    filtered_scans <- reactive({
      tab <- scan_tab()
      keep <- rep(TRUE, nrow(tab))
      if (isTRUE(is.finite(sl$scan_min))) keep <- keep & tab$scan >= sl$scan_min
      if (isTRUE(is.finite(sl$scan_max))) keep <- keep & tab$scan <= sl$scan_max
      if (isTRUE(is.finite(sl$rt_min)))   keep <- keep & tab$rt_disp >= sl$rt_min
      if (isTRUE(is.finite(sl$rt_max)))   keep <- keep & tab$rt_disp <= sl$rt_max
      if (!is.null(sl$ms) && sl$ms != "all") keep <- keep & tab$msLevel == as.integer(sl$ms)
      if (!is.null(sl$pol) && sl$pol != "any") {
        pcode <- if (identical(sl$pol, "pos")) 1L else 0L
        keep <- keep & tab$polarity == pcode
      }
      if (isTRUE(is.finite(sl$pmz_min))) keep <- keep & tab$precursorMZ >= sl$pmz_min
      if (isTRUE(is.finite(sl$pmz_max))) keep <- keep & tab$precursorMZ <= sl$pmz_max
      if (!is.null(sl$sid) && nzchar(sl$sid))
        keep <- keep & grepl(sl$sid, tab$spectrumId, fixed = TRUE)
      # NA fields (e.g. MS1 precursor m/z, unset polarity) make a clause NA, which
      # would materialize all-NA phantom rows in the DT — drop those rows.
      keep[is.na(keep)] <- FALSE
      tab[keep, , drop = FALSE]
    })
    observeEvent(input$scanlist, {
      ms_choices <- c("all", sort(unique(scan_tab()$msLevel)))
      u <- rv$settings$time_unit
      showModal(modalDialog(
        title = paste("Scans —", cur_row()$name), size = "xl", easyClose = TRUE,
        helpText("Type filters (blank = no limit); click a row to load that scan."),
        layout_columns(
          col_widths = c(2, 2, 2, 2, 2, 2),
          numericInput(ns("sl_scan_min"), "scan ≥", sl$scan_min),
          numericInput(ns("sl_scan_max"), "scan ≤", sl$scan_max),
          numericInput(ns("sl_rt_min"), paste0("rt(", u, ") ≥"), sl$rt_min),
          numericInput(ns("sl_rt_max"), paste0("rt(", u, ") ≤"), sl$rt_max),
          selectInput(ns("sl_ms"), "MS", choices = ms_choices, selected = sl$ms),
          selectInput(ns("sl_pol"), "Polarity", choices = c("any","pos","neg"),
                      selected = sl$pol)),
        layout_columns(
          col_widths = c(3, 3, 6),
          numericInput(ns("sl_pmz_min"), "precursor m/z ≥", sl$pmz_min),
          numericInput(ns("sl_pmz_max"), "precursor m/z ≤", sl$pmz_max),
          textInput(ns("sl_sid"), "spectrumId contains", value = sl$sid)),
        DTOutput(ns("scantable")),
        footer = modalButton("Close")
      ))
    })
    output$scantable <- renderDT({
      tab <- filtered_scans()
      disp <- tab[, c("scan", "rt_disp", "msLevel", "polarity", "precursorMZ",
                      "tic", "basePeakMZ", "spectrumId")]
      names(disp)[2] <- paste0("rt(", rv$settings$time_unit, ")")
      datatable(disp, rownames = FALSE, selection = "single",
                    options = list(pageLength = 15, scrollX = TRUE))
    })
    observeEvent(input$scantable_rows_selected, {
      i <- input$scantable_rows_selected; req(length(i) == 1)
      updateRadioButtons(session, "layout", selected = "single")
      updateNumericInput(session, "scan", value = filtered_scans()$scan[i])
      removeModal()
    })

    mod_export_server("export", plot_gg, rv, "spectrum")
  })
}

#' Add adduct/isotope/fragment (or difference-network) layers to the single-view
#' spectrum ggplot. Colours come from the qualitative ColorBrewer palette
#' (indices 2-4, leaving index 1 = the spectrum itself). Built as conditional
#' geoms with explicit data, never by mutating the base aes (ggplot2 v4 / S7).
#' @importFrom ggplot2 geom_point geom_text geom_segment scale_color_manual aes labs
#' @noRd
annotate_layers <- function(p, ar, df, palette) {
  ymax <- max(df$intensity, na.rm = TRUE)
  pal4 <- brewer_qual(4, palette)
  if (identical(ar$mode, "diff")) {
    e <- ar$edges
    if (!nrow(e)) return(p)
    e$y <- ymax * (1.06 + 0.05 * (seq_len(nrow(e)) - 1))   # stack brackets
    e$xmid <- (e$mz_lo + e$mz_hi) / 2
    e$lab <- sprintf("Δ %.4f\n%s", e$delta, e$origin)
    e$.tip <- e$lab
    return(p +
      geom_segment(data = e, aes(x = mz_lo, xend = mz_hi, y = y, yend = y, text = .tip),
                   inherit.aes = FALSE, color = pal4[2], linewidth = 0.4) +
      geom_text(data = e, aes(x = xmid, y = y, label = sprintf("%.4f", delta)),
                inherit.aes = FALSE, vjust = -0.3, size = 2.6, color = pal4[2]))
  }
  tab <- ar$table
  hit <- tab[tab$matched, , drop = FALSE]
  cols <- c(adduct = pal4[2], isotope = pal4[3], fragment = pal4[4])
  if (nrow(hit)) {
    hit <- collapse_hits(hit)   # one label per observed peak, "; "-joined
    hit$.tip <- sprintf("%s\nm/z %.4f (%.1f ppm)", hit$label, hit$mz_obs, hit$ppm_err)
    p <- p +
      geom_point(data = hit, aes(x = mz_obs, y = intensity, color = type, text = .tip),
                 inherit.aes = FALSE, size = 1.8) +
      # labels written vertically (angle 90) so dense clusters don't overlap
      geom_text(data = hit, aes(x = mz_obs, y = intensity, label = label, color = type),
                inherit.aes = FALSE, angle = 90, hjust = 0, vjust = 0.5,
                nudge_y = ymax * 0.02, size = 2.7, show.legend = FALSE) +
      scale_color_manual(values = cols, name = NULL)
  }
  if (isTRUE(ar$ghost)) {
    miss <- tab[!tab$matched, , drop = FALSE]
    if (nrow(miss)) {
      miss$.tip <- sprintf("expected %s\nm/z %.4f (absent)", miss$label, miss$mz)
      p <- p + geom_segment(
        data = miss, aes(x = mz, xend = mz, y = 0, yend = ymax * 0.03, text = .tip),
        inherit.aes = FALSE, color = "grey70", linewidth = 0.3)
    }
  }
  p
}

#' Collapse matched annotations that land on the same observed peak into one row,
#' joining their labels with "; ". When several ion types coincide on a peak the
#' colour/representative type is the highest priority present (adduct > fragment >
#' isotope). Keeps the matched-peak m/z, intensity and (first) ppm error.
#' @importFrom tibble tibble
#' @noRd
collapse_hits <- function(hit) {
  prio <- c("adduct", "fragment", "isotope")
  parts <- split(hit, round(hit$mz_obs, 4))
  do.call(rbind, lapply(parts, function(g) {
    g <- g[order(match(g$type, prio)), , drop = FALSE]
    tibble(mz_obs = g$mz_obs[1], intensity = g$intensity[1],
           label = paste(unique(g$label), collapse = "; "),
           type = g$type[1], ppm_err = g$ppm_err[1])
  }))
}

#' Keep only the N most intense ANNOTATED peaks (top-N applies to hits, not to the
#' input spectrum). Unmatched rows (ghost candidates) are always retained; ties
#' broken by intensity. `n = NA` keeps everything.
#' @noRd
cap_matched <- function(tab, n) {
  if (is.na(n)) return(tab)
  m <- tab[tab$matched, , drop = FALSE]
  if (nrow(m) == 0) return(tab)
  keep <- utils::head(unique(m$mz_obs[order(-m$intensity)]), n)   # top-N distinct peaks
  tab[!tab$matched | tab$mz_obs %in% keep, , drop = FALSE]
}

#' Render the annotation labels vertically. ggplotly turns geom_text into scatter
#' text traces, and this plotly.js (2.25) ignores `textangle` on those — but it
#' does honour it on LAYOUT ANNOTATIONS. So convert each text trace's labels into
#' layout annotations (rotated -90, reading upward, anchored above the peak) and
#' drop the now-redundant text trace. Operate on a built object so trace `mode`,
#' `x`/`y`/`text` and `textfont` are populated.
#' @noRd
text_traces_vertical <- function(p) {
  d <- p$x$data
  if (is.null(d)) return(p)
  anns <- p$x$layout$annotations
  if (is.null(anns)) anns <- list()
  keep <- rep(TRUE, length(d))
  for (i in seq_along(d)) {
    tr <- d[[i]]
    if (is.null(tr$mode) || !grepl("text", tr$mode)) next
    keep[i] <- FALSE
    txt <- tr$text; xs <- tr$x; ys <- tr$y
    col <- tr$textfont$color %||% "black"
    for (j in seq_along(txt)) {
      if (is.na(txt[j]) || !nzchar(txt[j])) next
      anns[[length(anns) + 1L]] <- list(
        x = xs[j], y = ys[j], text = txt[j], textangle = -90,
        showarrow = FALSE, xanchor = "center", yanchor = "bottom",
        font = list(size = 10, color = if (length(col) > 1) col[j] else col))
    }
  }
  p$x$data <- d[keep]
  p$x$layout$annotations <- anns
  p
}
