# Spectrum annotation: adducts, isotopes and in-source fragments on a single
# raw spectrum. Two assets are combined:
#   * commonMZ  — the adduct/fragment DICTIONARY (MZ_CAMERA rule table +
#                 adducts_fragments mass-difference table). Single source of
#                 truth for every projected m/z, so the manual and auto modes
#                 annotate with identical definitions.
#   * InterpretMSSpectrum::findMAIN — the AUTO ranker (mode 2): given one
#                 spectrum it scores candidate (neutral mass, main adduct)
#                 hypotheses; we only use it to *suggest* the molecular ion,
#                 then re-project the winning mass through our own project_ions().
#
# Everything here is pure (no Shiny) so it is unit-testable. The app calls it
# from mod_plot_spectrum. CAMERA/cliqueMS etc. don't apply — they need a
# multi-sample feature matrix; this app is raw-only, one spectrum at a time.

# --- tolerance + peak picking ------------------------------------------------

#' Half-window in Da for a tolerance given in ppm or Da (vectorised over `mz`).
#' Mirrors the EIC target formula (`mod_plot_eic`): window = m/z +/- this. `unit`
#' is a single value (not vectorised) — branch on it so a scalar unit does not
#' collapse a vector `mz` the way `ifelse()` would.
#' @noRd
tol_to_da <- function(mz, tol, unit = "ppm") {
  if (identical(unit, "ppm")) mz * tol / 1e6 else rep(tol, length(mz))
}

#' Reduce a (possibly profile-mode) spectrum to centroids: cluster points whose
#' neighbours are within `mz_gap` and keep each cluster's apex (most intense
#' point), above a relative-intensity floor. Profile shoulders collapse to one
#' peak; already-centroided, well-separated peaks each pass through. Used before
#' findMAIN and the difference network so noise/profile shape don't spawn spurious
#' annotations. Returns mz/intensity sorted by m/z.
#' @importFrom tibble tibble
#' @noRd
centroid_peaks <- function(df, rel_floor = 0, mz_gap = 0.01) {
  if (nrow(df) == 0) return(tibble(mz = numeric(), intensity = numeric()))
  o <- order(df$mz)
  mz <- df$mz[o]; it <- df$intensity[o]
  grp <- cumsum(c(TRUE, diff(mz) > mz_gap))   # new cluster when the gap is large
  ord <- order(grp, -it)                      # within each cluster, apex first
  sel <- sort(ord[!duplicated(grp[ord])])     # one apex per cluster
  floor_abs <- rel_floor * max(it, na.rm = TRUE)
  cp <- tibble(mz = mz[sel], intensity = it[sel])
  cp[cp$intensity > floor_abs, , drop = FALSE]
}

# --- adduct dictionary (commonMZ) --------------------------------------------

.adduct_cache <- new.env(parent = emptyenv())

#' CAMERA-style adduct rule table for a polarity, via commonMZ (cached; static).
#' Columns: name, nmol, charge, massdiff, quasi. `massdiff` is the mass offset to
#' the uncharged species (already includes the proton/electron mass), so
#'   m/z = (nmol * M + massdiff) / abs(charge).
#' @param mode "pos" or "neg".
#' @importFrom tibble as_tibble
#' @noRd
adduct_rules <- function(mode = c("pos", "neg")) {
  mode <- match.arg(mode)
  hit <- get0(mode, envir = .adduct_cache, inherits = FALSE)
  if (!is.null(hit)) return(hit)
  r <- commonMZ::MZ_CAMERA(mode, warn_clash = FALSE)
  r <- tibble::as_tibble(r[, c("name", "nmol", "charge", "massdiff", "quasi")])
  assign(mode, r, envir = .adduct_cache)
  r
}

#' The principal (quasi-molecular) adduct names for a polarity — the sensible
#' anchor choices and the findMAIN hypotheses (e.g. `[M+H]+`, `[M+Na]+`, `[M+H-H2O]+`).
#' @noRd
quasi_adducts <- function(mode = c("pos", "neg")) {
  r <- adduct_rules(match.arg(mode))
  r$name[r$quasi == 1]
}

#' Neutral mass M implied by an observed ion m/z under one adduct rule:
#'   M = (m/z * abs(charge) - massdiff) / nmol.   `rule` is a one-row rule table.
#' @noRd
neutral_mass <- function(mz, rule) {
  (mz * abs(rule$charge[1]) - rule$massdiff[1]) / rule$nmol[1]
}

#' Expected m/z for each rule given a neutral mass M (vectorised over `rules`).
#' @noRd
adduct_mz <- function(M, rules) {
  (rules$nmol * M + rules$massdiff) / abs(rules$charge)
}

# --- ion projection ----------------------------------------------------------

#' Project every ion we expect to see for a neutral mass M: all adducts, the
#' M+1..M+k isotopes of the quasi-molecular adducts, and in-source neutral losses
#' from the principal ion (commonMZ::adducts_fragments mass differences subtracted
#' from the principal-ion m/z). Returns tibble(label, type, mz, charge) where
#' `type` is "adduct" | "isotope" | "fragment". Pure dictionary maths — matching
#' against an actual spectrum is match_spectrum().
#' @param M neutral monoisotopic mass.
#' @param mode "pos" / "neg".
#' @param principal adduct name whose ion the neutral losses hang off
#'   (default: the first quasi adduct, i.e. `[M+H]+` / `[M-H]-`).
#' @param isotopes number of isotope peaks (M+1..) to project per quasi adduct.
#' @param losses include in-source neutral-loss fragments.
#' @param max_loss largest neutral loss (Da) to consider.
#' @importFrom tibble tibble
#' @noRd
project_ions <- function(M, mode = c("pos", "neg"), principal = NULL,
                         isotopes = 1L, losses = TRUE, max_loss = 250) {
  mode <- match.arg(mode)
  rules <- adduct_rules(mode)
  out <- tibble(label = rules$name, type = "adduct",
                mz = adduct_mz(M, rules), charge = rules$charge)

  if (isotopes >= 1) {
    q <- rules[rules$quasi == 1, , drop = FALSE]
    qmz <- adduct_mz(M, q)
    iso <- lapply(seq_len(isotopes), function(k) {
      tibble(label = sprintf("%s [+%d]", q$name, k), type = "isotope",
             mz = qmz + k * ISOTOPE_SPACING / abs(q$charge), charge = q$charge)
    })
    out <- rbind_tibbles(out, iso)
  }

  if (isTRUE(losses)) {
    pr <- if (is.null(principal)) quasi_adducts(mode)[1] else principal
    prule <- rules[rules$name == pr, , drop = FALSE]
    if (nrow(prule)) {
      base_mz <- adduct_mz(M, prule)[1]
      af <- commonMZ::adducts_fragments
      d <- af[is.finite(af$mz_diff) & af$mz_diff > 0 & af$mz_diff <= max_loss, ]
      frag_mz <- base_mz - d$mz_diff
      ok <- frag_mz > 0
      out <- rbind_tibbles(out, list(tibble(
        label = sprintf("%s -%.3f (%s)", pr, d$mz_diff[ok], short_origin(d$origin[ok])),
        type = "fragment", mz = frag_mz[ok], charge = prule$charge[1])))
    }
  }
  out[is.finite(out$mz), , drop = FALSE]
}

#' Match projected ions against the observed spectrum: for each expected m/z take
#' the most intense observed peak inside the +/- tol window. Returns `expected`
#' augmented with mz_obs, intensity, ppm_err and a `matched` flag (unmatched rows
#' are kept so the caller can draw "expected but absent" ghost ticks).
#' @param spec_df observed peaks (mz, intensity).
#' @param expected output of project_ions().
#' @noRd
match_spectrum <- function(spec_df, expected, tol = 10, unit = "ppm") {
  n <- nrow(expected)
  mz_obs <- rep(NA_real_, n); int_obs <- rep(NA_real_, n)
  if (nrow(spec_df) > 0) {
    win <- tol_to_da(expected$mz, tol, unit)
    for (i in seq_len(n)) {
      hit <- which(abs(spec_df$mz - expected$mz[i]) <= win[i])
      if (length(hit)) {
        j <- hit[which.max(spec_df$intensity[hit])]
        mz_obs[i] <- spec_df$mz[j]; int_obs[i] <- spec_df$intensity[j]
      }
    }
  }
  expected$mz_obs    <- mz_obs
  expected$intensity <- int_obs
  expected$ppm_err   <- (mz_obs - expected$mz) / expected$mz * 1e6
  expected$matched   <- is.finite(mz_obs)
  expected
}

#' Manual-anchor annotation (mode 1): treat `anchor_mz` as a known adduct ion,
#' derive the neutral mass, project all ions and match them to the spectrum.
#' Returns list(M = neutral mass, adduct, table = match_spectrum(...)).
#' @noRd
annotate_anchor <- function(spec_df, anchor_mz, adduct = NULL, mode = c("pos", "neg"),
                            tol = 10, unit = "ppm", isotopes = 1L, losses = TRUE) {
  mode <- match.arg(mode)
  rules <- adduct_rules(mode)
  if (is.null(adduct)) adduct <- quasi_adducts(mode)[1]
  rule <- rules[rules$name == adduct, , drop = FALSE]
  if (!nrow(rule)) stop("Unknown adduct: ", adduct)
  M <- neutral_mass(anchor_mz, rule)
  expected <- project_ions(M, mode, principal = adduct, isotopes = isotopes,
                           losses = losses)
  list(M = M, adduct = adduct,
       table = match_spectrum(spec_df, expected, tol, unit))
}

#' Auto-suggest the molecular ion (mode 2) with InterpretMSSpectrum::findMAIN.
#' Centroids the spectrum, runs findMAIN constrained to commonMZ's quasi-molecular
#' adducts, and returns the ranked hypotheses as a tibble (best first). Robust to
#' failure/empty input — returns a 0-row tibble. The app uses the top row's
#' (adductmz, adducthyp) as the anchor for annotate_anchor().
#' @importFrom tibble as_tibble tibble
#' @noRd
rank_anchors <- function(spec_df, mode = c("pos", "neg"), ppm = 5,
                         top_n = 5L, rel_floor = 0.01) {
  mode <- match.arg(mode)
  empty <- tibble(adductmz = numeric(), adducthyp = character(),
                  neutral_mass = numeric(), adducts_explained = integer(),
                  total_score = numeric())
  cp <- centroid_peaks(spec_df, rel_floor = rel_floor)
  if (nrow(cp) < 1) return(empty)
  spec <- cbind(mz = cp$mz, int = cp$intensity)
  ionmode <- if (mode == "pos") "positive" else "negative"
  # findMAIN is chatty (per-hypothesis scoring warnings) — quiet it for the app.
  res <- tryCatch(
    suppressWarnings(suppressMessages(
      InterpretMSSpectrum::findMAIN(spec, ionmode = ionmode,
                                    adducthyp = quasi_adducts(mode), ppm = ppm))),
    error = function(e) NULL)
  if (is.null(res)) return(empty)
  s <- tryCatch(as.data.frame(summary(res)), error = function(e) NULL)
  if (is.null(s) || !nrow(s)) return(empty)
  tibble::as_tibble(utils::head(s, top_n))
}

#' Difference network (mode 3): annotate peak PAIRS whose m/z difference matches a
#' commonMZ adducts_fragments entry. No anchor needed; the noisy mode (off by
#' default in the UI). Returns tibble(mz_lo, mz_hi, delta, origin, int_lo, int_hi),
#' one row per matched edge among the `top_n` most intense peaks.
#' @importFrom tibble tibble
#' @noRd
difference_network <- function(spec_df, tol = 10, unit = "ppm", top_n = 30L,
                               rel_floor = 0.01) {
  empty <- tibble(mz_lo = numeric(), mz_hi = numeric(), delta = numeric(),
                  origin = character(), int_lo = numeric(), int_hi = numeric())
  cp <- centroid_peaks(spec_df, rel_floor = rel_floor)
  if (nrow(cp) < 2) return(empty)
  cp <- cp[order(-cp$intensity), , drop = FALSE]
  cp <- utils::head(cp, top_n)
  af <- commonMZ::adducts_fragments
  af <- af[is.finite(af$mz_diff) & af$mz_diff > 0, , drop = FALSE]
  rows <- list(); k <- 0L
  for (i in seq_len(nrow(cp) - 1L)) for (j in (i + 1L):nrow(cp)) {
    lo <- min(cp$mz[i], cp$mz[j]); hi <- max(cp$mz[i], cp$mz[j])
    delta <- hi - lo
    # The window is the instrument accuracy at BOTH peaks (errors add), NOT ppm of
    # the tiny difference: a 10 ppm peak pair at m/z 425 leaves ~0.008 Da slack on
    # an 18 Da loss, but ppm-of-18 would be 0.0002 Da and miss the whole ladder.
    win <- tol_to_da(lo, tol, unit) + tol_to_da(hi, tol, unit)
    m <- which(abs(af$mz_diff - delta) <= win)
    if (length(m)) {
      k <- k + 1L
      rows[[k]] <- tibble(
        mz_lo = lo, mz_hi = hi, delta = delta,
        origin = clean_text(paste(af$origin[m], collapse = " | ")),
        int_lo = cp$intensity[cp$mz == lo][1], int_hi = cp$intensity[cp$mz == hi][1])
    }
  }
  if (!k) return(empty)
  do.call(rbind, rows)
}

# --- small internals ---------------------------------------------------------

#' rbind a base tibble with a list of tibbles, all-same-columns. Local rather than
#' dplyr::bind_rows to keep this file dependency-light and explicit.
#' @noRd
rbind_tibbles <- function(x, pieces) {
  do.call(rbind, c(list(x), pieces[vapply(pieces, nrow, integer(1)) > 0]))
}

#' Re-encode commonMZ origin text to UTF-8. The adducts_fragments table carries
#' Latin-1 bytes (e.g. the "±" in "± H2O"); left as-is they break grepl/printing
#' downstream. The only non-ASCII content is Latin-1, so this conversion is exact.
#' @noRd
clean_text <- function(x) iconv(x, from = "latin1", to = "UTF-8")

#' First clause of a commonMZ origin string (before the first comma) — the
#' fragment description, dropping the long explanatory tail, for compact labels.
#' @noRd
short_origin <- function(x) {
  x <- clean_text(x)
  trimws(vapply(strsplit(x, ",", fixed = TRUE), `[`, character(1), 1))
}
