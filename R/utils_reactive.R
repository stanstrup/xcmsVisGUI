# Central reactive state shared across modules.

#' Create the app-wide reactive store. One instance lives in the main server
#' and is passed to every module.
#' @importFrom tibble tibble
#' @importFrom parallel detectCores
#' @noRd
make_rv <- function() {
  reactiveValues(
    # Per-file metadata; grows as async reads resolve. One row per file.
    files = tibble(
      id          = character(),
      path        = character(),
      name        = character(),
      sample_group = character(),
      include     = logical(),
      status      = character(),   # "reading" | "ready" | "error"
      n_spectra   = integer(),
      rt_min      = numeric(),
      rt_max      = numeric(),
      mz_min      = numeric(),
      mz_max      = numeric(),
      ms_levels   = character(),
      polarities  = character(),
      charges     = character(),
      spec_mode   = character(),   # "profile" | "centroid" | "mixed" | NA
      message     = character()
    ),

    # Editable EIC target table (mod_plot_eic).
    eic_targets = tibble(
      label  = character(),
      mz     = numeric(),
      tol    = numeric(),
      unit   = character(),  # "ppm" | "Da"
      rt_min = numeric(),
      rt_max = numeric(),
      enabled = logical()
    ),

    # Last plotly click that should drive the linked spectrum view.
    selection = NULL,        # list(plot, file_id, rt, mz)

    # Global filter state (mod_filter). Shape defined once in empty_filter().
    filter = empty_filter(),

    # User settings (mod_settings). A NESTED reactiveValues so each field is its
    # own reactive: changing the palette doesn't invalidate time-unit consumers
    # (a plain list slot would fan out every settings change to every reader).
    settings = reactiveValues(
      time_unit    = "min",          # "min" | "sec" \u2014 display unit for rt
      qual_palette = "Set1",
      seq_palette  = "viridis",
      invert_scale = TRUE,
      default_tol      = 10,         # default EIC tolerance for new targets
      default_tol_unit = "ppm",      # "ppm" | "Da"
      daemons      = max(1L, detectCores() - 1L),
      export_format = "png",
      export_width  = 8,
      export_height = 5,
      export_units  = "in",
      export_dpi    = 300
    )
  )
}

#' Construct EIC target row(s) with the shared defaults (full rt range, enabled)
#' matching the rv$eic_targets schema. `label` defaults to "m<mz>"; vectorised
#' over `mz`. Single home for the target-row literal used by EIC add/paste and
#' the spectrum click-to-add.
#' @importFrom tibble tibble
#' @noRd
new_eic_target <- function(mz, tol = 10, unit = "ppm",
                           label = sprintf("m%.4f", mz)) {
  tibble(label = label, mz = mz, tol = tol, unit = unit,
         rt_min = NA_real_, rt_max = NA_real_, enabled = TRUE)
}

#' Standard notification for files skipped by extract_over_files (one bad file in
#' a multi-file plot is reported, not fatal). Pass as the `on_error` callback.
#' @noRd
notify_read_failures <- function(names) {
  showNotification(
    paste0("Skipped unreadable file(s): ", paste(names, collapse = ", ")),
    type = "warning", duration = 6)
}

#' The plotly events every interactive plot registers (and that the modules
#' query via `event_data`).
PLOTLY_EVENTS <- c("plotly_click", "plotly_relayout", "plotly_doubleclick")

#' Register the click/relayout/doubleclick events on a plotly object. Used by
#' every interactive plot so clicks and zoom-persistence reach the server.
#' @importFrom plotly event_register
#' @noRd
register_plotly_events <- function(p) {
  p %>%
    event_register("plotly_click") %>%
    event_register("plotly_relayout") %>%
    event_register("plotly_doubleclick")
}

#' Pre-seed plotly's per-session registry of event IDs so `event_data()` does
#' not warn before (or unless) the matching plot renders. plotly only marks a
#' source's events "registered" when that plot actually renders
#' (`register_plot_events`); our plot modules live on lazy nav tabs that don't
#' render until visited, yet their `zoom_keeper`/`wire_selection` observers call
#' `event_data` on every flush. event_data defers the registration check to an
#' `onFlushed` callback and `warning()`s there — OUTSIDE any `suppressWarnings`
#' at the call site — so hidden tabs flood the log. Seeding the IDs up front
#' silences that without touching real event delivery (the client side still
#' only emits events for plots that rendered with `event_register`; a later
#' render just re-adds the same IDs via `unique()`).
#' @noRd
prime_plotly_events <- function(session, sources, events = PLOTLY_EVENTS) {
  ids <- as.vector(outer(events, sources, paste, sep = "-"))
  ud <- session$userData
  ud$plotlyShinyEventIDs <- unique(c(ud$plotlyShinyEventIDs, ids))
}

#' Convert a ggplot to plotly and finalize it for an interactive plot module:
#' tooltip from the `text` aes, dynamic ticks, zoom persistence, and event
#' registration. `keep_zoom` is the function returned by `zoom_keeper(source)`.
#' Collapses the identical render tail repeated in every ggplot-based plot module.
#' @importFrom plotly ggplotly
#' @noRd
finalize_plotly <- function(gg, source, keep_zoom) {
  ggplotly(gg, source = source, tooltip = "text", dynamicTicks = TRUE) %>%
    keep_zoom() %>%
    register_plotly_events()
}

#' The aesthetics we pass through ggplot2 purely for plotly's benefit: `text`
#' becomes the tooltip and `key` carries the file id into click events. ggplot2
#' knows neither.
#' @noRd
.PLOTLY_ONLY_AES <- c("text", "key")

#' Evaluate plot-building code, muffling ONLY the "Ignoring unknown aesthetics"
#' warning for the plotly-only aesthetics above.
#'
#' ggplot2 checks a layer's own mapping against the geom's known aesthetics and
#' warns at layer-construction time, so any `geom_*(data = ..., aes(text = ...))`
#' emits one. It is telling us something we already know and rely on: `text` is
#' inert in ggplot2 and read later by ggplotly(). A plot-level `aes()` is not
#' checked, which is why only the extra layers warn.
#'
#' Deliberately narrow — a warning naming any OTHER unknown aesthetic is a real
#' typo and still surfaces, as does every non-aesthetic warning.
#' @noRd
with_plotly_aes <- function(expr) {
  withCallingHandlers(expr, warning = function(w) {
    m <- conditionMessage(w)
    if (!grepl("^Ignoring unknown aesthetics", m)) return()
    named <- strsplit(sub("^[^:]*:", "", m), ",| and ")[[1]]
    named <- trimws(named); named <- named[nzchar(named)]
    if (length(named) && all(named %in% .PLOTLY_ONLY_AES))
      invokeRestart("muffleWarning")
  })
}

#' Shared "Peak picking" panel for the views that draw peaks (Spectrum, MS map).
#' Peak picking is data PROCESSING, so it lives in each view's own panel, not the
#' global Filters. The sub-controls (S/N, half-window, m/z refinement) expose the
#' Spectra::pickPeaks() knobs and show for any mode other than raw. `default_mode`
#' differs per view: the Spectrum view opens on the raw trace ("off"), the MS map
#' on auto-detect ("auto") since raw is tens of millions of points there.
#' `overlay = TRUE` (Spectrum only) adds a "Raw + centroids overlay" mode that
#' draws the raw trace AND the picked centroids over it.
#' Pair with read_centroid_spec(input) in the module server.
#' @noRd
centroid_controls_ui <- function(ns, default_mode = "off", overlay = FALSE) {
  choices <- c("Raw — no peak picking" = "off",
               "Centroid profile scans" = "auto",
               "Force centroid (all scans)" = "on")
  # overlay slots in right after "Raw": it is a raw view with centroids drawn on top.
  if (isTRUE(overlay))
    choices <- append(choices, c("Raw + centroids overlay" = "overlay"), after = 1L)
  tagList(
    selectInput(ns("cmode"), "Peak picking", width = "100%", choices,
                selected = default_mode),
    conditionalPanel(
      sprintf("input['%s'] != 'off'", ns("cmode")),
      div(class = "d-flex gap-2",
          numericInput(ns("csnr"), "S/N", value = 0, min = 0, step = 1, width = "90px"),
          numericInput(ns("chws"), "Half-window", value = 2, min = 1, step = 1,
                       width = "120px")),
      numericInput(ns("ck"), "m/z accuracy: average ±N points", value = 0,
                   min = 0, step = 1),
      tags$small(class = "text-muted d-block",
                 "Profile scans are peak-picked; already-centroided scans pass ",
                 "through untouched. S/N drops noise peaks; half-window is the ",
                 "local-maximum window. m/z accuracy > 0 replaces each peak's apex ",
                 "m/z with the intensity-weighted mean of its ±N neighbouring ",
                 "raw samples (sub-sample centroiding); 0 keeps the apex."))
  )
}

#' Read the shared peak-picking controls (centroid_controls_ui) into a
#' centroid_spec(). The Spectrum "overlay" mode shows the RAW spectrum (with
#' centroids drawn separately), so it maps to mode "off" for the main extraction.
#' @noRd
read_centroid_spec <- function(input) {
  m <- input$cmode %||% "off"
  centroid_spec(mode = if (identical(m, "overlay")) "off" else m,
                snr = input$csnr, hws = input$chws, k = input$ck)
}

#' Wire a plotly click on `source` to `rv$selection` (drives the linked Spectrum
#' view). `file_id` comes from the click `key` aesthetic; `mz_from(ev)` yields the
#' m/z (default NA). Call ONCE inside a moduleServer. (The "source not registered"
#' warning is silenced up front by `prime_plotly_events`.)
#' @importFrom plotly event_data
#' @noRd
wire_selection <- function(source, plot, rv, mz_from = function(ev) NA_real_) {
  click <- reactive(event_data("plotly_click", source = source))
  observeEvent(click(), {
    ev <- click(); req(ev)
    rv$selection <- list(plot = plot, file_id = ev$key,
                         rt = rt_to_sec(ev$x, rv$settings$time_unit),
                         mz = mz_from(ev))
  })
}

#' Persist 2D zoom across re-renders. Call ONCE inside a moduleServer with the
#' plot's plotly `source`; it returns a function to pipe a plotly object through.
#' The stored range is read with isolate() so a user zoom does NOT re-trigger the
#' render (that caused an autorange/snap-back feedback loop); it is only re-applied
#' when the plot re-renders for data/cosmetic reasons. Cleared on double-click.
#' @importFrom plotly event_data layout
#' @noRd
zoom_keeper <- function(source) {
  z <- reactiveValues(x = NULL, y = NULL)
  # Track zoom PER AXIS: a reported range pins that axis; a reported autorange
  # CLEARS it. Clearing per-axis (never both at once) is what keeps this safe.
  # A data re-render autoranges only the axes we did NOT pin, so its autorange
  # echo can't wipe a pinned axis — while a genuine x-only zoom (which autoranges
  # y) correctly drops the now-stale y range, instead of leaving it to be
  # re-applied on the next re-render (which snapped the view back — the bug).
  # (The "source not registered" warning is silenced up front by
  # prime_plotly_events.)
  observeEvent(event_data("plotly_relayout", source = source), {
    e <- event_data("plotly_relayout", source = source)
    if (is.null(e)) return()
    if (!is.null(e[["xaxis.range[0]"]]))
      z$x <- c(e[["xaxis.range[0]"]], e[["xaxis.range[1]"]])
    else if (isTRUE(e[["xaxis.autorange"]])) z$x <- NULL
    if (!is.null(e[["yaxis.range[0]"]]))
      z$y <- c(e[["yaxis.range[0]"]], e[["yaxis.range[1]"]])
    else if (isTRUE(e[["yaxis.autorange"]])) z$y <- NULL
  }, ignoreInit = TRUE)
  # A genuine reset is a double-click -> forget the zoom.
  observeEvent(event_data("plotly_doubleclick", source = source), {
    z$x <- NULL; z$y <- NULL
  }, ignoreInit = TRUE)
  function(p) {
    zx <- isolate(z$x); zy <- isolate(z$y)
    if (!is.null(zx)) p <- layout(p, xaxis = list(range = zx, autorange = FALSE))
    if (!is.null(zy)) p <- layout(p, yaxis = list(range = zy, autorange = FALSE))
    p
  }
}
