# Lightweight asserting test runner (no testthat dependency — testthat is not in
# the renv library and this app is sourced, not installed). Sources the app, runs
# every tests/test-*.R, prints a summary, and exits non-zero if anything failed.
#
#   Rscript tests/run-tests.R
#
# Real-data tests are gated on the Suggests packages (msdata/faahKO) being
# installed; they SKIP (not fail) when absent.

suppressWarnings(suppressMessages(source("global.R")))
for (f in list.files("R", full.names = TRUE)) source(f)

.T <- new.env()
.T$ok <- 0L; .T$fail <- 0L; .T$skip <- 0L

expect <- function(cond, msg) {
  if (isTRUE(cond)) .T$ok <- .T$ok + 1L
  else { .T$fail <- .T$fail + 1L; cat("  FAIL:", msg, "\n") }
}
expect_equal <- function(a, b, msg, tol = 1e-6) {
  ok <- length(a) == length(b) && all(is.finite(a) == is.finite(b)) &&
        all(abs(a[is.finite(a)] - b[is.finite(b)]) <= tol)
  expect(isTRUE(ok), sprintf("%s [%s vs %s]", msg,
                             paste(a, collapse = ","), paste(b, collapse = ",")))
}
expect_identical <- function(a, b, msg) {
  expect(identical(a, b), sprintf("%s [%s vs %s]", msg,
                                  paste(a, collapse = ","), paste(b, collapse = ",")))
}
skip <- function(msg) { .T$skip <- .T$skip + 1L; cat("  SKIP:", msg, "\n") }

for (tf in sort(list.files("tests", pattern = "^test-.*\\.R$", full.names = TRUE))) {
  cat("== ", basename(tf), " ==\n", sep = "")
  source(tf)
}

try(mirai::daemons(0), silent = TRUE)
cat(sprintf("\n%d passed, %d failed, %d skipped\n", .T$ok, .T$fail, .T$skip))
if (.T$fail > 0) quit(status = 1)
