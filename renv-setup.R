# One-shot dependency install for the renv library, then snapshot.
#
# Run with the project's R (renv auto-activates via .Rprofile):
#
#   Rscript renv-setup.R
#
# Installs everything declared in DESCRIPTION -- Imports + Suggests and the
# Remotes (github::stanstrup/commonMZ) -- so it stays in sync with DESCRIPTION
# and never drifts out of a hand-maintained package list. Use this (rather than
# renv::restore()) after upgrading R to a new version: it picks the Bioconductor
# release that matches the running R, then re-snapshots renv.lock to match.

options(
  renv.config.pak.enabled = FALSE,
  Ncpus = max(1L, parallel::detectCores() - 1L)
)

# Install the project's declared dependencies and its Remotes from DESCRIPTION
# (Imports incl. commonMZ + InterpretMSSpectrum; the RforMassSpectrometry stack).
renv::install(dependencies = TRUE, prompt = FALSE)

# The Bioconductor experiment-data packages are only referenced indirectly in
# tests (skip_if_not_installed + system.file), so renv's code scan misses them;
# install them explicitly so the real-data tests run rather than skip.
renv::install(c("bioc::msdata", "bioc::faahKO"), prompt = FALSE)

# Snapshot the installed library into renv.lock.
renv::snapshot(prompt = FALSE)

cat("\n=== renv setup complete ===\n")
