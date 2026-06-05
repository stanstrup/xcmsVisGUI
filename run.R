# run.R — convenience launcher.
#
#   Rscript run.R
#
# renv auto-activates via .Rprofile. Loads the package from source (no install
# needed for dev) and starts the app. For an installed package use instead:
#   xcmsVisGUI::run_app(launch.browser = TRUE)

pkgload::load_all(".", quiet = TRUE)
run_app(launch.browser = TRUE)
