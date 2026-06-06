# Persistent cache for the heavy extraction reactives. bindCache results (TIC/BPC
# and EIC tibbles) go into a LAYERED memory+disk cache: memory is the fast primary
# (within-session hits never touch disk), disk is the persistent backing so that
# re-opening the app and re-adding the same files + filter is instant instead of
# re-running build_msexp() + chromatogram().
#
# The disk layer serialises with qs2 at compress_level 0 rather than cachem's
# built-in gzip RDS: for this app's result sizes (a 140-file TIC/EIC is easily
# 0.5-1.5M rows) gzip writes take 1.5-4 s, while qs2 L0 is ~0.1-0.4 s with similar
# file size. The raw MsExperiment is kept in a session (memory) cache only — not
# worth disk-serialising an S4 object with a file-backed backend (see run_app.R).

#' A cachem-compatible disk cache that serialises with qs2 (compress_level 0).
#' Implements the cachem cache interface so it can be used in cache_layered() and
#' as a bindCache() store. Files are `<key>.qs2`; keys are the (filename-safe)
#' hashes bindCache produces. Eviction is by total size / age / count, oldest
#' (least-recently-read) first.
#' @importFrom qs2 qs_save qs_read
#' @importFrom cachem key_missing
#' @noRd
cache_disk_qs2 <- function(dir, max_size = 2 * 1024^3, max_age = Inf,
                           max_n = Inf, compress_level = 0L) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  destroyed <- FALSE
  pathof <- function(key) file.path(dir, paste0(key, ".qs2"))

  do_prune <- function() {
    fs <- list.files(dir, pattern = "\\.qs2$", full.names = TRUE)
    if (!length(fs)) return(invisible())
    nfo <- file.info(fs)
    nfo <- nfo[order(nfo$mtime), , drop = FALSE]          # oldest first
    fs <- rownames(nfo)
    drop <- rep(FALSE, length(fs))
    if (is.finite(max_age))
      drop <- drop | as.numeric(difftime(Sys.time(), nfo$mtime, units = "secs")) > max_age
    if (is.finite(max_n) && length(fs) > max_n)
      drop[seq_len(length(fs) - max_n)] <- TRUE
    if (is.finite(max_size)) {
      # remove oldest until the kept files fit under max_size
      keep_sz <- rev(cumsum(rev(nfo$size[!drop])))
      over <- which(!drop)[keep_sz > max_size]
      drop[over] <- TRUE
    }
    if (any(drop)) unlink(fs[drop])
    invisible()
  }

  structure(list(
    get = function(key, missing = key_missing()) {
      p <- pathof(key)
      if (!file.exists(p)) return(missing)
      val <- tryCatch(qs_read(p), error = function(e) NULL)
      if (is.null(val)) { unlink(p); return(missing) }
      try(Sys.setFileTime(p, Sys.time()), silent = TRUE)   # LRU touch
      val
    },
    set = function(key, value) {
      tmp <- paste0(pathof(key), ".", Sys.getpid(), ".tmp")
      qs_save(value, tmp, compress_level = compress_level)
      suppressWarnings(file.remove(pathof(key)))
      if (!file.rename(tmp, pathof(key))) {
        file.copy(tmp, pathof(key), overwrite = TRUE); unlink(tmp)
      }
      do_prune()
      invisible(TRUE)
    },
    exists = function(key) file.exists(pathof(key)),
    remove = function(key) { unlink(pathof(key)); invisible(TRUE) },
    reset  = function() {
      unlink(list.files(dir, pattern = "\\.qs2$", full.names = TRUE)); invisible(TRUE)
    },
    keys   = function() sub("\\.qs2$", "", list.files(dir, pattern = "\\.qs2$")),
    prune  = function() { do_prune(); invisible(TRUE) },
    size   = function() length(list.files(dir, pattern = "\\.qs2$")),
    info   = function() list(class = "cache_disk_qs2", dir = dir,
                             max_size = max_size, max_age = max_age, max_n = max_n,
                             evict = "lru"),
    destroy      = function() { unlink(dir, recursive = TRUE); destroyed <<- TRUE; invisible(TRUE) },
    is_destroyed = function() destroyed
  ), class = c("cache_disk_qs2", "cachem"))
}

#' Layered (memory + disk/qs2) cachem cache backing the app's bindCache() calls
#' (the app-level cache, wired in via shinyOptions() in setup_runtime()). One
#' instance per process; disk lives under tools::R_user_dir("xcmsVisGUI","cache")
#' and is evicted past ~2 GB or 30 days.
#' @importFrom cachem cache_mem cache_layered
#' @importFrom tools R_user_dir
#' @noRd
app_cache <- local({
  cache <- NULL
  function() {
    if (is.null(cache))
      cache <<- cache_layered(
        cache_mem(max_size = 512 * 1024^2),
        cache_disk_qs2(dir = file.path(R_user_dir("xcmsVisGUI", "cache"), "bindcache"),
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
