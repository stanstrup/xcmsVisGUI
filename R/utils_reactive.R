# Central reactive state shared across modules.

#' Create the app-wide reactive store. One instance lives in the main server
#' and is passed to every module.
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
      time_unit    = "min",          # "min" | "sec" — display unit for rt
      qual_palette = "Set1",
      seq_palette  = "viridis",
      invert_scale = TRUE,
      default_tol      = 10,         # default EIC tolerance for new targets
      default_tol_unit = "ppm",      # "ppm" | "Da"
      daemons      = max(1L, parallel::detectCores() - 1L),
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
new_eic_target <- function(mz, tol = 10, unit = "ppm",
                           label = sprintf("m%.4f", mz)) {
  tibble::tibble(label = label, mz = mz, tol = tol, unit = unit,
                 rt_min = NA_real_, rt_max = NA_real_, enabled = TRUE)
}

#' Standard notification for files skipped by extract_over_files (one bad file in
#' a multi-file plot is reported, not fatal). Pass as the `on_error` callback.
notify_read_failures <- function(names) {
  shiny::showNotification(
    paste0("Skipped unreadable file(s): ", paste(names, collapse = ", ")),
    type = "warning", duration = 6)
}

#' Register the click/relayout/doubleclick events on a plotly object. Used by
#' every interactive plot so clicks and zoom-persistence reach the server.
register_plotly_events <- function(p) {
  p %>%
    plotly::event_register("plotly_click") %>%
    plotly::event_register("plotly_relayout") %>%
    plotly::event_register("plotly_doubleclick")
}

#' Convert a ggplot to plotly and finalize it for an interactive plot module:
#' tooltip from the `text` aes, dynamic ticks, zoom persistence, and event
#' registration. `keep_zoom` is the function returned by `zoom_keeper(source)`.
#' Collapses the identical render tail repeated in every ggplot-based plot module.
finalize_plotly <- function(gg, source, keep_zoom) {
  plotly::ggplotly(gg, source = source, tooltip = "text", dynamicTicks = TRUE) %>%
    keep_zoom() %>%
    register_plotly_events()
}

#' Wire a plotly click on `source` to `rv$selection` (drives the linked Spectrum
#' view). `file_id` comes from the click `key` aesthetic; `mz_from(ev)` yields the
#' m/z (default NA). Call ONCE inside a moduleServer. `suppressWarnings` hides the
#' benign "source not registered" notice emitted before the first render.
wire_selection <- function(source, plot, rv, mz_from = function(ev) NA_real_) {
  click <- shiny::reactive(suppressWarnings(
    plotly::event_data("plotly_click", source = source)))
  shiny::observeEvent(click(), {
    ev <- click(); shiny::req(ev)
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
zoom_keeper <- function(source) {
  z <- reactiveValues(x = NULL, y = NULL)
  # Only STORE ranges from user zoom/pan. We must NOT clear on autorange here:
  # a re-render emits an autorange relayout that would wipe the saved zoom.
  observeEvent(event_data("plotly_relayout", source = source), {
    e <- suppressWarnings(event_data("plotly_relayout", source = source))
    if (is.null(e)) return()
    if (!is.null(e[["xaxis.range[0]"]]))
      z$x <- c(e[["xaxis.range[0]"]], e[["xaxis.range[1]"]])
    if (!is.null(e[["yaxis.range[0]"]]))
      z$y <- c(e[["yaxis.range[0]"]], e[["yaxis.range[1]"]])
  }, ignoreInit = TRUE)
  # A genuine reset is a double-click -> forget the zoom.
  observeEvent(event_data("plotly_doubleclick", source = source), {
    z$x <- NULL; z$y <- NULL
  }, ignoreInit = TRUE)
  function(p) {
    zx <- isolate(z$x); zy <- isolate(z$y)
    if (!is.null(zx)) p <- plotly::layout(p, xaxis = list(range = zx, autorange = FALSE))
    if (!is.null(zy)) p <- plotly::layout(p, yaxis = list(range = zy, autorange = FALSE))
    p
  }
}
