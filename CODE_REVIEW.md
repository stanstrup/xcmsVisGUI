# Code review — xcmsVisGUI

Full read of `app.R`, `global.R`, and all `R/*.R`, plus a runtime check
of the one filter path in doubt. Date: 2026-06-05.

Overall: in good shape. The architecture matches `CLAUDE.md`, the
SerialParam perf fix is correctly centralized, cache keys are sensible,
and the seconds-internally / display-unit-at-edges discipline is
consistent. No crashes or security concerns (local single-user, no
injection vectors).

Verified by running on real data (msdata):
[`Spectra::filterMzRange()`](https://rdrr.io/pkg/ProtGenerics/man/protgenerics.html)
**does** dispatch on `MsExperiment` and constrains correctly
(110.001–119.999 for a 110–120 window), so the unwrapped m/z filter in
`apply_filters()` is fine — not a bug.

Findings by priority, with `file:line` and concrete fixes.

## Medium — functional

**1. Scan-list filters can materialize phantom blank rows** —
`R/mod_plot_spectrum.R:187-199` `filtered_scans()` builds `keep` with
raw comparisons (`keep & tab$polarity == pcode`,
`keep & tab$precursorMZ >= sl$pmz_min`, …). When a scan has `NA` in that
field (MS1 rows have no precursor m/z; some vendors leave polarity
unset), the comparison yields `NA`, and `tab[keep, ]` turns each `NA`
into an all-`NA` row in the DT. Enabling the precursor-m/z or polarity
filter can therefore sprinkle empty rows into the scan list. *Fix:*
coerce NA→FALSE per clause, e.g.
`keep <- keep & !is.na(tab$polarity) & tab$polarity == pcode`, or wrap
each numeric clause in `(…) %in% TRUE`.

**2. “Reset filters” leaves MS level untouched** —
`R/mod_filter.R:84-89` The reset handler clears rt/mz/intensity,
`spectrum_id`, and polarity, but not the `ms_level` select — so after a
reset the MS-level constraint silently persists. *Fix:* add
`updateSelectInput(session, "ms_level", selected = if ("1" %in% ranges()$ms_levels) "1" else "all")`.

## Medium — performance

**3. Single-file views re-open the file on every interaction** —
`R/fct_extract.R:70-105,152-158` `extract_spectrum` / `extract_peaks` /
`extract_precursors` each call `Spectra::Spectra(path, MsBackendMzR())`
fresh. The Spectrum tab re-initializes the backend (a header read) on
*every* rt/scan tweak; the MS map / Precursors re-read all included
files on each render. Header *tables* are cached in `.scan_cache`
(`file_scan_table`), but the `Spectra` object the peak path uses is not.
*Fix:* add a small per-path `Spectra`-object cache (mirroring
`.scan_cache`) and slice from it. Biggest felt win is the Spectrum tab
becoming interactive.

**4. EIC cache key omits the time unit** — `R/mod_plot_eic.R:141`
`eic_df` is `bindCache(data_key(), enabled_targets())`. Per-target
`rt_min`/`rt_max` cells are entered in the display unit and converted to
seconds at extraction. Flipping Settings min↔︎sec doesn’t change the
numeric cell values, so the cache doesn’t bust, but they now mean a
different unit → wrong rt window. *Fix:* add `rv$settings$time_unit` to
the cache key.

## Low — cleanup (startup time + clarity)

**5. Stale [`library()`](https://rdrr.io/r/base/library.html) loads** —
`global.R:21-22,29-36` `shinyFiles` and `shinyWidgets` have zero call
sites (shinyFiles was removed; nothing uses widgets). `stringr`, `fs`,
`tidyr`, `purrr` also show no usage. `shinyjs` is only `useShinyjs()`
with no actual `shinyjs::*` calls. Dropping these (and from
`renv-setup.R:14`) trims boot time and the lockfile.

**6. Dead state/helpers** — `R/utils_reactive.R` `make_backend()` (107)
is unused; `rv$settings$backend` is never read or written (the backend
selector was removed); `rv$active_file` (41), `rv$filter$charge` (50),
and `eic_targets$color` (33) are vestigial; `included_file_ids()` (100)
is unused (app.R inlines it). Trimming these removes “is this wired up?”
confusion.

**7. Stale module comment** — `R/mod_ingest.R:1-7` Header still says
files are “picked server-side with shinyFiles.” It’s now typed path +
[`utils::choose.dir()`](https://rdrr.io/r/utils/choose.dir.html) +
native `fileInput`. Update to match.

## Polish

**8. `Inf` leaking into filter hints** — `R/fct_extract.R:23-24` For
all-`NA` retention times (CDF edge), `min/max(..., na.rm=TRUE)` returns
`Inf/-Inf` (warning suppressed), which then shows up in the filter range
hint. Coalesce non-finite to `NA`.

## Suggested order

5/6/7 are pure deletions (near-zero risk); 1 and 2 are small real bugs;
3 is the perf win you’ll actually feel. Do them as separate commits on
`main`, parse-checked and smoke-tested on real data.
