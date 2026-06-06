# Persistent cache for the heavy extraction reactives. bindCache results (TIC/BPC
# and EIC tibbles) go into a LAYERED memory+disk cache: memory is the fast primary
# (within-session hits never touch disk), disk is the persistent backing so that
# re-opening the app and re-adding the same files + filter is instant instead of
# re-running build_msexp() + chromatogram(). The disk write on a miss is small and
# synchronous (~20 ms for a multi-file TIC) — dwarfed by the extraction it saves.
# The raw MsExperiment itself is kept in an in-memory (session) cache — not worth
# disk-serialising an S4 object with a file-backed backend (see run_app.R).

#' Layered (memory + disk) cachem cache backing the app's bindCache() calls (the
#' app-level cache, wired in via shinyOptions() in setup_runtime()). One instance
#' per process; disk lives under tools::R_user_dir("xcmsVisGUI", "cache") and is
#' evicted past ~2 GB or 30 days.
#' @importFrom cachem cache_disk cache_mem cache_layered
#' @importFrom tools R_user_dir
#' @noRd
app_cache <- local({
  cache <- NULL
  function() {
    if (is.null(cache))
      cache <<- cache_layered(
        cache_mem(max_size = 512 * 1024^2),
        cache_disk(dir = file.path(R_user_dir("xcmsVisGUI", "cache"), "bindcache"),
                   max_size = 2 * 1024^3, max_age = 30 * 24 * 3600))
    cache
  }
})

#' Empty the persistent bindCache (called from clear_ms_caches / "Clear all").
#' @noRd
clear_disk_cache <- function() {
  tryCatch(app_cache()$reset(), error = function(e) NULL)
  invisible(NULL)
}
