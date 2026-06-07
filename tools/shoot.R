# Capture pkgdown screenshots (TIC + Filters) using faahKO, via chromote.
suppressMessages(library(chromote))
URL <- "http://127.0.0.1:7799/"
FIG <- "vignettes/articles/figures"
FOLDER <- system.file("cdf", "KO", package = "faahKO")
say <- function(...) { cat(..., "\n"); flush.console() }

b <- ChromoteSession$new(); say("session up")
vp <- function() b$set_viewport_size(width = 1440, height = 900)
vp()
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
shot <- function(file) { vp(); Sys.sleep(0.8); b$screenshot(filename = file.path(FIG, file)); say("saved", file) }

wait_for("typeof Shiny!=='undefined' && Shiny.shinyapp && Shiny.shinyapp.isConnected()", 40, "shiny")
say("connected")
js(sprintf("(function(){var i=document.getElementById('ingest-folder');i.value='%s';i.dispatchEvent(new Event('input',{bubbles:true}));Shiny.setInputValue('ingest-folder',i.value,{priority:'event'});document.getElementById('ingest-add_folder').click();return 'ok';})()", FOLDER))
wait_for("document.querySelectorAll('#ingest-file_table tbody tr').length >= 6", 40, "rows")
wait_for("(function(){var n=document.querySelectorAll('#ingest-file_table tbody tr').length,ok=0;for(var i=1;i<=n;i++){var c=document.querySelector('#ingest-file_table tbody tr:nth-child('+i+') td:nth-child(4)');if(c&&c.innerText.trim().length>0)ok++;}return ok>=n;})()", 60, "all read")
say("all read")
# select all in ONE client action (the All button) -> single extraction
js("(function(){var b=Array.from(document.querySelectorAll('button')).find(function(x){return x.textContent.trim()==='All'&&x.getAttribute('onclick');});b.click();return 'ok';})()")
say("clicked All")
# wait for extraction to FULLY finish: 6 traces and the progress toast gone
wait_for("document.querySelectorAll('#tic-plot .scatterlayer .trace').length>=6 && document.querySelectorAll('.shiny-notification').length===0", 90, "tic done")
Sys.sleep(1.5)
shot("tic.png")

# Filters: collapse Files so the whole Filters panel (incl. Spectrum ID rules) shows
js("(function(){var fs=Array.from(document.querySelectorAll('.accordion-button'));var files=fs.find(function(e){return /Files/.test(e.textContent);});var filt=fs.find(function(e){return /Filters/.test(e.textContent);});if(filt&&filt.classList.contains('collapsed'))filt.click();if(files&&!files.classList.contains('collapsed'))files.click();return 'ok';})()")
Sys.sleep(0.8)
js("document.getElementById('filter-id_add').click(); 'ok'")
wait_for("document.querySelector('#filter-id_rules > div')!==null", 20, "rule")
# leave the rule's term as the placeholder (illustrative); set mode select visible
Sys.sleep(1.2)
shot("filters.png")
say("DONE"); b$close()
