# Export each interactive plot as a VECTOR SVG (crisp at any zoom), via plotly's
# own Plotly.toImage(format = "svg") in headless Chrome (chromote). Complements
# capture-screenshots.R (which captures the full UI as PNG — Chrome can only
# screenshot raster). These SVGs are the PLOT ONLY (no sidebar chrome).
#
# NOTE: the 2-D MS map draws with scattergl (WebGL) for speed, so its SVG embeds a
# raster image for the points; the other plots are pure SVG. For a fully-vector MS
# map, drop the contrast/point count first, or export from a non-gl view.
#
# Run with the app serving on port 7799 (see capture-screenshots.R), then:
#   Rscript data-raw/capture-plots-svg.R
# Writes vignettes/articles/figures/svg/<name>.svg.

library(chromote)
figdir <- "vignettes/articles/figures/svg"
dir.create(figdir, recursive = TRUE, showWarnings = FALSE)

faahko <- normalizePath(system.file("cdf", "KO", package = "faahKO"), winslash = "/")
ms3    <- normalizePath(list.files(system.file("proteomics", package = "msdata"),
                                   pattern = "mzML$", full.names = TRUE)[1], winslash = "/")

b <- ChromoteSession$new(width = 1440, height = 900); on.exit(b$close(), add = TRUE)
ev  <- function(c, await = FALSE) b$Runtime$evaluate(c, awaitPromise = await)$result$value
typ <- function(id, val) ev(sprintf("(()=>{const e=document.getElementById(%s);if(!e)return'NOEL';e.value=%s;e.dispatchEvent(new Event('input',{bubbles:true}));e.dispatchEvent(new Event('change',{bubbles:true}));return e.value})()", shQuote(id), shQuote(as.character(val))))
click<- function(id) ev(sprintf("(()=>{const e=document.getElementById(%s);if(e){e.click();return true}return false})()", shQuote(id)))
nav  <- function(l) ev(sprintf("(()=>{const a=[...document.querySelectorAll('.nav-link,.navbar a')].find(e=>e.textContent.trim()===%s);if(a){a.click();return true}return false})()", shQuote(l)))
incl <- function() ev("(()=>{const t=$('#ingest-file_table').data('datatable');if(t&&t.shinyMethods){var n=t.rows().count(),a=[];for(var i=1;i<=n;i++)a.push(i);t.shinyMethods.selectRows(a);return n}return 0})()")
waitrows <- function(n = 1, tries = 25) for (i in seq_len(tries)) { Sys.sleep(1)
  if (isTRUE(ev("(()=>{const t=$('#ingest-file_table').data('datatable');return t?t.rows().count():0})()") >= n)) break }

# Export the plotly graph div `gid` to a vector SVG file.
svgshot <- function(gid, name, w = 1000, h = 560, pause = 2) {
  Sys.sleep(pause)
  url <- ev(sprintf("(async()=>{const gd=document.getElementById('%s');if(!gd)return'NOGD';return await Plotly.toImage(gd,{format:'svg',width:%d,height:%d})})()", gid, w, h), await = TRUE)
  if (identical(url, "NOGD") || is.null(url)) { message("  ! no plot for ", name); return(invisible()) }
  svg <- utils::URLdecode(sub("^data:image/svg\\+xml,", "", url))
  writeLines(svg, file.path(figdir, name)); message("  ", name, " (", nchar(svg), " bytes)")
}

b$Page$navigate("http://127.0.0.1:7799"); b$Page$loadEventFired(); Sys.sleep(5)

message("faahKO plots ...")
typ("ingest-folder", faahko); Sys.sleep(1); click("ingest-add_folder")
waitrows(6); Sys.sleep(2); incl(); Sys.sleep(3)
nav("TIC / BPC"); svgshot("tic-plot", "tic.svg", pause = 6)

nav("EIC"); Sys.sleep(1)
ev("Shiny.setInputValue('eic-paste','300.2\\n335.1\\n195.0877'); true"); Sys.sleep(1.5); click("eic-parse")
svgshot("eic-plot", "eic.svg", pause = 6)

nav("Spectrum"); Sys.sleep(1)
typ("spec-rt", "47"); svgshot("spec-plot", "spectrum.svg", pause = 5)

nav("MS map"); Sys.sleep(1); click("map-plot"); svgshot("map-plot_out", "msmap.svg", pause = 12)

message("MS3TMT11 (profile spectrum + precursors) ...")
nav("TIC / BPC"); Sys.sleep(1)
js_show <- "var cs=document.querySelectorAll('.accordion-collapse'); if(cs.length>=1){bootstrap.Collapse.getOrCreateInstance(cs[0],{toggle:false}).show();} true"
ev(js_show); click("ingest-clear"); Sys.sleep(2)
typ("ingest-folder", ms3); Sys.sleep(1); click("ingest-add_folder")
waitrows(1); Sys.sleep(2); incl(); Sys.sleep(3)
nav("Spectrum"); Sys.sleep(1)
ev("Shiny.setInputValue('filter-ms_level','1'); true"); Sys.sleep(1)
typ("spec-rt", ""); typ("spec-scan", "22413"); ev("Shiny.setInputValue('spec-scan',22413); true")
svgshot("spec-plot", "spectrum_profile.svg", pause = 6)
nav("Precursors"); svgshot("prec-plot", "precursors.svg", pause = 8)

message("done")
