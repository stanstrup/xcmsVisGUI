# One-shot dependency install for the renv library, then snapshot.
#
# Run with the project's R (renv auto-activates via .Rprofile):
#
#   Rscript renv-setup.R
#
# Installs the DEPENDENCIES declared in DESCRIPTION (Imports + Suggests) plus the
# GitHub remote (commonMZ) -- NOT xcmsVisGUI itself, which is this project and
# isn't on any repository. Reading DESCRIPTION keeps it in sync automatically.
# renv routes each package to CRAN or Bioconductor (the `biocViews` field marks
# this a Bioconductor project) and picks the Bioc release matching the running R,
# so this also provisions a fresh library after an R upgrade.

options(
  repos = c(CRAN = "https://cloud.r-project.org"),  # ensure a CRAN mirror is set
  renv.config.pak.enabled = FALSE,
  Ncpus = max(1L, parallel::detectCores() - 1L)
)

# Parse a comma-separated DESCRIPTION field into bare package names.
desc_field <- function(field) {
  v <- read.dcf("DESCRIPTION", fields = field)[, field]
  if (is.na(v)) return(character())
  p <- trimws(gsub("\\s*\\(.*?\\)", "", strsplit(v, ",")[[1]]))  # drop version notes
  p[nzchar(p)]
}

# Everything declared, minus: R itself, base/recommended packages (ship with R),
# and commonMZ (installed from its GitHub remote below).
base_pkgs <- rownames(installed.packages(priority = c("base", "recommended")))
pkgs <- setdiff(unique(c(desc_field("Imports"), desc_field("Suggests"))),
                c("R", base_pkgs, "commonMZ"))

renv::install(c(pkgs, "github::stanstrup/commonMZ"), prompt = FALSE)

# Snapshot the installed library into renv.lock.
renv::snapshot(prompt = FALSE)

cat("\n=== renv setup complete ===\n")
