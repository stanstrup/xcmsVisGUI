# Spectra / xcms read performance — benchmark & root cause

While building **xcmsVisGUI** (an interactive raw LC-MS viewer) we hit
catastrophic slowness reading real mzML files through `Spectra` /
`xcms`. This note records the benchmark and the root cause, for
discussion with the RforMassSpectrometry / XCMS authors.

**TL;DR:** `Spectra(MsBackendMzR())` and
[`xcms::chromatogram()`](https://rdrr.io/pkg/ProtGenerics/man/protgenerics.html)
take **80–150 s per operation** on a 30 MB centroided mzML file — but
the cost is **not** mzR or I/O. It is **BiocParallel**:
`MsBackendMzR::backendInitialize()` reads per-file headers via
`bplapply(files, ..., BPPARAM = bpparam())`, and the registered default
`bpparam()` on Windows is **`SnowParam(workers = 6)`**. Each call spawns
and tears down a 6-process socket cluster (every worker re-loading the
Bioc stack). Forcing **`SerialParam()`** drops the same operations to
**0.2–1.6 s** — a **~150–730× difference**.

## Environment

|                     |                                               |
|---------------------|-----------------------------------------------|
| OS                  | Windows 11 Enterprise (26200), local SSD      |
| R                   | 4.5.2                                         |
| Bioconductor        | 3.21                                          |
| Spectra             | 1.18.2                                        |
| xcms                | 4.6.4                                         |
| mzR                 | 2.42.0 (also rebuilt from source — no change) |
| MsCoreUtils         | 1.20.0                                        |
| ProtGenerics        | 1.40.0                                        |
| S4Vectors           | 0.46.0                                        |
| BiocParallel        | 1.42.2                                        |
| `bpparam()` default | **SnowParam, workers = 6**                    |

Test file: a 30 MB **centroided, indexed, zlib-compressed** mzML, 1814
MS1 spectra, median 1161 peaks/spectrum (human urine, LC-MS positive).
Behaviour reproduces across all 140 files in the dataset.

## Timings

### Raw mzR vs the Spectra layer (default BiocParallel)

| Operation | Time |
|----|---:|
| [`mzR::openMSfile()`](https://rdrr.io/pkg/mzR/man/openMSfile.html) | 0.04 s |
| [`mzR::header()`](https://rdrr.io/pkg/mzR/man/peaks.html) (all 1814 spectra) | 0.08 s |
| [`mzR::peaks()`](https://rdrr.io/pkg/ProtGenerics/man/protgenerics.html) (ALL peak data) | 0.52 s |
| **`Spectra(f, MsBackendMzR())`** | **83.9 s** |
| `rtime(sp)` (after construct) | 0.00 s |
| `peaksData(sp)` (after construct) | 0.59 s |
| `setBackend(sp, MsBackendMemory())` | 0.72 s |
| **`readMsExperiment(f)`** | **80.6 s** |
| **`chromatogram(xe, mz=...)`** | **92.9 s** |
| manual EIC on in-memory peaks | 0.14 s |

So raw mzR reads the **entire file in ~0.6 s**; the 80–93 s is incurred
purely in the Spectra/xcms construction path, and is paid again on every
`chromatogram()` call.

### Same operations with `register(SerialParam())`

| Operation                    | Default (SnowParam 6) | SerialParam |
|------------------------------|----------------------:|------------:|
| `Spectra(f, MsBackendMzR())` |               146.7 s |  **0.75 s** |
| `readMsExperiment(f)`        |                80.6 s |  **0.31 s** |
| `chromatogram()` TIC         |                88.4 s |  **1.58 s** |
| `chromatogram()` EIC (1 m/z) |                92.9 s |  **1.06 s** |

## Root cause (Rprof)

`Rprof(line.profiling = TRUE)` around `Spectra(f, MsBackendMzR())`
(total 109.7 s):

    == top by SELF time ==
                             self.time self.pct
    DeveloperInterface.R#122     79.04    72.08   # BiocParallel cluster mgmt
    SnowParam-class.R#243        29.36    26.77   # SnowParam workers

    == top by TOTAL time ==
    bplapply-methods.R#57       108.90    99.31
    bpinit.R#47 / bploop.R#325   79.20    72.22
    SnowParam-class.R#243        29.36    26.77

~99% of the time is inside
[`BiocParallel::bplapply`](https://rdrr.io/pkg/BiocParallel/man/bplapply.html)
→ SnowParam cluster start (`bpstart`/`bploop`) and worker management —
i.e. spawning a socket cluster and having each of the 6 workers
initialise (load packages) — **not** the actual header read.

## The exact call site

`Spectra/R/MsBackendMzR.R`, `backendInitialize`:

``` r
setMethod("backendInitialize", "MsBackendMzR",
          function(object, files, ..., BPPARAM = bpparam()) {     # default = SnowParam(6)
              ...
              spectraData <- rbindlistWithRownames(
                  bplapply(files, FUN = function(fl) {            # cluster spawned per call
                      cbind(Spectra:::.mzR_header(fl), dataStorage = fl)
                  }, BPPARAM = BPPARAM), use.names = TRUE, fill = TRUE)
              ...
```

Because the default `bpparam()` is an **unstarted** SnowParam, every
`bplapply` call does an internal `bpstart` + `bpstop` (full cluster
spawn + teardown). When the number of files is small (or one), the
cluster-spawn overhead dwarfs the work, and it is repeated for every
`Spectra()`/`chromatogram()` call.

## Suggested fixes (for upstream discussion)

1.  **Default to `SerialParam()` for header reads** (or when
    `length(files)` is below a threshold) in
    `MsBackendMzR::backendInitialize` — per-file header reads are cheap
    and rarely benefit from a freshly-spawned cluster.
2.  Document prominently that interactive/Windows users should
    `register(SerialParam())` (or use a persistent/lightweight backend,
    e.g. a `mirai`-based one) — the default SnowParam re-spawns a
    cluster per `bplapply`.
3.  Consider whether `chromatogram()` and friends should reuse a single
    started cluster rather than spawning one per call.

## What xcmsVisGUI does about it

The GUI reads files **directly with mzR** (`openMSfile` + `header` +
`peaks`, ~0.6 s/file), caches the result in memory, and computes
TIC/BPC/EIC/MS-map/spectrum/precursors itself (manual EIC per the xcms
\#809 discussion). This sidesteps the Spectra construction cost
entirely. If/when the upstream `SnowParam` default is addressed, the GUI
could move back onto `Spectra`/`xcms`/`xcmsVis` (regaining its full
filter set) by registering `SerialParam()`.
