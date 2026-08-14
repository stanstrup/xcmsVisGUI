# NA

## TODO

(empty)

## Done (2026-08-13)

7.  EIC normalization looked wrong with more than one file — the
    normalisation maths was fine (verified on 3 faahKO files x 2 targets
    against single-file extractions); the **zoom keeper** was at fault.
    Repro: raw + facet by file + zoom into a peak, then switch on
    normalisation. The stored y range is in data units, so re-applying
    it after the units changed pinned a panel at 0–250k while the
    normalised trace sat under 1.0 — the peak vanished. Only one panel,
    because only the first `yaxis` is tracked (facets also have
    `yaxis2..N`). `zoom_keeper()$reset("y")` is now called from the EIC
    scale/facet controls and the spectrum layout control; the x (rt)
    zoom is kept.

8.  Move filenames below on the TIC/EIC plots —
    `theme(legend.position="bottom")`.

9.  Re-adding a dir named the new files NA — `add_paths()`’s `names`
    default (`basename(paths)`) was forced only AFTER `paths` had been
    narrowed to the new subset, so the keep mask indexed off the end.
    Reading itself was never broken (it goes by path); only the
    displayed name was NA. Now `select_new_paths()`.

10. Adding files cleared the filter — the Filters panel is a `renderUI`
    keyed on the included files, and the rebuild reset every control.
    Values are now re-seeded from the current inputs.

11. Deselecting files redrew per click — `included` is `debounce`d.

12. EIC target checkbox also selected the row — DT delegates row
    selection on **mousedown**, so the checkbox stops propagation on
    mousedown *and* click.

13. Saving a plot now uses the current zoom — `zoom_keeper()$ranges` -\>
    `coord_cartesian()` on the exported ggplot (preview and file).

14. The `Ignoring unknown aesthetics: text` warning —
    `with_plotly_aes()` mutes it for `text`/`key` only; a misspelled
    aesthetic still warns.

## Decided / parked

- **xcmsVIS — declined for now (2026-06-06).** Evaluated using xcmsVis’s
  `gplot*` output and amending it post-hoc with `+ aes()/geom_/scale_`.
  Doesn’t fit the raw-only scope: its methods want xcms/MSnbase result
  objects (not our cached tibbles); post-hoc `+` is additive and can’t
  add the `key` click-nav aesthetic, the seconds→display-unit transform,
  or ColorBrewer to layers it already built; it doesn’t ggplotly cleanly
  (patchwork/geom_polygon); most `gplot*` are peak/feature plots
  (deferred). Also currently segfaults on first symbol access in this R
  install. Full rationale in `ARCHITECTURE_REVIEW.md` Decision log.

## For later

- **more use of xcmsVIS** — revisit when peak picking lands (see
  ARCHITECTURE_REVIEW.md “Deferred: preprocessing”): we’d then have
  XcmsExperiment objects and `gplotChromPeaks`/`gplotFeatureGroups`
  could back dedicated peak views (adding our own `key` layer on fresh
  plots is workable).
- xcms objects
- integrate with decomposemass –\> decomposemass needs API to pass
  parameters
- 
