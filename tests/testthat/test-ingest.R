# File-ingest queue. The reader is a single-slot async ExtendedTask fed by a
# queue, so the invariant that matters is: whatever happens, the queue keeps
# draining and no row is left stranded on "reading".

skip_if_not_installed("msdata")

msdata_file <- function() {
  normalizePath(list.files(system.file("proteomics", package = "msdata"),
                           full.names = TRUE, pattern = "mzML$")[1])
}

# Pump the reactive graph until no file is still "reading" (or we give up).
drain <- function(session, rv, tries = 60) {
  for (i in seq_len(tries)) {
    Sys.sleep(0.25)
    session$flushReact()
    if (nrow(rv$files) && !any(rv$files$status == "reading")) return(invisible(TRUE))
  }
  invisible(FALSE)
}

test_that("Clear all during an in-flight read does not wedge the queue", {
  # Regression: the reader's completion handler bailed out early when "Clear all"
  # had orphaned the in-flight read (current() == NULL) — WITHOUT pumping. Any
  # file queued behind it was then stranded: the reader sat idle and the file list
  # showed the hourglass for ever. The handler must always pump.
  set_daemons(1)
  p <- msdata_file()
  rv <- make_rv()

  shiny::testServer(mod_ingest_server, args = list(rv = rv), {
    session$setInputs(folder = p, add_folder = 1)   # starts reading
    expect_equal(rv$files$status, "reading")

    session$setInputs(clear = 1)                    # orphan the in-flight read
    expect_equal(nrow(rv$files), 0L)

    session$setInputs(folder = p, add_folder = 2)   # re-add before it finishes
    drain(session, rv)
    expect_equal(rv$files$status, "ready")          # was stuck on "reading"
    expect_equal(rv$files$spec_mode, "mixed")       # MS3TMT11: profile MS1 + centroid MS2/3
  })
})

test_that("file ids are unique across a Clear all within the same second", {
  # Ids used to be Sys.time() seconds + the row index, and Clear all resets the
  # index — so a re-add in the same second reissued the very same ids, letting a
  # stale in-flight result write onto the fresh row.
  set_daemons(1)
  p <- msdata_file()
  rv <- make_rv()

  shiny::testServer(mod_ingest_server, args = list(rv = rv), {
    session$setInputs(folder = p, add_folder = 1)
    first <- rv$files$id
    session$setInputs(clear = 1)
    session$setInputs(folder = p, add_folder = 2)   # same second, fresh row
    expect_false(any(rv$files$id %in% first))
    drain(session, rv)
  })
})
