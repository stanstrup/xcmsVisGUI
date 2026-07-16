# xcmsVisGUI — feature showcase video script

A shot-by-shot script for a screen-recorded walkthrough (~7–9 min) that touches
every feature. Each shot has **[SCREEN]** (what to do / show) and **[VO]**
(voice-over). Times are approximate. Use a profile-mode file so the profile / peak
-picking / isotope features have something to show — the public demo data
(`msdata::MS3TMT11.mzML`) is profile MS1 + centroided MS2/3; a polarity-switching
Orbitrap run is ideal if you have one.

Recording tips: 1440×900 window, hide the OS cursor trail, pause ~1 s after each
click so the UI settles on camera, and zoom the browser to ~110 % so the sidebar
text is legible.

---

## 0. Cold open (0:00–0:20)

**[SCREEN]** Title card → cut to the app already open on the **TIC / BPC** tab with
a few files loaded and a rich TIC overlay on screen.

**[VO]** "xcmsVisGUI is a local Shiny app for looking at *raw* LC–MS data — before
any peak picking or alignment. Load your files, and every view is one click from the
next. Let's walk through it."

---

## 1. Loading files (0:20–1:10)

**[SCREEN]** Empty app. In the **Files** panel, paste a folder path → **Add**. Show
the rows appearing with the ⏳ badge flipping to ✅. Point at the columns: **MS**,
**Pol**, and the **Mode** column (`prof` / `cent` / `mix`).

**[VO]** "Point it at a folder — multi-gigabyte files stay where they are, nothing
is copied. Files read in the background, so the interface never blocks. Each row
tells you the MS levels, the polarity, and — importantly — whether the file is
**profile** or **centroided**. That drives what happens later."

**[SCREEN]** Load a *second* folder that contains a file with the **same name**. Show
both rows present. Include all with **All**.

**[VO]** "Two files can even share a name from different folders — they're both kept,
and the plots tell them apart by their parent folder."

---

## 2. TIC / BPC and the click-through model (1:10–2:00)

**[SCREEN]** TIC overlay renders. Toggle **BPC (max)** vs **TIC (sum)**. Change
**Color by** from *Sample* to *Sample group*. Hover a trace to show the tooltip.

**[VO]** "The first tab overlays the total-ion or base-peak chromatogram of every
included file. Colour by sample or by group; the legend disambiguates same-named
files."

**[SCREEN]** **Click a peak** on the TIC. Switch to the **Spectrum** tab — it's
already loaded at that retention time.

**[VO]** "Now the key idea: everything is linked. Click a peak, and the spectrum at
that exact scan is waiting on the Spectrum tab."

---

## 3. The Spectrum tab — profile mode (2:00–3:10)

**[SCREEN]** Spectrum tab showing a **profile** scan drawn as a continuous **line**;
the title reads "… • profile". Tick **Show data points (profile)** to reveal the raw
detector samples on the line.

**[VO]** "Profile data is drawn as a line — because that's what it is: thousands of
detector samples per peak. You can even show the individual points."

**[SCREEN]** Open the **Peak picking** dropdown → choose **Raw + centroids overlay**.
Zoom into one peak cluster to show the raw line with the picked centroid sticks over
it. Show the **S/N**, **Half-window** and **m/z accuracy** controls that appear.

**[VO]** "Peak picking is data processing, so it lives here, per view — not in the
filters. Overlay the centroids to see exactly what picking keeps, and tune the
signal-to-noise, the window, and sub-sample m/z accuracy."

**[SCREEN]** Switch the dropdown to **Centroid profile scans** — the view becomes a
clean stick spectrum.

**[VO]** "Or just centroid it for a conventional stick spectrum."

---

## 4. Scan-list browser (3:10–3:35)

**[SCREEN]** Click **Scan list**. In the modal, type into the filters (e.g. MS = 1,
a precursor-m/z range). Click a row → the modal closes and that scan loads.

**[VO]** "Every scan's metadata is one table away — filter by MS level, polarity,
precursor mass, spectrum ID — and click any row to jump to it."

---

## 5. Annotation — adducts, isotopes, fragments (3:35–4:45)

**[SCREEN]** Tick **Annotate adducts / fragments**. Note the **Ion mode**
auto-selected from the scan's polarity. Leave **Manual anchor**; the base peak is the
default anchor. Show the labelled adduct / fragment / isotope peaks on the plot and
the **"N candidate peaks feed matching"** readout.

**[VO]** "Turn on annotation and the ion mode follows the scan you're on. It matches
against real centroids at a signal-to-noise you control — the readout tells you how
many peaks feed the match, so nothing is a black box."

**[SCREEN]** Switch **Mode** to **Auto-suggest (findMAIN)** → press **Suggest
molecular ion** → click a row in the ranked table. Then switch to **Difference
network** and show the peak-pair Δ labels.

**[VO]** "Let findMAIN rank molecular-ion hypotheses, or drop the anchor entirely and
annotate peak *pairs* whose mass difference matches a known loss."

---

## 6. Fine isotope patterns + metal complexes (4:45–6:00)

**[SCREEN]** Switch **Mode** to **Isotope pattern (formula)**. With an anchor set,
show the candidate-formula table (formula, mass, ppm, DBE, ✓). Pick a row → the
translucent green **theoretical envelope** overlays the raw spectrum. Adjust
**Resolving power** and show the fine structure separating/merging; click **From
data** to estimate R from the peak width.

**[VO]** "For real identification-adjacent work: propose molecular formulas from the
mass, then overlay the *fine* isotope pattern — the true ¹³C, ¹⁵N, ³⁴S structure —
simulated at your instrument's resolving power. The envelope is translucent, so you
can judge how it fits the data."

**[SCREEN]** Add **Fe** to the **Elements** selector, choose the **[M]+** adduct, and
turn **off** *Chemically valid only*. Show a metal-complex formula (e.g. an
iron-formate background ion) appearing at low ppm.

**[VO]** "It even handles metal-complex background ions — the iron-formate clusters
that leach from stainless steel. Add the metal, pick the intrinsic-charge ion type,
and there it is."

---

## 7. EIC — targets and scaling (6:00–7:00)

**[SCREEN]** On the Spectrum, set click action to **→ EIC list** and click a couple
of peaks. Switch to the **EIC** tab — the targets are populated. Show the target
table (m/z, tol, unit, rt window, enable checkbox). Paste a couple more m/z values.

**[VO]** "Click peaks into the EIC list — or paste masses — and extract them across
every file at once."

**[SCREEN]** Cycle the **Scale intensity** control: *Raw* → *Normalise each trace* →
*Normalise per target* → *Log10*. Tick **Facet by file**.

**[VO]** "Scale however the question needs: raw, each trace to its own max to compare
shapes, per target to compare relative abundance across files, or log to pull weak
traces up. Facet by file when the overlay gets busy."

---

## 8. MS map — 2D and 3D (7:00–7:45)

**[SCREEN]** Go to **MS map**, press **Plot**. Show the 2-D m/z × rt map; drag the
**Contrast** slider. Point out **Peak picking = Centroid profile scans** (why it's on
by default). Switch to **3D surface**, press **Plot**, rotate it.

**[VO]** "The MS map draws exact centroids across m/z and time — profile files are
picked first, because mapping tens of millions of raw points isn't practical. Lower
the contrast to bring up weak peaks, or flip to a rotatable 3-D surface."

**[SCREEN]** Click a pixel on the 2-D map → Spectrum tab loads that scan.

**[VO]** "And, again — click anywhere to read the spectrum underneath."

---

## 9. Precursors (7:45–8:05)

**[SCREEN]** With a DDA file included, go to **Precursors**. Show the rt × precursor
-m/z scatter. Click a point → the MS2 spectrum loads on the Spectrum tab.

**[VO]** "For DDA runs, the Precursors map shows what was fragmented and when — click
a point to read the MS2."

---

## 10. Filters, settings, export (8:05–8:50)

**[SCREEN]** Open **Filters**: set an rt window and an MS-level, add a spectrum-ID
rule. Show a plot updating. Then **Settings**: change the retention-time unit to
seconds and the palette; show it applied.

**[VO]** "Global filters — retention time, m/z, intensity, MS level, polarity, even
spectrum-ID rules — apply to every view. Settings like the time unit, palettes and
export defaults persist across restarts."

**[SCREEN]** Press **Save** on a plot; show the export dialog (png / svg / pdf / rds).

**[VO]** "Every plot exports to a crisp publication image — or the raw ggplot object,
to keep tweaking in R."

---

## 11. Close (8:50–9:00)

**[SCREEN]** Zoom back out to the full app; end card with the repo URL.

**[VO]** "xcmsVisGUI — raw LC–MS, one click at a time. It's on GitHub; the article
guides walk through every panel."

---

### Feature checklist (make sure the recording hits all of these)

- [ ] Async loading, Mode column (prof/cent/mix), same-name disambiguation
- [ ] TIC vs BPC, colour by sample/group, click-to-spectrum
- [ ] Profile spectrum as a line; show data points
- [ ] Peak picking modes: raw / overlay / centroid / force; S/N, half-window, m/z accuracy
- [ ] Scan-list browser (typed filters, click a row)
- [ ] Annotation: manual anchor, findMAIN auto, difference network
- [ ] Match S/N + candidate-peak readout; ion mode from scan
- [ ] Isotope pattern: candidate formulas, translucent envelope, resolving power, From data
- [ ] Metal complexes: Elements + [M]+ + valid-only off
- [ ] EIC: click-to-target + paste; scale (raw/trace/target/log); facet
- [ ] MS map: 2D contrast, 3D surface/points, click-to-spectrum
- [ ] Precursors: DDA map, click-to-MS2
- [ ] Filters (incl. spectrum-ID rules), Settings (persisted), Export (png/svg/pdf/rds)
