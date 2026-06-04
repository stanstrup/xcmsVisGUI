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

    # Global filter state (mod_filter).
    filter = list(
      rt_min = NA_real_, rt_max = NA_real_,
      mz_min = NA_real_, mz_max = NA_real_,
      ms_level = 1L, polarity = "any",
      int_min = NA_real_
    ),

    # User settings (mod_settings).
    settings = list(
      backend      = "MsBackendMzR",
      time_unit    = "min",          # "min" | "sec" — display unit for rt
      qual_palette = "Set1",
      seq_palette  = "YlOrRd",
      daemons      = max(1L, parallel::detectCores() - 1L),
      export_format = "png",
      export_width  = 8,
      export_height = 5,
      export_units  = "in",
      export_dpi    = 300
    )
  )
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
