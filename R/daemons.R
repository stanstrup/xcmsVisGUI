# Async backend (mirai) + per-run runtime setup (formerly the side-effecting
# tail of global.R). These run when the app launches, NOT on package load —
# spawning worker processes / setting global options belongs to run_app().

# Default daemon count: one per core, leaving one free.
.default_daemons <- function() max(1L, parallel::detectCores() - 1L)

#' (Re)size the mirai daemon pool used by the async file readers.
#' @param n number of daemons (>= 1).
#' @return the daemon count actually set.
set_daemons <- function(n = .default_daemons()) {
  n <- max(1L, as.integer(n))
  mirai::daemons(0)        # reset any existing pool
  mirai::daemons(n)
  n
}

#' One-time runtime setup performed by run_app(): seed the daemon pool, ship mzR
#' to the workers (they only read headers via mzR — fast, no BiocParallel), and
#' allow large uploads. SerialParam is registered in .onLoad, not here.
setup_runtime <- function() {
  set_daemons()
  mirai::everywhere(suppressPackageStartupMessages(library(mzR)))
  options(shiny.maxRequestSize = 5 * 1024^3)
  invisible(TRUE)
}
