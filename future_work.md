## TODO

* CommonMZ/CAMERA/??? integration
* xcms objects


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

