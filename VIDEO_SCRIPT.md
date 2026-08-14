# xcmsVisGUI — feature showcase video script

A shot-by-shot script for a screen-recorded walkthrough (~8–9 min). The
through-line is **compound identification from raw LC–MS**, and the
spine of it is one loop: *chromatogram → spectrum → are these peaks one
compound? → EICs to check co-elution → back to the spectrum to
annotate.* At each step the voice-over says which question you’re
answering, so the tools land as a workflow rather than a tour. Each shot
has **\[SCREEN\]** (bulleted actions to perform) and **\[VO\]**
(voice-over beats — read as connected narration, not a list). Times are
approximate.

Recording tips: 1440×900 window, browser zoom ~110 % so the sidebar text
is legible, hide the OS cursor trail, and pause ~1 s after each click so
the UI settles on camera.

------------------------------------------------------------------------

## Demo data — what to load for each feature

Reproducible from two public Bioconductor datasets, with two optional
“own-data” files where richer small-molecule chemistry helps. Get the
public paths in R with `system.file(...)`:

| Feature in the video | File(s) | How to get them |
|----|----|----|
| The main ID loop: profile spectrum, peak picking, co-elution EICs, annotation, isotope envelope, precursors | **MS3TMT11.mzML** — profile MS1 + centroid MS2/3, DDA | `list.files(system.file("proteomics", package = "msdata"), "mzML$", full.names = TRUE)` |
| Cross-sample abundance in the EIC, colour **by group** | **faahKO** — 12 centroid CDF (6 KO + 6 WT); target *m/z* **335.1** (a fatty-acid amide up in the knockouts) | `system.file("cdf", "KO", package = "faahKO")` and `.../"WT"` — two folders, 6 files each |
| MS map (2-D / 3-D) | faahKO (fast, centroid) or MS3TMT11 | as above |
| Adduct / fragment / findMAIN annotation on real adduct series | *best on small-molecule data* — a profile urine/Orbitrap run (`.../incognito_urine_A_vs_C_pos`); MS3TMT11 shows the mechanics | own data / msdata |
| Metal-complex ions (**\[M\]+**, Fe) | iron-formate contaminant run (own data); anchors **131.9504** and **132.9582** | own data |
| Same-name disambiguation, the copying **Browse** path | any file copied into two folders | copy one CDF into a second folder |

> For the annotation stretch (sections 4–5) a **polarity-switching
> small-molecule Orbitrap run** is far more compelling than the peptide
> file — real adduct series and a clean isotope cluster. Use your own
> data there if you have it; the script notes the public fallback each
> time.

------------------------------------------------------------------------

## 0. Cold open (0:00–0:20)

**\[SCREEN\]** - Title card, then cut to the app open on **TIC / BPC**
with a file loaded and a chromatogram on screen.

**\[VO\]** - xcmsVisGUI is a local app for reading *raw* LC–MS data by
eye — before any peak picking or alignment. - I use it mostly to figure
out what a compound actually is. - There’s one loop I run over and over:
chromatogram → spectrum → extract the ions → back to the spectrum. Let
me show you that loop.

------------------------------------------------------------------------

## 1. Loading files — three ways, and which one copies (0:20–1:30)

**\[SCREEN\]** Empty app, **Files** panel. Show each control in turn: -
Paste a folder path into the box → **Add**. - Click **Choose folder…**
(native OS folder dialog). - Click **Browse files…**, and separately
**drag a file onto it**.

**\[VO\]** - Three ways to get files in — and the difference matters
once your files are large. - **Paste a path**, or **Choose folder…**,
loads the data **in place — nothing is copied**; a multi-gigabyte file
just stays on disk and the app reads it there. - The path box also takes
a **single file**, and a folder load grabs every MS file in *that*
folder only — it **doesn’t descend into sub-folders**, so load `KO` and
`WT` as two separate folders. - **Browse files…** — or **dragging files
onto it** — is the ordinary OS file dialog, and it **copies** everything
into a temp folder first. - So: handy for a file or two, but for big or
many files, paste the path and skip the copy.

**\[SCREEN\]** - Let the files read in the background — ⏳ badges flip
to ✅. - Point at the **MS**, **Pol**, and **Mode**
(`prof`/`cent`/`mix`) columns. - Double-click a **Group** cell to rename
a group. - Click **All** to include everything.

**\[VO\]** - Reading happens in the background, so the interface never
blocks. - Each row tells me the MS levels, the polarity, and whether the
file is **profile or centroided** — which decides how the views
behave. - I set my sample groups right here in the table, and click a
row to include that file in the plots. - Two files can even share a name
from different folders — they’re kept apart by their parent folder.

------------------------------------------------------------------------

## 2. Chromatogram → click a peak → spectrum (1:30–2:30)

**\[SCREEN\]** - On **TIC / BPC**, toggle **BPC (max)** vs **TIC
(sum)**. - Set **Color by** = *Sample group*. - **Click a peak** on the
trace. - Switch to **Spectrum** — it’s already loaded at that scan.

**\[VO\]** - I start at the chromatogram just to get oriented — where
the run is busy. - Then the core move: I **click a peak**, and the mass
spectrum at that exact scan is waiting on the Spectrum tab. - Everything
here is linked like that — a click always takes me to the data
underneath.

**\[SCREEN\]** - The spectrum shows a **profile** scan as a line (title
reads “… • profile”). - Tick **Show data points (profile)**. - Open
**Peak picking** → **Raw + centroids overlay**; zoom one cluster. - Show
the **S/N**, **Half-window**, and **m/z accuracy** controls. - Switch to
**Centroid profile scans** for a clean stick spectrum.

**\[VO\]** - Profile data is drawn as a **line** — thousands of detector
samples per peak, which I can even show as points. - To work with masses
I **centroid** it — and because that’s *data processing*, it lives right
here, per view, not in a global filter. - I **overlay** the centroids
first to see exactly what picking keeps, then switch to a clean **stick
spectrum**. - Now I’m looking at a handful of mass peaks around my
compound.

**\[SCREEN\]** - Click **Scan list**. - In the modal, filter by MS level
/ precursor-m/z / polarity. - Click a row to jump to that scan; close
the modal.

**\[VO\]** - And if I don’t have a peak to click my way to, every scan’s
metadata is one table away — - filter by MS level, polarity or precursor
mass, and jump straight to it.

------------------------------------------------------------------------

## 3. “Are these peaks the same compound?” → EICs (2:30–3:50)

**\[SCREEN\]** Still on the Spectrum: - Set the click action to **→ EIC
list**. - **Click several peaks** in the cluster — the base peak, a
neighbour a couple of Da away, a suspected adduct further out (click,
click, click). - Switch to the **EIC** tab — the targets are populated
and the overlaid EICs render.

**\[VO\]** - Here’s the question a single spectrum can’t answer: I see
several peaks — but do they belong to **one** compound (a molecular ion
with its adducts, isotopes and fragments), or are they different things
that just happen to co-elute? - A spectrum is one slice in time; to tell
them apart I need their **chromatograms**. - So I click each peak into
the **EIC list** and pull them out.

**\[SCREEN\]** - Set **Scale intensity** = *Normalise each trace*. -
Point at the peaks that rise and fall together, versus one that peaks at
a different time or with a different shape.

**\[VO\]** - Normalising each trace to its own height throws away
abundance and shows me pure **shape**. - Now it’s obvious: these three
**rise and fall together**, same retention time, same profile — that’s
one compound. - But this one peaks slightly earlier, different shape — a
**separate species** that was just sitting under the same scan. - That
co-elution test is the difference between annotating a real adduct
series and chasing a coincidence.

**\[SCREEN\]** *(Optional, faahKO)* - Load faahKO and paste *m/z*
`335.1`. - Set **Color by group** and **Scale** = *Normalise per
target*.

**\[VO\]** - The same view answers a different question too — across
many samples, is my compound more abundant in one group? - Here’s 335 in
the FAAH knockouts versus wild-type, clearly up where the biology says
it should be.

------------------------------------------------------------------------

## 4. Back to the spectrum → annotate the ion set (3:50–5:10)

**\[SCREEN\]** Return to **Spectrum**: - Tick **Annotate adducts /
fragments**. - Note **Ion mode** auto-set from the scan polarity; leave
**Manual anchor** (base peak default). - Point at the labelled adduct /
fragment / isotope peaks and the *“N candidate peaks feed matching”*
readout.

**\[VO\]** - Now that I know which peaks belong together, I annotate
them. - I anchor on the molecular-ion candidate; the app projects the
common adducts and in-source fragments and labels the ones actually
present — only over the co-eluting set I just confirmed. - The ion mode
follows the scan, and matching runs against **real centroids** at a
signal-to-noise I control — with a readout of how many peaks feed it, so
nothing is hidden.

**\[SCREEN\]** - Switch **Mode** → **Auto-suggest (findMAIN)** →
**Suggest molecular ion** → click a ranked row. - Then switch to
**Difference network** → show the peak-pair Δ labels.

**\[VO\]** - If I’m unsure which peak is the molecule, **findMAIN**
ranks the hypotheses for me. - Or I drop the anchor entirely and
annotate the **differences** between peaks — to catch a neutral loss or
an adduct relationship I hadn’t assumed.

------------------------------------------------------------------------

## 5. From a mass to a formula — fine isotopes and contaminants (5:10–6:20)

**\[SCREEN\]** - Switch **Mode** → **Isotope pattern (formula)**. - With
the anchor set, show the candidate-formula table (formula, mass, ppm,
DBE, ✓). - Pick a row → the translucent green **envelope** overlays the
raw cluster. - Adjust **Resolving power**; click **From data** to
estimate it from the peak width.

**\[VO\]** - With the right ion and its neutral mass, I want a
**formula**. - The app decomposes the mass into candidates, then — the
payoff on high-res data — overlays the **fine** isotope pattern for
each: the true ¹³C, ¹⁵N, ³⁴S structure, simulated at my instrument’s
resolving power. - The envelope is **translucent**, so I can see the raw
peaks underneath and judge the fit. - That’s how a mass becomes a
confident formula.

**\[SCREEN\]** - Add **Fe** to the **Elements** selector. - Choose the
**\[M\]+** adduct and turn **off** *Chemically valid only*. - Show an
iron-formate formula at low ppm (anchors 131.9504 / 132.9582).

**\[VO\]** - Half of identification is ruling out **contaminants**. -
These are iron-formate clusters leaching from steel tubing, carrying an
intrinsic charge from the metal’s oxidation state. - Add iron, pick the
metal-ion type, relax the organic-only rule — and the background ion
names itself.

------------------------------------------------------------------------

## 6. MS map — surveying the neighbourhood (6:20–7:00)

**\[SCREEN\]** - Go to **MS map**, press **Plot**. - Drag the
**Contrast** slider on the 2-D m/z × rt map. - Note **Peak picking =
Centroid profile scans** is on by default. - Switch to **3D surface**,
press **Plot**, and rotate it. - Click a pixel → Spectrum loads that
scan.

**\[VO\]** - Sometimes I zoom out from one peak and survey the
neighbourhood — co-eluting isomers, an adduct series marching across
m/z, a contaminant ladder. - The map plots exact centroids over mass and
time; I lower the contrast for the weak stuff, or rotate a 3-D
surface. - And, as everywhere, click a point to read the spectrum
underneath.

------------------------------------------------------------------------

## 7. Precursors — MS2 for structure (7:00–7:25)

**\[SCREEN\]** - With MS3TMT11 (DDA) included, go to **Precursors**. -
Show the rt × precursor-m/z scatter. - Click a point → its MS2 loads on
the Spectrum tab.

**\[VO\]** - For the structural layer of an ID I need
**fragmentation**. - The Precursors map shows exactly what the
instrument fragmented and when — click a precursor and I’m reading its
MS2, ready to annotate it the same way.

------------------------------------------------------------------------

## 8. Filters, settings, export (7:25–8:20)

**\[SCREEN\]** - Open **Filters**: set an rt window and MS level, add a
spectrum-ID rule; watch a plot update. - Open **Settings**: switch the
time unit and palette; show it applied.

**\[VO\]** - Two housekeeping notes. - **Global filters** — retention
time, m/z, intensity, MS level, polarity, even spectrum-ID rules —
narrow *every* view at once. - And **settings** like the time unit,
palette and export defaults persist across restarts.

**\[SCREEN\]** - Press **Save** on a plot → show the export dialog (png
/ svg / pdf / rds).

**\[VO\]** - When I’ve made the case, every plot exports to a
publication image — or the raw ggplot object, to keep tweaking in R.

------------------------------------------------------------------------

## 9. Close (8:20–8:35)

**\[SCREEN\]** - Zoom out to the full app; end card with the repo URL.

**\[VO\]** - That’s the loop — chromatogram, spectrum, extract the ions
to prove they belong together, then annotate to a formula and a
structure. - Raw LC–MS, one click at a time. - It’s on GitHub, and the
article guides cover every panel.

------------------------------------------------------------------------

### Feature checklist (make sure the recording hits all of these)

Loading: paste-path / Choose folder (no copy) vs Browse / drag-and-drop
(copies to temp); non-recursive folder load

Async reading, Mode column (prof/cent/mix), group editing, same-name
disambiguation

TIC vs BPC, colour by sample/group, click-to-spectrum

Profile spectrum as a line; show data points

Peak picking modes: raw / overlay / centroid / force; S/N, half-window,
m/z accuracy

Scan-list browser (typed filters, click a row)

**Co-elution loop**: click peaks → EIC list; normalise-each-trace to
compare shapes; same-vs-different call

EIC cross-sample: paste m/z, colour by group, normalise-per-target;
facet

Annotation: manual anchor, findMAIN auto, difference network; Match
S/N + candidate readout; ion mode from scan

Isotope pattern: candidate formulas, translucent envelope, resolving
power, From data

Metal complexes: Elements + \[M\]+ + valid-only off (131.9504 /
132.9582)

MS map: 2D contrast, 3D surface/points, click-to-spectrum

Precursors: DDA map, click-to-MS2

Filters (incl. spectrum-ID rules), Settings (persisted), Export
(png/svg/pdf/rds)
