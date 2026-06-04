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
      color  = character(),
      enabled = logical()
    ),

    # Last plotly click that should drive the linked spectrum view.
    selection = NULL,        # list(plot, file_id, rt, mz)

    # Shared "active file" for the single-file views (Spectrum, MS map).
    active_file = NULL,      # a file id

    # Global filter state (mod_filter).
    filter = list(
      rt_min = NA_real_, rt_max = NA_real_,
      mz_min = NA_real_, mz_max = NA_real_,
      ms_level = 1L, polarity = "any",
      int_min = NA_real_, int_max = NA_real_,
      charge = NA_integer_, spectrum_id = ""
    ),

    # User settings (mod_settings).
    settings = list(
      backend      = "MsBackendMzR",
      time_unit    = "min",          # "min" | "sec" — display unit for rt
      qual_palette = "Set1",
      seq_palette  = "viridis",
      invert_scale = TRUE,
      daemons      = max(1L, parallel::detectCores() - 1L),
      export_format = "png",
      export_width  = 8,
      export_height = 5,
      export_units  = "in",
      export_dpi    = 300
    )
  )
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

#' Convenience: ids of files currently included for plotting.
included_file_ids <- function(rv) {
  f <- rv$files
  if (nrow(f) == 0) return(character())
  f$id[f$include & f$status == "ready"]
}

#' Construct a Spectra backend object from a settings string.
make_backend <- function(backend = "MsBackendMzR") {
  switch(
    backend,
    MsBackendMzR    = Spectra::MsBackendMzR(),
    MsBackendMemory = Spectra::MsBackendMemory(),
    MsBackendSql    = Spectra::MsBackendMzR(),  # Sql needs a db handle; read via MzR then setBackend downstream
    Spectra::MsBackendMzR()
  )
}
