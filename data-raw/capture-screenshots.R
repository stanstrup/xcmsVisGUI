# Capture the screenshots used in the pkgdown usage articles.
#
# Drives a running app with headless Chrome (chromote) and writes PNGs to
# vignettes/articles/figures/. Chrome captures raster only, so these are PNG; a
# vector figure of a single plot can instead be exported from that view's Save
# button (png/svg/pdf). Run with the app already serving on port 7799:
#   Rscript -e "pkgload::load_all('.'); run_app(port = 7799, launch.browser = FALSE)"
# then, in another process:
#   Rscript data-raw/capture-screenshots.R
#
# faahKO (6 centroid CDF) drives the chromatogram / map / EIC shots; msdata's
# MS3TMT11.mzML (profile MS1 + centroided MS2/3) drives the profile-mode, peak-
# picking, annotation and isotope-pattern shots, and the DDA precursor map.

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
# Set a Shiny input directly (for selectize / radio inputs that typeinto can't hit).
setin <- function(id, val) js(sprintf("Shiny.setInputValue(%s, %s); true",
                                      shQuote(id), if (is.numeric(val)) val else shQuote(val)))
# Same, but a JS literal + priority 'event' — needed for conditionalPanel widgets
# (which don't transmit their values until interacted with) and array inputs.
setev <- function(id, v) js(sprintf("Shiny.setInputValue('%s', %s, {priority:'event'}); true", id, v))
# Include ALL files: call the DT Shiny binding's selectRows the way the All button
# does — the instance that carries shinyMethods is on $('#..').data('datatable'),
# NOT $(el).DataTable(). A synthetic .click() on the button doesn't fire under
# chromote, so drive it directly and return the row count.
incl_all <- function() js(
  "(()=>{const t=$('#ingest-file_table').data('datatable');if(t&&t.shinyMethods){var n=t.rows().count(),a=[];for(var i=1;i<=n;i++)a.push(i);t.shinyMethods.selectRows(a);return n}return 0})()")
# Wait until at least one file row has been read into the table.
waitrows <- function(n = 1, tries = 25) for (i in seq_len(tries)) {
  Sys.sleep(1)
  if (isTRUE(js("(()=>{const t=$('#ingest-file_table').data('datatable');return t?t.rows().count():0})()") >= n)) break
}

b$Page$navigate("http://127.0.0.1:7799")
b$Page$loadEventFired(); Sys.sleep(5)

## --- faahKO: chromatograms, filters, EIC, map ------------------------------
message("loading faahKO ...")
typeinto("ingest-folder", faahko); Sys.sleep(1); click("ingest-add_folder")
waitrows(6)                                     # 6 files read via the mirai queue
Sys.sleep(2); incl_all(); Sys.sleep(3)
shot("tic.png", 6)                              # Files panel (with Mode column) + TIC overlay

# Filters: collapse Files, expand Filters (sidebar accordion is single-open).
js("var cs=document.querySelectorAll('.accordion-collapse'); if(cs.length>=2){bootstrap.Collapse.getOrCreateInstance(cs[0],{toggle:false}).hide(); bootstrap.Collapse.getOrCreateInstance(cs[1],{toggle:false}).show();} true")
shot("filters.png", 3)
js("var cs=document.querySelectorAll('.accordion-collapse'); if(cs.length>=2){bootstrap.Collapse.getOrCreateInstance(cs[1],{toggle:false}).hide(); bootstrap.Collapse.getOrCreateInstance(cs[0],{toggle:false}).show();} true")

message("EIC (incl. the intensity-scaling control) ...")
nav("EIC"); Sys.sleep(1)
js("Shiny.setInputValue('eic-paste', '300.2\\n335.1\\n195.0877'); true"); Sys.sleep(1.5); click("eic-parse")
shot("eic.png", 7)

message("Spectrum (centroided example) ...")
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

## --- MS3TMT11: profile mode, peak-picking panel, DDA precursors ------------
message("clearing, loading MS3TMT11 (profile) ...")
nav("TIC / BPC"); Sys.sleep(1)
js("var cs=document.querySelectorAll('.accordion-collapse'); if(cs.length>=1){bootstrap.Collapse.getOrCreateInstance(cs[0],{toggle:false}).show();} true")
click("ingest-clear"); Sys.sleep(2)
typeinto("ingest-folder", ms3); Sys.sleep(1); click("ingest-add_folder")
waitrows(1); Sys.sleep(2); incl_all(); Sys.sleep(3)

message("profile spectrum + peak-picking panel ...")
nav("Spectrum"); Sys.sleep(1)
setin("filter-ms_level", "1"); Sys.sleep(1)         # MS1 is the profile level
typeinto("spec-rt", "")                              # clear any stale rt so the scan drives it
typeinto("spec-scan", "22413"); setin("spec-scan", 22413)   # a mid profile MS1 scan
shot("spectrum_profile.png", 6)                      # raw profile line + Peak-picking controls

message("isotope-pattern annotation (fine-structure envelope) ...")
# stay on Spectrum with MS3TMT11 scan 22413 loaded; turn annotation on and switch
# Mode to the formula-based isotope pattern.
click("spec-annotate"); Sys.sleep(2)
js("(()=>{const e=document.getElementById('spec-ann_mode');if(e&&e.selectize)e.selectize.setValue('iso');return true})()"); Sys.sleep(3)
click("spec-showpts"); Sys.sleep(1)                  # raw points under the envelope
# Feed every input the iso reactives read: the conditionalPanel widgets don't
# transmit until interacted with, and the anchor is server-updated one-way.
setev("spec-ann_pol", "'pos'"); setev("spec-ann_adduct", "'[M+H]+'")
setev("spec-ann_unit", "'ppm'"); setev("spec-ann_tol", 30)
setev("spec-ann_min_int", 0); setev("spec-ann_match_snr", 0)
setev("spec-anchor_mz", 582.3448)                    # the scan's base peak
setev("spec-iso_elements", "['C','H','N','O','P','S','F','Cl','Br']")
setev("spec-iso_valid", "false"); setev("spec-iso_res", 60000)
for (i in 1:20) { Sys.sleep(1)                        # wait for the candidate table
  if (isTRUE(js("(()=>{const t=document.getElementById('spec-iso_cands');return t?t.querySelectorAll('tbody tr').length:0})()") > 0)) break }
Sys.sleep(3)                                          # let the plot settle, then zoom LAST
js("(()=>{const gd=document.getElementById('spec-plot');if(gd&&window.Plotly)Plotly.relayout(gd,{'xaxis.range':[580.5,586.5],'xaxis.autorange':false,'yaxis.autorange':true});return true})()")
shot("isotope.png", 2)                                # envelope over the raw profile cluster

message("Precursors ...")
nav("Precursors"); shot("precursors.png", 8)

message("Settings ...")
nav("Settings"); shot("settings.png", 2)

message("done")
