# run.R — convenience launcher.
#
# On a fresh machine:  Rscript run.R
# renv auto-activates via .Rprofile; global.R restores the library from
# renv.lock on first boot, then the app starts.

shiny::runApp(".", launch.browser = TRUE)
