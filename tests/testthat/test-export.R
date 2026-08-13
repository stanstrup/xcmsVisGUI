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
