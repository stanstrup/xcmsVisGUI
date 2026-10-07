# Plot export. The saved file must match what the user is looking at.

test_that("apply_zoom clips the exported plot to the current zoom", {
  # "Save plot" must save what you are looking at: the plotly zoom held by
  # zoom_keeper is applied as coord limits before the preview/ggsave render.
  p <- ggplot2::ggplot(data.frame(x = 1:10, y = 1:10), ggplot2::aes(x, y)) +
    ggplot2::geom_point()
  expect_identical(apply_zoom(p, NULL), p)                       # unzoomed
  expect_identical(apply_zoom(p, list(x = NULL, y = NULL)), p)   # zoom reset

  zx <- apply_zoom(p, list(x = c(2, 5), y = NULL))
  expect_equal(zx$coordinates$limits$x, c(2, 5))
  expect_null(zx$coordinates$limits$y)                           # y stays free

  zb <- apply_zoom(p, list(x = c(2, 5), y = c(3, 4)))
  expect_equal(zb$coordinates$limits$x, c(2, 5))
  expect_equal(zb$coordinates$limits$y, c(3, 4))
  # the ranges really do restrict the built panel, not just the object (the
  # built range is the limits plus the usual axis expansion, so bracket it
  # rather than pinning exact numbers)
  rng <- ggplot2::ggplot_build(zb)$layout$panel_params[[1]]$x.range
  expect_true(rng[1] > 1 && rng[2] < 6)
})

test_that("zoom_keeper$reset drops only the axes it is given", {
  # Regression (#7): a pinned y range is meaningful only while the axis keeps its
  # units. Switching the EIC intensity scaling (counts -> 0-1) re-applied the old
  # range, so with "Facet by file" one panel stayed at 0-250k while the
  # normalised trace sat under 1.0 and the peak vanished. Scale/facet/layout
  # controls now reset "y" and keep the rt window.
  shiny::testServer(function(input, output, session) {
    prime_plotly_events(session, "t")   # as app_server does; silences plotly's
    zoom <- zoom_keeper("t")            # "source not registered" warning
    session$userData$zoom <- zoom
  }, {
    z <- session$userData$zoom
    # Stand in for a box zoom: reach the keeper's own reactiveValues, since
    # testServer cannot deliver a real plotly_relayout event.
    zi <- environment(z$apply)$z
    zi$x <- c(56, 58); zi$y <- c(0, 250000)
    session$flushReact()
    expect_equal(z$ranges()$x, c(56, 58))
    expect_equal(z$ranges()$y, c(0, 250000))

    z$reset("y")                       # the scaling control changed
    session$flushReact()
    expect_null(z$ranges()$y)          # stale intensity range dropped
    expect_equal(z$ranges()$x, c(56, 58))   # rt window kept

    z$reset()                          # double-click == forget everything
    session$flushReact()
    expect_null(z$ranges()$x)
    expect_null(z$ranges()$y)
  })
})

test_that("spectrum_table exports the drawn spectrum; table_tsv is tab-separated", {
  df <- tibble::tibble(mz = c(100.12345, 200.5), intensity = c(10, 2000),
                       rt = c(120, 120), scan = c(7L, 7L), profile = c(TRUE, TRUE),
                       sample_name = "a")
  tab <- spectrum_table(df, "min")
  expect_named(tab, c("file", "scan", "rt_min", "mz", "intensity", "mode"))
  expect_equal(tab$rt_min, c(2, 2))
  expect_equal(tab$mz, df$mz)                     # full precision, no rounding
  expect_identical(tab$mode, c("profile", "profile"))
  expect_identical(spectrum_table(df[0, ], "sec")$mz, numeric())

  tsv <- strsplit(table_tsv(tab), "\n")[[1]]
  expect_length(tsv, 3)
  expect_identical(tsv[1], "file\tscan\trt_min\tmz\tintensity\tmode")
  expect_identical(strsplit(tsv[2], "\t")[[1]][4], "100.12345")
})
