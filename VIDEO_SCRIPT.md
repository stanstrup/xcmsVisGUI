# xcmsVisGUI — feature showcase video script

A shot-by-shot script for a screen-recorded walkthrough (~8–9 min). The through-line
is **compound identification from raw LC–MS**: at each step the voice-over says *what
question you're answering*, so the tools land as a workflow rather than a tour. Each
shot has **[SCREEN]** (what to do) and **[VO]** (voice-over). Times are approximate.

Recording tips: 1440×900 window, browser zoom ~110 % so the sidebar text is legible,
hide the OS cursor trail, and pause ~1 s after each click so the UI settles on camera.

---

## Demo data — what to load for each feature

Everything below is reproducible from two public Bioconductor datasets, with two
optional "own-data" files where richer small-molecule chemistry helps. Get the public
paths in R with `system.file(...)`:

| Feature in the video | File(s) | How to get them |
|---|---|---|
| Async loading, **Mode** column, groups | **faahKO** — 12 centroid CDF (6 KO + 6 WT) | `system.file("cdf", "KO", package = "faahKO")` and `.../"WT"` — two folders, 6 files each |
| TIC/BPC overlay, **colour by group** | faahKO (KO vs WT) | same |
| **EIC** overlay across samples, scaling, facet | faahKO; target *m/z* **335.1** (a fatty-acid amide up in the knockouts), plus 300.2 / 195.0877 | same |
| **Profile** spectrum, peak picking, precursors, isotope envelope | **MS3TMT11.mzML** — profile MS1 + centroid MS2/3, DDA | `list.files(system.file("proteomics", package = "msdata"), "mzML$", full.names = TRUE)` |
| **MS map** (2-D/3-D) | faahKO (fast, centroid) or MS3TMT11 | as above |
| Adduct / fragment / findMAIN annotation | *best on small-molecule data* — e.g. a profile urine run (`.../incognito_urine_A_vs_C_pos`); MS3TMT11 works to show the mechanics | own data / msdata |
| Metal-complex ions (**[M]+**, Fe) | iron-formate contaminant run (own data); anchors **131.9504** and **132.9582** | own data |
| Same-name disambiguation | any file copied into two folders | copy one CDF into a second folder |

> For the annotation/identification stretch (sections 5–6), a **polarity-switching
> small-molecule Orbitrap run** is far more compelling than the peptide file — real
> adduct series and a clean isotope cluster. Use your own data there if you have it;
> the script notes the public fallback each time.

---

## 0. Cold open (0:00–0:20)

**[SCREEN]** Title card → cut to the app open on **TIC / BPC** with the faahKO files
loaded and a two-group overlay on screen.

**[VO]** "This is xcmsVisGUI — a local app for reading *raw* LC–MS data by eye, before
any peak picking or alignment. I use it for one thing above all: figuring out what a
compound actually is. Let me walk that workflow, start to finish."

---

## 1. Load and get oriented (0:20–1:20)

**[SCREEN]** In **Files**, paste the faahKO **KO** folder path → **Add**; then the
**WT** folder → **Add**. Twelve rows appear with the ⏳ badge flipping to ✅.
Double-click the **Group** cells and rename the six `ko*` rows to `KO`, the six `wt*`
rows to `WT`. Click **All**. Point at the **MS**, **Pol**, and **Mode** (`cent`) columns.

**[VO]** "First, load your run. Point it at a folder — the files stay where they are,
nothing is copied, and they read in the background so the interface never blocks. I set
the sample groups right here in the table — knockout versus wild-type — because most of
identification is really *comparison*: is this compound different where I expect? Each
row also tells me the MS levels, the polarity, and whether the data is profile or
centroided, which decides how the later views behave."

**[SCREEN]** TIC overlay renders. Toggle **BPC (max)** vs **TIC (sum)**; set **Color by**
= *Sample group*.

**[VO]** "The chromatogram overlay is just orientation — where the run is busy, whether
my groups even look different at the whole-run level. Now I zoom in on the compound I
actually care about."

---

## 2. EIC — the targeted starting point (1:20–2:40)

**[SCREEN]** Go to **EIC**. In the target table, paste `335.1`, `300.2`, `195.0877`
(one per line) → **Parse/Add**. Show the columns: *m/z*, tol, unit, rt window, enable.
The overlaid EICs render across all twelve files.

**[VO]** "This is where compound ID usually *starts*: you have a mass — from a database,
a suspect list, or a feature that popped out of processing — and the first question is
simply, *is there a real peak, and where?* I extract the target across every file at
once. There's my 335 — one clean chromatographic peak, at the same retention time in
every sample. That's a real compound, not noise."

**[SCREEN]** Cycle **Scale intensity**: *Raw* → *Normalise each trace* → *Normalise per
target* → *Log10*.

**[VO]** "Then, *how much, and where?* Raw intensity compares absolute abundance.
Normalise each trace to its own maximum when I only care about peak *shape* and
co-elution. Normalise per target to compare the same compound across samples — and here
it is, clearly higher in the knockouts, which is exactly the biology. Log pulls faint
traces up so I don't miss a low-abundance isomer."

**[SCREEN]** Tick **Facet by file**; then untick. Click a peak apex on the 335 trace.

**[VO]** "Facet when the overlay gets crowded. And once I've found my peak, I need its
mass spectrum to identify it — so I click the apex, and jump to the spectrum."

---

## 3. The spectrum at the peak — getting clean data (2:40–3:40)

> Switch to **MS3TMT11** here (or your profile run) so profile mode and peak picking
> have something to show. Load it, include it, set the scan as noted.

**[SCREEN]** Spectrum tab, a **profile** scan drawn as a continuous **line**; the title
reads "… • profile". Tick **Show data points (profile)** to reveal the raw samples.

**[VO]** "The spectrum lands on the scan I clicked. If the file is profile data, it's
drawn as a line — because that's what it is: thousands of detector samples across each
peak. That fidelity matters when I'm judging whether an isotope is real."

**[SCREEN]** Open **Peak picking** → **Raw + centroids overlay**; zoom one cluster to
show centroid sticks on the raw line. Show **S/N**, **Half-window**, **m/z accuracy**.
Then switch to **Centroid profile scans**.

**[VO]** "To actually work with masses I centroid the profile — but that's *data
processing*, so it lives here, per view, not buried in a global filter. I overlay the
centroids first to see exactly what picking keeps and tune the signal-to-noise, then
switch to a clean stick spectrum. Now every peak is a mass I can reason about."

---

## 4. Scan-list browser (3:40–4:00)

**[SCREEN]** Click **Scan list**. In the modal, filter by MS level / precursor-m/z /
polarity; click a row → it loads that scan.

**[VO]** "If I don't have a peak to click, every scan's metadata is one table away —
filter by MS level, polarity, or precursor mass and jump straight to the scan I want."

---

## 5. Annotation — which ion is the molecule? (4:00–5:15)

> Best on small-molecule data (your urine/Orbitrap run). MS3TMT11 shows the mechanics.

**[SCREEN]** Tick **Annotate adducts / fragments**. Note **Ion mode** auto-set from the
scan polarity. Leave **Manual anchor** — the base peak is the default anchor. Labelled
adduct / fragment / isotope peaks appear; show the *"N candidate peaks feed matching"*
readout.

**[VO]** "Here's the crux of identification: of all these peaks, which is the *molecular
ion*, and what's the neutral mass behind it? I anchor on a peak and the app projects the
common adducts and in-source fragments, labelling the ones that are actually present.
The ion mode follows the scan, and it matches against real centroids at a
signal-to-noise I set — the readout tells me how many peaks feed the match, so nothing
is a black box."

**[SCREEN]** Switch **Mode** → **Auto-suggest (findMAIN)** → **Suggest molecular ion** →
click a ranked row. Then **Difference network** to show peak-pair Δ labels.

**[VO]** "If I'm not sure of the anchor, findMAIN ranks the molecular-ion hypotheses for
me. Or I drop the anchor entirely and annotate peak *pairs* — the differences between
peaks — to spot a neutral loss or an adduct relationship I hadn't assumed."

---

## 6. Fine isotope patterns and contaminants (5:15–6:30)

**[SCREEN]** **Mode** → **Isotope pattern (formula)**. With the anchor set, show the
candidate-formula table (formula, mass, ppm, DBE, ✓). Pick a row → the translucent green
**theoretical envelope** overlays the raw cluster. Adjust **Resolving power** (fine
structure separating/merging); click **From data** to estimate R from the peak width.

**[VO]** "Once I have a neutral mass, I want a *formula*. The app decomposes the mass
into candidate formulas, then — and this is the payoff on high-res data — overlays the
*fine* isotope pattern for each one: the true carbon-13, nitrogen-15, sulfur-34
structure, simulated at my instrument's resolving power. The envelope is translucent, so
I can see the raw peaks underneath and judge how well the formula actually fits. That's
how I go from a mass to a confident formula."

**[SCREEN]** Add **Fe** to **Elements**, choose the **[M]+** adduct, turn **off**
*Chemically valid only*. Show an iron-formate background formula at low ppm (anchors
131.9504 / 132.9582 on the contaminant run).

**[VO]** "And identification isn't always your analyte — half the battle is ruling out
contaminants. These are iron-formate clusters that leach from stainless-steel tubing,
carrying an intrinsic charge from the metal's oxidation state. Add iron, pick the
metal-ion type, relax the organic-only rule, and the background ion identifies itself."

---

## 7. MS map — surveying the neighbourhood (6:30–7:15)

**[SCREEN]** **MS map**, press **Plot**. Show the 2-D m/z × rt map; drag **Contrast**.
Note **Peak picking = Centroid profile scans** on by default. Switch to **3D surface**,
**Plot**, rotate. Click a pixel → Spectrum loads that scan.

**[VO]** "Sometimes I need to step back from one peak and survey the neighbourhood —
co-eluting isomers, an adduct series marching across m/z, a contaminant ladder. The map
plots exact centroids over mass and time; I lower the contrast to bring up the weak
stuff, or rotate a 3-D surface. And, as everywhere, I can click any point to read the
spectrum underneath."

---

## 8. Precursors — MS2 for structure (7:15–7:40)

**[SCREEN]** With MS3TMT11 (DDA) included, go to **Precursors**. Show the rt × precursor
-m/z scatter; click a point → the MS2 spectrum loads on Spectrum.

**[VO]** "For the final, structural layer of an ID, I need fragmentation. The Precursors
map shows exactly what the instrument chose to fragment and when — click a precursor and
I'm reading its MS2, ready to annotate it the same way."

---

## 9. Filters, settings, export (7:40–8:30)

**[SCREEN]** Open **Filters**: set an rt window and MS level, add a spectrum-ID rule; a
plot updates. **Settings**: switch the time unit and palette; show it applied.

**[VO]** "Two housekeeping notes. Global filters — retention time, m/z, intensity, MS
level, polarity, even spectrum-ID rules — narrow *every* view at once, so I can focus
the whole app on one region. And settings like the time unit, colour palette and export
defaults persist across restarts."

**[SCREEN]** Press **Save** on a plot; show the export dialog (png / svg / pdf / rds).

**[VO]** "When I've made the case, every plot exports to a publication image — or the raw
ggplot object, to keep tweaking in R."

---

## 10. Close (8:30–8:45)

**[SCREEN]** Zoom out to the full app; end card with the repo URL.

**[VO]** "That's the whole loop — from a mass, to a peak, to a spectrum, to a formula and
a structure. Raw LC–MS, one click at a time. It's on GitHub, and the article guides
cover every panel."

---

### Feature checklist (make sure the recording hits all of these)

- [ ] Async loading, Mode column (prof/cent/mix), group editing, same-name disambiguation
- [ ] TIC vs BPC, colour by sample/group
- [ ] **EIC first**: click-to-target + paste; scale (raw/trace/target/log); facet
- [ ] Click-through EIC/TIC/map → spectrum at that scan
- [ ] Profile spectrum as a line; show data points
- [ ] Peak picking modes: raw / overlay / centroid / force; S/N, half-window, m/z accuracy
- [ ] Scan-list browser (typed filters, click a row)
- [ ] Annotation: manual anchor, findMAIN auto, difference network; Match S/N + candidate readout; ion mode from scan
- [ ] Isotope pattern: candidate formulas, translucent envelope, resolving power, From data
- [ ] Metal complexes: Elements + [M]+ + valid-only off (131.9504 / 132.9582)
- [ ] MS map: 2D contrast, 3D surface/points, click-to-spectrum
- [ ] Precursors: DDA map, click-to-MS2
- [ ] Filters (incl. spectrum-ID rules), Settings (persisted), Export (png/svg/pdf/rds)
