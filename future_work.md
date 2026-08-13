## TODO

7) Something seems wrong with EIC normlization when you have more than one file
   — **could not reproduce (2026-08-13).** Checked on 3 faahKO files x 2 targets:
   extraction/attribution is right (each file+target matches a single-file
   extraction exactly), "÷ own max" puts every one of the 6 traces at exactly
   1.0, and "÷ target max" puts the strongest file of each target at 1.0 with
   the rest below. Needs a concrete example of what looked wrong.

## Done (2026-08-13)

1) Move filenames below on the TIC/EIC plots — `theme(legend.position="bottom")`.
2) Re-adding a dir named the new files NA — `add_paths()`'s `names` default
   (`basename(paths)`) was forced only AFTER `paths` had been narrowed to the new
   subset, so the keep mask indexed off the end. Reading itself was never broken
   (it goes by path); only the displayed name was NA. Now `select_new_paths()`.
3) Adding files cleared the filter — the Filters panel is a `renderUI` keyed on
   the included files, and the rebuild reset every control. Values are now
   re-seeded from the current inputs.
4) Deselecting files redrew per click — `included` is `debounce`d.
5) EIC target checkbox also selected the row — DT delegates row selection on
   **mousedown**, so the checkbox stops propagation on mousedown *and* click.
6) Saving a plot now uses the current zoom — `zoom_keeper()$ranges` ->
   `coord_cartesian()` on the exported ggplot (preview and file).
8) The `Ignoring unknown aesthetics: text` warning — `with_plotly_aes()` mutes it
   for `text`/`key` only; a misspelled aesthetic still warns.

## Decided / parked

* **xcmsVIS — declined for now (2026-06-06).** Evaluated using xcmsVis's `gplot*`
  output and amending it post-hoc with `+ aes()/geom_/scale_`. Doesn't fit the
  raw-only scope: its methods want xcms/MSnbase result objects (not our cached
  tibbles); post-hoc `+` is additive and can't add the `key` click-nav aesthetic,
  the seconds→display-unit transform, or ColorBrewer to layers it already built;
  it doesn't ggplotly cleanly (patchwork/geom_polygon); most `gplot*` are
  peak/feature plots (deferred). Also currently segfaults on first symbol access
  in this R install. Full rationale in `ARCHITECTURE_REVIEW.md` Decision log.


## For later
* **more use of xcmsVIS** — revisit when peak picking lands (see ARCHITECTURE_REVIEW.md
  "Deferred: preprocessing"): we'd then
  have XcmsExperiment objects and `gplotChromPeaks`/`gplotFeatureGroups` could back
  dedicated peak views (adding our own `key` layer on fresh plots is workable).
* xcms objects
* integrate with decomposemass --> decomposemass needs API to pass parameters
* 
