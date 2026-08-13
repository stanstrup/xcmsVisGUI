# The app-level reactive graph. `included` is the root of every extraction, so
# how often it updates decides how often the app re-reads the files.

# Paths must EXIST: the reactive graph normalizePath()es them, which warns on a
# missing file. The rows are never read, so empty placeholder files are enough.
stub_dir <- file.path(tempdir(), "appsrv")
dir.create(stub_dir, showWarnings = FALSE)
stub_paths <- file.path(stub_dir, sprintf("f%d.mzML", 1:3))
file.create(stub_paths[!file.exists(stub_paths)])

ready_rows <- function(n) {
  tibble::tibble(
    id = paste0("f", seq_len(n)), path = stub_paths[seq_len(n)],
    name = paste0("f", seq_len(n), ".mzML"), sample_group = "group1",
    include = TRUE, status = "ready", n_spectra = 10L,
    rt_min = 0, rt_max = 60, mz_min = 100, mz_max = 500,
    ms_levels = "1", polarities = "pos", charges = NA_character_,
    spec_mode = "centroid", message = NA_character_)
}

test_that("a burst of file (de)selections settles into one update", {
  # Regression (#4): every tick wrote rv$files$include and immediately
  # invalidated included() -> data_key() -> a full re-extract and redraw.
  # Unticking ten files meant ten redraws. The set is now debounced.
  shiny::testServer(app_server, {
    rv$files <- ready_rows(1)
    session$flushReact()
    expect_equal(nrow(included()), 1L)      # first value arrives with no delay

    rv$files <- ready_rows(3)               # two more ticked in quick succession
    session$flushReact()
    expect_equal(nrow(included()), 1L)      # not yet — still settling

    session$elapse(SELECTION_DEBOUNCE_MS + 50)
    expect_equal(nrow(included()), 3L)      # one update for the whole burst

    # ...and untick back down, again as a single settled update
    rv$files$include <- c(TRUE, FALSE, FALSE)
    session$flushReact()
    expect_equal(nrow(included()), 3L)
    session$elapse(SELECTION_DEBOUNCE_MS + 50)
    expect_equal(nrow(included()), 1L)
  })
})
