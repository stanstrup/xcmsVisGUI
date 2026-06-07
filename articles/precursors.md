# Precursors

For **data-dependent acquisition (DDA)**, the Precursors tab maps each
fragmented precursor ion as a point at its retention time × precursor
*m/z*, across the included MS2 files. It is the quickest way to see
*what* was selected for fragmentation and *when*.

![DDA precursor-ion map](figures/precursors.png)

DDA precursor-ion map

- **Color by** — *File*, *Sample group*, or none.
- Only files that contain MS2 spectra contribute; if none do, the view
  says so.

## Moving between tabs

**Click a precursor point** to send its file, retention time and
precursor *m/z* to the
[Spectrum](https://stanstrup.github.io/xcmsVisGUI/articles/spectrum.md)
tab; switch there to view the corresponding MS2 spectrum — and from that
spectrum you can click fragment peaks straight into the
[EIC](https://stanstrup.github.io/xcmsVisGUI/articles/eic.md) list.

## Export

**Save** writes a static image of the precursor map.
