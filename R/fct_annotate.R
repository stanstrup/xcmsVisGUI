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

#' Project the ADDUCT ions for a neutral mass M from commonMZ::MZ_CAMERA. The
#' CAMERA table also carries in-source fragments (`[M+H-H2O]+`, `[M+H-CO2]+`, …);
#' those are excluded here (classified by mass via is_fragment_rule) — in-source
#' losses are the difference-network's job, not the anchor/auto overlay. Isotopes
#' are not projected either; they are DETECTED after matching (add_detected_isotopes).
#' Returns tibble(label, type = "adduct", mz, charge).
#' @param M neutral monoisotopic mass.
#' @param mode "pos" / "neg".
#' @param max_charge keep only ions with |charge| <= this.
#' @importFrom tibble tibble
#' @noRd
project_ions <- function(M, mode = c("pos", "neg"), max_charge = Inf) {
  mode <- match.arg(mode)
  rules <- adduct_rules(mode)
  rules <- rules[abs(rules$charge) <= max_charge &
                   !is_fragment_rule(rules$massdiff, rules$charge), , drop = FALSE]
  out <- tibble(label = rules$name, type = "adduct",
                mz = adduct_mz(M, rules), charge = rules$charge)
  out[is.finite(out$mz), , drop = FALSE]
}

#' Classify a CAMERA rule as an in-source FRAGMENT by MASS, not by name: a
#' fragment removes neutral mass from M (massdiff < 0). The only adducts with a
#' negative offset are pure (de)protonations (`[M-H]-`, `[M-2H]2-`), whose massdiff
#' is exactly -|charge|*proton — exclude those. Everything that adds mass (any
#' protonation, Na/K/NH4/Cl/formate adduct, multimer) is an adduct.
#' @noRd
is_fragment_rule <- function(massdiff, charge, proton = 1.007276) {
  (massdiff < 0) & (abs(massdiff + abs(charge) * proton) > 0.01)
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
#' derive the neutral mass, project the adduct/fragment ions, match them, then
#' DETECT and label the isotopes of each matched ion from the spectrum (up to
#' `isotopes` members). Returns list(M = neutral mass, adduct, table).
#' @noRd
annotate_anchor <- function(spec_df, anchor_mz, adduct = NULL, mode = c("pos", "neg"),
                            tol = 10, unit = "ppm", isotopes = 1L, max_charge = Inf) {
  mode <- match.arg(mode)
  rules <- adduct_rules(mode)
  if (is.null(adduct)) adduct <- quasi_adducts(mode)[1]
  rule <- rules[rules$name == adduct, , drop = FALSE]
  if (!nrow(rule)) stop("Unknown adduct: ", adduct)
  M <- neutral_mass(anchor_mz, rule)
  expected <- project_ions(M, mode, max_charge = max_charge)
  # Match adducts against the DEISOTOPED, centroided spectrum so an isotope peak
  # can never be labelled as an adduct (isotope wins); its satellites are then
  # labelled separately from the full spectrum.
  cp <- centroid_peaks(spec_df, rel_floor = 0)
  zmax <- if (is.finite(max_charge)) max(1L, as.integer(max_charge)) else 2L
  pool <- deisotope(cp, tol, unit, max_charge = zmax)
  tab <- match_spectrum(pool, expected, tol, unit)
  if (isotopes >= 1) tab <- add_detected_isotopes(tab, cp, isotopes, tol, unit)
  list(M = M, adduct = adduct, table = tab)
}

#' Auto-suggest the molecular ion (mode 2) with InterpretMSSpectrum::findMAIN.
#' Centroids the spectrum, runs findMAIN constrained to commonMZ's quasi-molecular
#' adducts, and returns the ranked hypotheses as a tibble (best first). Robust to
#' failure/empty input — returns a 0-row tibble. The app uses the top row's
#' (adductmz, adducthyp) as the anchor for annotate_anchor().
#'
#' findMAIN's scoring degrades when fed thousands of noise peaks (random
#' coincidences "explain" spurious masses), so we always reduce to the `max_peaks`
#' most intense centroids first — independent of the intensity floor, which the
#' user may have set to 0 for the other modes.
#' @importFrom tibble as_tibble tibble
#' @noRd
rank_anchors <- function(spec_df, mode = c("pos", "neg"), ppm = 5,
                         top_n = 5L, rel_floor = 0.01, max_peaks = 200L) {
  mode <- match.arg(mode)
  empty <- tibble(adductmz = numeric(), adducthyp = character(),
                  neutral_mass = numeric(), adducts_explained = integer(),
                  total_score = numeric())
  cp <- centroid_peaks(spec_df, rel_floor = rel_floor)
  if (nrow(cp) < 1) return(empty)
  if (nrow(cp) > max_peaks)
    cp <- cp[order(-cp$intensity), , drop = FALSE][seq_len(max_peaks), , drop = FALSE]
  spec <- cbind(mz = cp$mz, int = cp$intensity)
  ionmode <- if (mode == "pos") "positive" else "negative"
  # findMAIN is chatty (per-hypothesis scoring warnings) — quiet it for the app.
  # Hypotheses are real adducts only — NOT in-source fragments like [M+H-H2O]+.
  # Allowing a fragment as the main-ion hypothesis let findMAIN call the base peak
  # a water loss (neutral mass off by +H2O) and produced confusing annotations.
  r <- adduct_rules(mode)
  hyp <- r$name[r$quasi == 1 & !is_fragment_rule(r$massdiff, r$charge)]
  res <- tryCatch(
    suppressWarnings(suppressMessages(
      InterpretMSSpectrum::findMAIN(spec, ionmode = ionmode,
                                    adducthyp = hyp, ppm = ppm))),
    error = function(e) NULL)
  if (is.null(res)) return(empty)
  s <- tryCatch(as.data.frame(summary(res)), error = function(e) NULL)
  if (is.null(s) || !nrow(s)) return(empty)
  tibble::as_tibble(utils::head(s, top_n))
}

#' Difference network (mode 3): annotate peak PAIRS whose m/z difference matches a
#' commonMZ adducts_fragments entry. No anchor needed. Returns tibble(mz_lo, mz_hi,
#' delta, origin, int_lo, int_hi), one row per matched edge among the `top_n` most
#' intense peaks. With `ignore_isotopes` the peak list is DEISOTOPED first (M+1/M+2
#' satellites removed, so an M+1 at 453 can't pair with 470) AND any remaining
#' isotope-spaced pair (delta ~= k * 13C, k = 1..3) is skipped — that covers the
#' case where the satellite is the taller, or a noise peak one spacing away.
#' @importFrom tibble tibble
#' @noRd
difference_network <- function(spec_df, tol = 10, unit = "ppm", top_n = 30L,
                               rel_floor = 0.01, ignore_isotopes = TRUE) {
  empty <- tibble(mz_lo = numeric(), mz_hi = numeric(), delta = numeric(),
                  origin = character(), int_lo = numeric(), int_hi = numeric())
  cp <- centroid_peaks(spec_df, rel_floor = rel_floor)
  if (isTRUE(ignore_isotopes)) cp <- deisotope(cp, tol, unit)
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
    if (ignore_isotopes) {
      # Skip any near-isotope-spaced delta (k = 1..3). Real isotope centroids in
      # MS2 can be tens of ppm off the theoretical spacing, so this uses a GENEROUS
      # window (the adduct ppm window plus an absolute isotope slack) — wider than
      # the adduct match window — so imprecise/noise isotope pairs don't slip
      # through and get mislabelled (e.g. a 2.03 spacing tagged as "+/- 2H").
      ik <- round(delta / ISOTOPE_SPACING)
      if (ik >= 1 && ik <= 3 && abs(delta - ik * ISOTOPE_SPACING) <= win + ISO_SLACK) next
    }
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

#' Flag isotope SATELLITES in a centroid list — the single isotope definition
#' shared by deisotoping and annotation. A peak is a satellite when another peak
#' sits ~k * (13C spacing / z) BELOW it (k = 1..max_k, z = 1..max_charge) within
#' the combined peak-accuracy window AND is at least as intense (the monoisotope is
#' the tallest for small molecules). Checking the lower steps cascades to strip a
#' whole envelope to its monoisotope. Position+intensity based and governed by the
#' user's tolerance — deliberately NOT MetaboCoreUtils::isotopologues, whose
#' theoretical-spacing grouping is too strict for real MS2 (isotope centroids tens
#' of ppm off ideal). Returns a logical vector over `cp` rows.
#' @noRd
isotope_satellites <- function(cp, tol = 10, unit = "ppm", max_charge = 2L,
                               max_k = 2L) {
  n <- nrow(cp)
  if (n < 2) return(rep(FALSE, n))
  o <- order(cp$mz); mz <- cp$mz[o]; it <- cp$intensity[o]
  sat <- logical(n)
  span <- max_k * ISOTOPE_SPACING + 0.05         # widest look-behind window
  for (a in seq_len(n)) {
    lo <- findInterval(mz[a] - span, mz) + 1L     # candidate parents are just below
    if (lo > a - 1L) next
    for (b in lo:(a - 1L)) {
      if (it[b] < it[a]) next                     # parent must be >= intensity
      d <- mz[a] - mz[b]
      win <- tol_to_da(mz[a], tol, unit) + tol_to_da(mz[b], tol, unit)
      for (z in seq_len(max_charge)) for (k in seq_len(max_k))
        if (abs(d - k * ISOTOPE_SPACING / z) <= win) { sat[o[a]] <- TRUE; break }
      if (sat[o[a]]) break
    }
  }
  sat
}

#' Reduce a centroid list to monoisotopic peaks by dropping isotope satellites.
#' @noRd
deisotope <- function(cp, tol = 10, unit = "ppm", max_charge = 2L) {
  if (nrow(cp) < 2) return(cp)
  cp[!isotope_satellites(cp, tol, unit, max_charge), , drop = FALSE]
}

#' Label the isotopes of each matched adduct/fragment by DETECTION anchored to the
#' expected position: for k = 1..n look for a real peak at mono + k*(13C/charge)
#' within tolerance, with a plausible intensity (an isotope shouldn't dwarf its
#' monoisotope). Only peaks actually present are labelled. Position-anchored rather
#' than via isotopologues() grouping because real MS2 isotope centroids are often
#' tens of ppm off the theoretical spacing, which defeats strict grouping at the
#' user's tolerance and yields spurious groups in dense spectra; the user's
#' tolerance governs how far off the spacing may be.
#' @importFrom tibble tibble
#' @noRd
add_detected_isotopes <- function(tab, cp, n = 2L, tol = 10, unit = "ppm") {
  hits <- tab[tab$matched & tab$type == "adduct", , drop = FALSE]
  if (!nrow(hits) || !nrow(cp)) return(tab)
  extra <- list()
  for (i in seq_len(nrow(hits))) {
    z <- abs(hits$charge[i]); if (!is.finite(z) || z < 1) z <- 1
    mono_mz <- hits$mz_obs[i]; mono_int <- hits$intensity[i]
    for (k in seq_len(n)) {
      em <- mono_mz + k * ISOTOPE_SPACING / z
      win <- tol_to_da(em, tol, unit)
      cand <- which(abs(cp$mz - em) <= win)
      if (!length(cand)) next                       # isotope must be present
      j <- cand[which.min(abs(cp$mz[cand] - em))]
      if (cp$intensity[j] > 1.5 * mono_int) next     # not a plausible satellite
      extra[[length(extra) + 1L]] <- tibble(
        label = sprintf("[+%d]", k), type = "isotope",
        mz = em, charge = hits$charge[i], mz_obs = cp$mz[j],
        intensity = cp$intensity[j], ppm_err = (cp$mz[j] - em) / em * 1e6,
        matched = TRUE)
    }
  }
  if (!length(extra)) return(tab)
  rbind(tab, do.call(rbind, extra)[, names(tab), drop = FALSE])
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
