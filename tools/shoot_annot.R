# Regenerate vignettes/articles/figures/annotation.png.
#
# Drives a *running* app (run_app(port = 7799)) with chromote: loads one
# small-molecule file, opens the Spectrum tab at the given scan, ticks
# "Annotate adducts / fragments", and screenshots the overlay.
#
#   Rscript -e "source('renv/activate.R'); source('tools/shoot_annot.R')" <mzML-path> <scan>
#
# Use a file with annotatable spectra (adducts / in-source fragments / isotopes);
# a centroided small-molecule LC-MS run works best.
suppressMessages(library(chromote))
URL <- "http://127.0.0.1:7799/"
FIG <- "vignettes/articles/figures"
args <- commandArgs(trailingOnly = TRUE)
FILE <- args[1]
SCAN <- suppressWarnings(as.integer(args[2]))
if (is.na(FILE) || !nzchar(FILE)) stop("usage: shoot_annot.R <mzML-path> <scan>")
if (is.na(SCAN)) SCAN <- 1L
say <- function(...) { cat(..., "\n"); flush.console() }

b <- ChromoteSession$new(); say("session up")
vp <- function() b$set_viewport_size(width = 1440, height = 900); vp()
b$Page$navigate(URL, wait_ = FALSE)
js <- function(code) b$Runtime$evaluate(code, returnByValue = TRUE)$result$value
wait_for <- function(code, timeout = 60, msg = "") {
  t0 <- Sys.time(); repeat {
    v <- tryCatch(js(code), error = function(e) NULL)
    if (isTRUE(v)) return(invisible(TRUE))
    if (as.numeric(Sys.time() - t0) > timeout) stop("timeout: ", msg)
    Sys.sleep(0.5)
  }
}
wait_for("typeof Shiny!=='undefined' && Shiny.shinyapp && Shiny.shinyapp.isConnected()", 40, "shiny")
say("connected")
js(sprintf("(function(){var i=document.getElementById('ingest-folder');i.value='%s';i.dispatchEvent(new Event('input',{bubbles:true}));Shiny.setInputValue('ingest-folder',i.value,{priority:'event'});document.getElementById('ingest-add_folder').click();return 'ok';})()", gsub("\\\\", "/", FILE)))
wait_for("document.querySelectorAll('#ingest-file_table tbody tr').length >= 1", 40, "row")
wait_for("(function(){var c=document.querySelector('#ingest-file_table tbody tr:nth-child(1) td:nth-child(4)');return c&&c.innerText.trim().length>0;})()", 60, "read")
js("(function(){var b=Array.from(document.querySelectorAll('button')).find(function(x){return x.textContent.trim()==='All'&&x.getAttribute('onclick');});b.click();return 'ok';})()")
js("(function(){var a=Array.from(document.querySelectorAll('.nav-link')).find(function(x){return /Spectrum/.test(x.textContent);});if(a)a.click();return 'ok';})()")
Sys.sleep(1)
js(sprintf("(function(){var s=document.getElementById('spec-scan');s.value='%d';s.dispatchEvent(new Event('input',{bubbles:true}));s.dispatchEvent(new Event('change',{bubbles:true}));Shiny.setInputValue('spec-scan',%d,{priority:'event'});return 'ok';})()", SCAN, SCAN))
wait_for("document.querySelectorAll('#spec-plot .scatterlayer .trace, #spec-plot path.js-line').length>=1 && document.querySelectorAll('.shiny-notification').length===0", 60, "spectrum")
say("spectrum rendered")
Sys.sleep(1)
js("(function(){var c=document.getElementById('spec-annotate');if(!c.checked)c.click();Shiny.setInputValue('spec-annotate',true,{priority:'event'});return 'ok';})()")
wait_for("document.querySelectorAll('.shiny-notification').length===0", 30, "settle")
Sys.sleep(3)
vp(); b$screenshot(filename = file.path(FIG, "annotation.png")); say("saved annotation.png")
say("DONE"); b$close()
