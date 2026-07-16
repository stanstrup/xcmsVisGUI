# Spectrum-view module glue. The extraction/centroiding is covered in
# test-filters.R; here we guard the plot-layer wiring for the profile extras
# (show data points, overlay centroids) by driving the real module with
# testServer on a profile spectrum from msdata.

skip_if_not_installed("msdata")

profile_file <- function() {
  # MS3TMT11.mzML is mixed: profile MS1 + centroided MS2/MS3.
  normalizePath(list.files(system.file("proteomics", package = "msdata"),
                           full.names = TRUE, pattern = "mzML$")[1])
}

test_that("show-points and overlay add the expected profile plot layers", {
  p <- profile_file()
  raw <- get_spectra(p)
  pr <- which(!Spectra::centroided(raw))
  skip_if_not(length(pr) > 0, "no profile spectra in test file")
  rt_min <- Spectra::rtime(raw)[pr[1]] / 60   # module rt input is in display units (min)

  files <- tibble::tibble(
    id = "f1", path = p, name = basename(p), sample_group = "g1",
    include = TRUE, status = "ready", n_spectra = length(raw),
    rt_min = 0, rt_max = 1e5, mz_min = 0, mz_max = 1e4,
    ms_levels = "1", polarities = "1", charges = NA_character_,
    spec_mode = "mixed", message = NA_character_)

  rv <- make_rv(); rv$files <- files
  rv$filter <- modifyList(empty_filter(), list(ms_level = 1L))  # the profile level
  included <- reactive(files)

  # `text` is not a real ggplot aesthetic (ggplotly consumes it for tooltips), so
  # ggplot2 v4 warns when the layers materialize — intrinsic to every plot in this
  # app, and deferred past any inner wrap. Suppress at the whole testServer call;
  # this silences warnings only, not expectation failures.
  suppressWarnings(shiny::testServer(mod_plot_spectrum_server,
                    args = list(rv = rv, included = included), {
    geoms <- function() vapply(plot_gg()$layers, function(l) class(l$geom)[1],
                               character(1))
    session$setInputs(layout = "single", rt = rt_min, scan = NA, annotate = FALSE,
                      cmode = "off", csnr = 0, chws = 2, ck = 0, showpts = FALSE)
    d <- spec_df()
    skip_if_not(isTRUE(all(d$profile)), "selected spectrum is not profile")
    expect_setequal(geoms(), "GeomLine")                     # raw profile is a line

    session$setInputs(showpts = TRUE)
    expect_true("GeomPoint" %in% geoms())                    # data points added

    # "overlay" mode: raw line + centroids drawn on top
    session$setInputs(showpts = FALSE, cmode = "overlay")
    ov <- overlay_df()
    expect_gt(nrow(ov), 0)
    expect_false(any(ov$profile))                            # overlay is centroided
    expect_true(all(c("GeomLine", "GeomLinerange", "GeomPoint") %in% geoms()))

    # overlay only applies in the overlay mode
    session$setInputs(cmode = "auto")
    expect_equal(nrow(overlay_df()), 0)
  }))
})
