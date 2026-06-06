# The qs2-backed, cachem-compatible disk cache used for persistent bindCache.

test_that("cache_disk_qs2 round-trips values and reports misses", {
  d <- withr::local_tempdir()
  ca <- cache_disk_qs2(d)
  ca$set("k1", tibble::tibble(a = 1:3, b = letters[1:3]))
  expect_equal(nrow(ca$get("k1")), 3)
  expect_identical(ca$get("k1")$b, c("a", "b", "c"))
  expect_true(cachem::is.key_missing(ca$get("absent")))
  expect_true(ca$exists("k1"))
  expect_identical(ca$keys(), "k1")
  ca$remove("k1")
  expect_false(ca$exists("k1"))
})

test_that("cache_disk_qs2 evicts by count and resets", {
  d <- withr::local_tempdir()
  ca <- cache_disk_qs2(d, max_n = 3)
  for (i in 1:5) ca$set(paste0("p", i), i)
  expect_lte(ca$size(), 3)
  ca$reset()
  expect_equal(ca$size(), 0)
})

test_that("cache_disk_qs2 works as a cache_layered disk layer", {
  d <- withr::local_tempdir()
  lay <- cachem::cache_layered(cachem::cache_mem(), cache_disk_qs2(d))
  lay$set("x", 1:10)
  expect_equal(lay$get("x"), 1:10)
  expect_true(cachem::is.key_missing(lay$get("nope")))
})
