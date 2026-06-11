# run.R — convenience launcher.
#
#   Rscript run.R
#
# Loads the package from source (pkgload::load_all, so edits live-reload) and
# starts the app. Install the dependencies first -- see the Developer guide:
# remotes::install_deps(dependencies = TRUE). For an installed package use
# instead:  xcmsVisGUI::run_app(launch.browser = TRUE)

pkgload::load_all(".", quiet = TRUE)
run_app(launch.browser = TRUE)
