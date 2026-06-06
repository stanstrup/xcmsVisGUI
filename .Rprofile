# Skip renv's startup synchronization check. It re-scans the whole dependency
# tree against renv.lock on every R launch (~2.6 s here; ~3.3 s -> 0.7 s startup),
# and the app spawns fresh R for each mirai daemon, so it adds up. Drift from the
# lockfile is checked on demand instead: run renv::status() / renv::snapshot()
# manually. Must be set before activate.R sources renv (which runs the check).
Sys.setenv(RENV_CONFIG_SYNCHRONIZED_CHECK = "FALSE")
source("renv/activate.R")
