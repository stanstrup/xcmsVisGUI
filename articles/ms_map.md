# MS map

The MS map plots a 2-D *m/z* × retention-time view of the included
files. It draws **exact centroids** (no binning) with an mzMine-style
**contrast** control — lower the contrast to reveal weaker peaks.

This view is **gated**: press **Plot** to render, so it never
auto-extracts every file as you change unrelated settings.

![2-D MS map](figures/msmap.png)

2-D MS map

**Profile-mode files are peak-picked first** (the **Peak picking**
control in this tab’s panel, default *Centroid profile scans*). This is
the view that needs it: mapping a profile file raw means tens of
millions of points — one test file goes from 29 million points (690 MB)
to 2 million (48 MB) once picked. (The
[Spectrum](https://stanstrup.github.io/xcmsVisGUI/articles/spectrum.md)
view defaults to raw — it can afford to.) Set it to *Raw* to map every
sample, but expect it to be slow. The setting, and its S/N / half-window
/ *m/z*-refinement sub-options, take effect on the next **Plot**. See
[Getting
started](https://stanstrup.github.io/xcmsVisGUI/articles/getting_started.html#profile-mode-data).

## 3D views

Switch the view to **3D surface** or **3D points** for a binned surface
/ scatter you can rotate. The bin sizes (and, for points, an intensity
cutoff) are set in the sidebar.

![3-D surface](figures/msmap3d.png)

3-D surface

## Moving between tabs

**Click a pixel** on the 2-D map to send that retention time to the
[Spectrum](https://stanstrup.github.io/xcmsVisGUI/articles/spectrum.md)
tab (for the first included file); switch to the Spectrum tab to read
the full scan there. It’s a fast way to go from “there’s a spot here” to
the actual mass spectrum.

## Export

**Save** writes a static image of the 2-D map.
