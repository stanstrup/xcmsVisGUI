# xcmsVisGUI: interactive raw LC-MS viewer (Shiny)

A local desktop Shiny app for visualising raw LC-MS data (TIC/BPC, EICs,
spectra, 2D/3D MS maps, DDA precursors). Launch with
[`run_app()`](https://stanstrup.github.io/xcmsVisGUI/reference/run_app.md).

## Details

Import policy: every used function is declared with a per-function
`@importFrom` so the code calls bare names. Two deliberate exceptions:

- `shiny` and `bslib` are imported whole (`@import`) — they are the UI
  framework used in essentially every function and have no conflicts
  with our other imports; enumerating them per function adds noise, not
  safety.

- the RforMassSpectrometry S4 stack
  (Spectra/xcms/MsExperiment/BiocParallel/ mzR) is called with `::`.
  Those packages export many overlapping generics (`rtime`, `intensity`,
  `mz`, `filterMsLevel`, `spectra`, ...) and some collide with base
  (`close`, `filter`); `::` keeps the intended method source explicit
  and dispatch unambiguous — the "unresolvable conflict" case. `%>%`
  (magrittr) and `%||%` (rlang) are imported here once as operators.

## See also

Useful links:

- <https://stanstrup.github.io/xcmsVisGUI>

- <https://github.com/stanstrup/xcmsVisGUI>

- Report bugs at <https://github.com/stanstrup/xcmsVisGUI/issues>

## Author

**Maintainer**: Jan Stanstrup <stanstrup@gmail.com>

Authors:

- Jan Stanstrup <stanstrup@gmail.com>
