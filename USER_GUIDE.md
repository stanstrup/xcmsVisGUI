# xcmsVisGUI — User Guide

An interactive desktop app for **exploring raw LC-MS data** — total/base-peak
chromatograms, extracted-ion chromatograms (EICs), spectra, 2D/3D MS maps and DDA
precursor maps — built on `mzR` + `Spectra`/`xcms`, with dynamic `plotly` plots.

It is a lightweight, raw-data-focused alternative to clicking around in mzMine: load
files, filter, and look at the data from many angles.

## Running it

```r
Rscript run.R        # or, in an R session:  shiny::runApp()
```

On first launch the app restores its pinned package library with `renv` (one-time).

## Loading files (left sidebar → "Files")

- **Paste a folder or file path** into the box and press **Add**. A folder loads
  *every* MS file inside it (mzML / mzXML / CDF); a file loads just that file. This is
  the fast, no-copy route — best for many or large files.
- **Browse…** opens the standard OS file dialog. ⚠️ This *copies* the chosen files to a
  temporary folder (a browser limitation), so prefer the path box for big data.
- Files are read **asynchronously** — the list fills in as each file's header is read,
  with a ✅/⏳/❌ status badge.
- **Tick a file** to include it in plots; untick to exclude (files stay loaded). Use
  **All / None / Invert**. Edit the **Group** cell to set sample groups (used for
  colouring). **Clear** (trash icon) removes everything.

## Filtering (left sidebar → "Filters")

All filters are **typed numeric inputs** (blank = no limit) applied to every view:

- **Retention time** (in the display unit) and **m/z** (4 decimals).
- **Intensity** min/max.
- **MS level** (`all` or a specific level).
- **Polarity** (any / pos / neg) — for polarity-switching runs.
- **Spectrum ID contains** — substring match on the raw spectrum id, e.g.
  `function=1 process=0 scan=7` (handy for Waters function/scanEvent subsetting).

Press **Reset filters** to clear.

## The plot tabs

**TIC / BPC** — total- or base-peak chromatogram overlay of the included files.
Colour by sample group or sample; toggle data points. **Click a trace** to open that
scan in the Spectrum tab. Hover shows scan number, rt and intensity.

**EIC** — multiple extracted-ion chromatograms. Fill the **target table**
(label / m/z / ± tol / unit / rt window / enable) or **paste a list of m/z values**
to add them. *Tolerance is a ± half-window:* a window is `m/z ± m/z·ppm/1e6` (or ± Da),
so "10 ppm" spans 20 ppm total — widen it if EICs look too narrow. Colour by target,
file or group; facet by file; toggle points. Click a trace → Spectrum.

**Spectrum** — driven by the included files (no separate picker):
- *Single* shows the file you clicked (or the first included) at a retention time or
  **scan (acquisition) number**; an out-of-range scan snaps to the last.
- *Facet* / *Stacked* compare the spectrum at the rt across **all** included files.
- The **precursor m/z** is marked (dashed line + title) when the scan has one.
- **Scan list** opens a searchable table of every scan's metadata (rt, MS level,
  polarity, precursor m/z, TIC, base-peak m/z, spectrum id) with typed min/max filters;
  click a row to jump to that scan. Filters persist between openings.
- **Click a peak** to add its m/z to the EIC target list.

**MS map** — 2D or 3D view of the included file(s); press **Plot** to render (so it
never auto-extracts everything). 2D draws **exact centroids** as rt-width line segments
(no binning); the **Contrast** slider sets the intensity percentile mapped to full
colour — lower it to reveal weaker peaks. 3D offers a **surface** (default) or points.
Hover shows exact m/z, rt and scan; click a point → Spectrum.

**Precursors** — DDA precursor map (m/z vs rt) for the included MS2 files. Colour by
file / group / none; hover shows the scan number; **click a point** to view its
spectrum.

## Settings

- **Retention-time unit** — minutes (default) or seconds, applied everywhere.
- **Qualitative palette** (groups/EICs) and **sequential palette** (maps/3D), including
  ColorBrewer and viridis options; **Invert colour scale** (on by default → light→dark).
- **Parallel readers** (mirai daemons) for file reading.
- **Export** defaults (format / size / DPI) used by each plot's **Save** button.

## Exporting

Each ggplot-based plot has a **Save** button → choose PNG / SVG / PDF, size and DPI.
Exports are crisp vectors (SVG/PDF) or high-DPI raster, independent of the on-screen
plotly. (3D views are interactive only.)

## Tips

- **Zoom is preserved** across cosmetic changes (contrast, colours, points) — double-
  click a plot to reset.
- For a folder of 100+ files, loading is header-only and fast; the heavy reads happen
  per plot and are cached.
