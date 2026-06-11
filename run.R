# run.R — dev convenience launcher.
#
#   Rscript run.R
#
# Runs the app from the cloned SOURCE via pkgload::load_all(): it loads R/ as the
# package namespace without installing, and reflects edits live (the dev iterate
# loop). End users don't use this -- they install the package and call
# xcmsVisGUI::run_app(); installing the clone (remotes::install_local(".") +
# library(xcmsVisGUI)) works too, but reinstalls on every edit.
#
# Install the package's dependencies first (Developer guide:
# remotes::install_deps(dependencies = TRUE)). pkgload is the one extra tool the
# launcher needs and it isn't a package dependency, so fetch it on demand:
if (!requireNamespace("pkgload", quietly = TRUE))
  install.packages("pkgload", repos = "https://cloud.r-project.org")

pkgload::load_all(".", quiet = TRUE)
run_app(launch.browser = TRUE)
