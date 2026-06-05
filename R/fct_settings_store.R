# Persist the Settings-tab values across app restarts. Stored as JSON in the
# per-user config directory (tools::R_user_dir) so it is independent of where the
# app is launched from and never lands in the project tree. Only user
# preferences are saved — not transient/session state.

# Fields persisted (a stable allow-list; anything else in settings is ignored).
.PERSISTED_SETTINGS <- c(
  "time_unit", "qual_palette", "seq_palette", "invert_scale",
  "default_tol", "default_tol_unit", "daemons",
  "export_format", "export_width", "export_height", "export_units", "export_dpi")

#' Path to the persisted settings file (per-user config dir).
#' @importFrom tools R_user_dir
#' @noRd
settings_file <- function() {
  file.path(R_user_dir("xcmsVisGUI", "config"), "settings.json")
}

#' Load persisted settings as a named list (known fields only). Returns an empty
#' list when nothing is saved or the file is missing/unreadable/corrupt — so a
#' bad file never blocks startup.
#' @importFrom jsonlite read_json
#' @noRd
load_settings <- function() {
  f <- settings_file()
  if (!file.exists(f)) return(list())
  out <- tryCatch(read_json(f, simplifyVector = TRUE),
                  error = function(e) list())
  if (!is.list(out)) return(list())
  out[intersect(names(out), .PERSISTED_SETTINGS)]
}

#' Write the persisted subset of `settings` (a plain list, e.g. from
#' reactiveValuesToList(rv$settings)) to disk, creating the config dir. Failures
#' warn rather than error — saving settings must never crash the app.
#' @importFrom jsonlite write_json
#' @noRd
save_settings <- function(settings) {
  f <- settings_file()
  keep <- settings[intersect(names(settings), .PERSISTED_SETTINGS)]
  tryCatch({
    dir.create(dirname(f), recursive = TRUE, showWarnings = FALSE)
    write_json(keep, f, auto_unbox = TRUE, pretty = TRUE)
  }, error = function(e) warning("Could not save settings: ", conditionMessage(e)))
  invisible(f)
}
