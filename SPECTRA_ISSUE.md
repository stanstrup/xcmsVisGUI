# Draft GitHub issue for rformassspectrometry/Spectra

> Paste into https://github.com/rformassspectrometry/Spectra/issues

---

**Title:** `MsBackendMzR` reading is 100×+ slower with the default `SnowParam` backend (esp. Windows)

**Body:**

Reading files with `MsBackendMzR` (and therefore `Spectra()`, `readMsExperiment()`,
`chromatogram()`, …) can be **catastrophically slow** because `backendInitialize()` reads
the per-file headers with `bplapply(files, ..., BPPARAM = bpparam())`, and the registered
default `bpparam()` is a **non-running `SnowParam`** cluster. Each call therefore spawns
*and tears down* a socket cluster (every worker re-loading the Bioc stack) just to read a
header. On Windows — where the BiocParallel default is `SnowParam` — this dominates
everything; the actual read is trivial.

In an interactive app reading one file at a time, this turns a ~0.6 s read into ~80–150 s.

### Reproducible example

This forces `SnowParam` so it reproduces on any OS (it is the *default* on Windows):

```r
library(Spectra)
library(BiocParallel)

f <- system.file("sciex/20171016_POOL_POS_1_105-134.mzML", package = "msdata")

## Simulates the Windows default backend
register(SnowParam(workers = 4))
system.time(Spectra(f, source = MsBackendMzR()))
#>    elapsed ~ 15.5 s   (cluster spawn — and this small file has only a few hundred spectra)

register(SerialParam())
system.time(Spectra(f, source = MsBackendMzR()))
#>    elapsed ~ 0.11 s
```

(Measured on Windows 11, R 4.5.2, Spectra 1.18.2 — a **~140× difference on a tiny bundled
file**, confirming the cost is the per-call cluster spawn, independent of file size.)

On a real 30 MB centroided mzML (1814 spectra) on Windows 11 / R 4.5.2 / Spectra 1.18.2 /
BiocParallel 1.42.2, with the **default** `bpparam()` = `SnowParam(workers = 6)`:

| Operation | default `SnowParam` | `register(SerialParam())` |
|---|---:|---:|
| `Spectra(MsBackendMzR())` | **146 s** | **0.75 s** |
| `readMsExperiment()` | 80 s | 0.31 s |
| `chromatogram()` (1 EIC) | 93 s | 1.06 s |

For reference, raw `mzR::openMSfile()` + `header()` + `peaks()` on the same file is ~0.6 s,
so the time is entirely BiocParallel cluster overhead, not I/O.

`Rprof` confirms ~99 % of the time is in `bplapply` → `bpstart`/`bploop` (SnowParam worker
startup), 0 % in the header read.

### Why this hurts users

- It is **silent**: nothing signals that the slowness is parallel-backend setup, not the
  read. New/Windows/interactive users just experience an unusably slow `Spectra`/`xcms`.
- The default backend **re-spawns** a cluster on every `bplapply` call (the default
  `SnowParam` is not started), so the cost is paid per `Spectra()`/`chromatogram()` call.
- For a **single or few files** — the common interactive case — a freshly-spawned cluster
  can never pay off; serial is strictly faster.

### Suggestion

For per-file header reads in `MsBackendMzR::backendInitialize()`, default to
`SerialParam()` (or use serial when `length(files)` is below a small threshold), rather
than inheriting a heavyweight `bpparam()`. At minimum, document prominently that
interactive/Windows users should `register(SerialParam())`. Optionally, reuse a single
started cluster across calls instead of spawning one per `bplapply`.

Happy to test a patch.
