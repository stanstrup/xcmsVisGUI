# Fine isotope-pattern simulation for a candidate molecular formula, drawn as a
# profile envelope over the raw spectrum. Everything here is pure (no Shiny) so it
# is unit-testable; the app calls it from mod_plot_spectrum.
#
# Pipeline (all reuse the commonMZ adduct rules from fct_annotate.R so the ion m/z
# is defined identically to the adduct annotation):
#   formula_candidates(mass, ...)          Rdisop::decomposeMass -> candidate formulas
#   isotope_pattern(formula, rule, ...)    enviPat fine isotopologues -> ion m/z
#   isotope_profile(pattern, resolution)   Gaussian envelope at a resolving power
# Unlike the spacing-based isotope LABELS in fct_annotate.R (M+1/M+2 at 13C
# spacing), this resolves the true fine structure (13C vs 15N vs 34S vs 2H ...),
# which needs a formula — hence Rdisop to propose formulas from the neutral mass.

#' Candidate neutral molecular formulas for a monoisotopic mass, via Rdisop.
#' Returns tibble(formula, mass, ppm_err, dbe, valid) sorted by |ppm_err|; keeps
#' only chemically valid, non-negative-DBE formulas unless told otherwise.
#' @param mass neutral monoisotopic mass (Da).
#' @param ppm mass tolerance for the search.
#' @param elements element symbols to allow (Rdisop initialises their ranges).
#' @importFrom tibble tibble
#' @noRd
formula_candidates <- function(mass, ppm = 5,
                               elements = c("C", "H", "N", "O", "P", "S"),
                               max_candidates = 25L, valid_only = TRUE,
                               min_dbe = 0) {
  empty <- tibble(formula = character(), mass = numeric(), ppm_err = numeric(),
                  dbe = numeric(), valid = logical())
  if (!isTRUE(is.finite(mass)) || mass <= 0) return(empty)
  mol <- tryCatch(
    Rdisop::decomposeMass(mass, mzabs = 0, ppm = ppm,
                          elements = Rdisop::initializeElements(elements)),
    error = function(e) NULL)
  if (is.null(mol) || !length(mol$formula)) return(empty)
  # Compute the error against the QUERY mass BEFORE building the tibble: inside
  # tibble() the `mass = mol$exactmass` column would shadow the `mass` argument,
  # making every ppm (exactmass - exactmass) = 0.
  ppm_err <- (mol$exactmass - mass) / mass * 1e6
  out <- tibble(
    formula = mol$formula, mass = mol$exactmass, ppm_err = ppm_err,
    dbe = mol$DBE, valid = tolower(mol$valid) == "valid")
  if (isTRUE(valid_only)) out <- out[out$valid, , drop = FALSE]
  if (is.finite(min_dbe)) out <- out[is.finite(out$dbe) & out$dbe >= min_dbe, , drop = FALSE]
  out <- out[order(abs(out$ppm_err)), , drop = FALSE]
  utils::head(out, max_candidates)
}

#' Multiply every element count in a Hill-style formula by `n` (for multimer
#' adducts such as 2M+X). "C8H10N4O2" * 2 -> "C16H20N8O4"; n = 1 is unchanged.
#' @noRd
scale_formula <- function(formula, n = 1L) {
  if (n <= 1L) return(formula)
  m <- gregexpr("([A-Z][a-z]?)([0-9]*)", formula, perl = TRUE)[[1]]
  toks <- regmatches(formula, list(m))[[1]]
  toks <- toks[nzchar(toks)]
  paste0(vapply(toks, function(t) {
    el <- sub("([A-Z][a-z]?).*", "\\1", t)
    cnt <- sub("[A-Z][a-z]?", "", t)
    cnt <- if (nzchar(cnt)) as.integer(cnt) else 1L
    paste0(el, cnt * n)
  }, character(1)), collapse = "")
}

#' enviPat's `isotopes` table, lazy-loaded once. It is a dataset (not in enviPat's
#' namespace env), so reach it with utils::data into a private env and cache.
#' @noRd
.envipat_isotopes <- local({
  cache <- NULL
  function() {
    if (is.null(cache)) {
      e <- new.env()
      utils::data("isotopes", package = "enviPat", envir = e)
      cache <<- get("isotopes", envir = e)
    }
    cache
  }
})

#' Fine isotopologue pattern of `formula` observed as the ion described by `rule`
#' (a one-row adduct_rules() table: nmol, charge, massdiff). enviPat computes the
#' exact isotopologues; each is then mapped to the ION m/z the same way adduct_mz()
#' maps the monoisotope, so the pattern lines up with the adduct annotation.
#' Returns tibble(mz, abundance) with abundance relative to the base peak (=1).
#' @importFrom tibble tibble
#' @noRd
isotope_pattern <- function(formula, rule, threshold = 0.1) {
  empty <- tibble(mz = numeric(), abundance = numeric())
  z <- abs(rule$charge[1]); if (!is.finite(z) || z < 1) z <- 1
  nmol <- rule$nmol[1]; if (!is.finite(nmol) || nmol < 1) nmol <- 1
  fchem <- scale_formula(formula, as.integer(nmol))
  iso <- .envipat_isotopes()
  pat <- tryCatch(
    enviPat::isopattern(iso, fchem, threshold = threshold, charge = 0,
                        verbose = FALSE),
    error = function(e) NULL)
  if (is.null(pat) || !length(pat) || !is.matrix(pat[[1]])) return(empty)
  m <- pat[[1]]
  # neutral isotopologue mass -> ion m/z: (mass + massdiff) / z  (mass already
  # carries the nmol multiplier via the scaled formula).
  mz <- (m[, "m/z"] + rule$massdiff[1]) / z
  ab <- m[, "abundance"]; ab <- ab / max(ab)
  o <- order(mz)
  tibble(mz = mz[o], abundance = ab[o])
}

#' Simulate the profile envelope of an isotopologue pattern at a resolving power
#' `resolution` (R = m/z / FWHM). Each isotopologue becomes a Gaussian of that
#' width; the sum is sampled on a fine grid and scaled to max 1. At high R the fine
#' structure separates; at low R it merges — exactly what the instrument does.
#' Returns tibble(mz, intensity).
#' @param pattern isotope_pattern() output (mz, abundance).
#' @param resolution resolving power (FWHM basis); higher = sharper peaks.
#' @param oversample grid points per FWHM.
#' @param pad_fwhm how many FWHM of m/z padding on each side.
#' @importFrom tibble tibble
#' @noRd
isotope_profile <- function(pattern, resolution = 70000, oversample = 12,
                            pad_fwhm = 6) {
  empty <- tibble(mz = numeric(), intensity = numeric())
  if (!nrow(pattern) || !isTRUE(is.finite(resolution)) || resolution <= 0)
    return(empty)
  sigma_of <- function(mz) (mz / resolution) / (2 * sqrt(2 * log(2)))  # FWHM->sd
  fwhm <- pattern$mz / resolution
  lo <- min(pattern$mz) - pad_fwhm * max(fwhm)
  hi <- max(pattern$mz) + pad_fwhm * max(fwhm)
  step <- min(fwhm) / oversample
  grid <- seq(lo, hi, by = step)
  y <- numeric(length(grid))
  for (i in seq_len(nrow(pattern))) {
    s <- sigma_of(pattern$mz[i])
    y <- y + pattern$abundance[i] * exp(-0.5 * ((grid - pattern$mz[i]) / s)^2)
  }
  if (max(y) > 0) y <- y / max(y)
  tibble(mz = grid, intensity = y)
}

#' Rough resolving power estimate from an observed PROFILE trace near `mz`: take
#' the tallest peak within `window` Da, measure its full width at half maximum on
#' the raw samples, and return m/z / FWHM. NA when it can't be measured (too few
#' points, already centroided). Lets the UI pre-fill R from the data.
#' @param prof observed profile as tibble(mz, intensity).
#' @noRd
estimate_resolution <- function(prof, mz, window = 0.5) {
  if (!nrow(prof)) return(NA_real_)
  near <- prof[abs(prof$mz - mz) <= window, , drop = FALSE]
  near <- near[order(near$mz), , drop = FALSE]
  if (nrow(near) < 5) return(NA_real_)
  apex <- which.max(near$intensity)
  half <- near$intensity[apex] / 2
  if (!is.finite(half) || half <= 0) return(NA_real_)
  mzv <- near$mz; iv <- near$intensity
  # linear-interpolate the half-max crossing between the bracketing samples on
  # each side (taking the outer sample overestimates FWHM and so underestimates R).
  cross <- function(a, b) mzv[a] + (mzv[b] - mzv[a]) *
    (half - iv[a]) / (iv[b] - iv[a])
  l <- apex; while (l > 1 && iv[l] > half) l <- l - 1
  r <- apex; while (r < nrow(near) && iv[r] > half) r <- r + 1
  if (l == apex || r == apex) return(NA_real_)   # apex at an edge, no crossing
  fwhm <- cross(r, r - 1) - cross(l, l + 1)
  if (!is.finite(fwhm) || fwhm <= 0) return(NA_real_)
  mzv[apex] / fwhm
}
