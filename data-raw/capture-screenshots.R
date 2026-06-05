# Capture the screenshots used in the pkgdown usage article.
#
# Drives a running app with headless Chrome (chromote) and writes PNGs to
# vignettes/articles/figures/. Run with the app already serving on port 7799:
#   Rscript -e "pkgload::load_all('.'); run_app(port = 7799, launch.browser = FALSE)"
# then, in another process:
#   Rscript data-raw/capture-screenshots.R
#
# Uses the faahKO (6 CDF) and msdata (MS3TMT11.mzML) demo data.

library(chromote)
figdir <- "vignettes/articles/figures"
dir.create(figdir, recursive = TRUE, showWarnings = FALSE)

faahko <- normalizePath(system.file("cdf", "KO", package = "faahKO"), winslash = "/")
ms3    <- normalizePath(list.files(system.file("proteomics", package = "msdata"),
                                   pattern = "mzML$", full.names = TRUE)[1], winslash = "/")

b <- ChromoteSession$new(width = 1440, height = 900)
on.exit(b$close(), add = TRUE)
js   <- function(code) b$Runtime$evaluate(code)$result$value
shot <- function(name, pause = 1.5) { Sys.sleep(pause); b$screenshot(file.path(figdir, name)); message("  ", name) }

# Set a text/numeric input's value and notify Shiny (more reliable than
# setInputValue for widget-backed inputs), then click controls by element id.
typeinto <- function(id, val) js(sprintf(
  "(()=>{const e=document.getElementById(%s);e.value=%s;e.dispatchEvent(new Event('input',{bubbles:true}));e.dispatchEvent(new Event('change',{bubbles:true}));return e.value})()",
  shQuote(id), shQuote(as.character(val))))
click <- function(id) js(sprintf(
  "(()=>{const e=document.getElementById(%s);if(e){e.click();return true}return false})()", shQuote(id)))
nav <- function(label) js(sprintf(
  "(()=>{const a=[...document.querySelectorAll('.nav-link,.navbar a')].find(e=>e.textContent.trim()===%s);if(a){a.click();return true}return false})()",
  shQuote(label)))

b$Page$navigate("http://127.0.0.1:7799")
b$Page$loadEventFired(); Sys.sleep(5)

message("loading faahKO ...")
typeinto("ingest-folder", faahko); Sys.sleep(1); click("ingest-add_folder")
Sys.sleep(15)                                   # 6 files read via the mirai queue
click("ingest-sel_all")
shot("tic.png", 6)                              # Files panel + TIC overlay

# Filters: collapse Files, expand Filters (sidebar accordion is single-open).
js("var cs=document.querySelectorAll('.accordion-collapse'); if(cs.length>=2){bootstrap.Collapse.getOrCreateInstance(cs[0],{toggle:false}).hide(); bootstrap.Collapse.getOrCreateInstance(cs[1],{toggle:false}).show();} true")
shot("filters.png", 3)
js("var cs=document.querySelectorAll('.accordion-collapse'); if(cs.length>=2){bootstrap.Collapse.getOrCreateInstance(cs[1],{toggle:false}).hide(); bootstrap.Collapse.getOrCreateInstance(cs[0],{toggle:false}).show();} true")

message("EIC ...")
nav("EIC"); Sys.sleep(1)
js("Shiny.setInputValue('eic-paste', '300.2\\n335.1\\n195.0877'); true"); Sys.sleep(1.5); click("eic-parse")
shot("eic.png", 7)

message("Spectrum ...")
nav("Spectrum"); Sys.sleep(1)
typeinto("spec-rt", "47"); shot("spectrum.png", 5)
click("spec-scanlist"); shot("scanlist.png", 3)
js("(()=>{const x=[...document.querySelectorAll('.modal-footer button,.modal [data-bs-dismiss=modal]')].pop();if(x)x.click();return true})()")
Sys.sleep(1)

message("MS map ...")
nav("MS map"); Sys.sleep(1)
click("map-plot"); shot("msmap.png", 12)
js("(()=>{const r=document.querySelector('input[name=\"map-mode\"][value=\"surface\"]');if(r)r.click();return true})()")
Sys.sleep(1); click("map-plot"); shot("msmap3d.png", 12)

message("Precursors (add MS3TMT11) ...")
nav("TIC / BPC"); Sys.sleep(1)
typeinto("ingest-folder", ms3); Sys.sleep(1); click("ingest-add_folder")
Sys.sleep(6); click("ingest-sel_all"); Sys.sleep(3)
nav("Precursors"); shot("precursors.png", 8)

message("Settings ...")
nav("Settings"); shot("settings.png", 2)

message("done")
