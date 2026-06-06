.onLoad <- function(libname, pkgname) {
  # THE performance fix: MsBackendMzR header reads are ~100x slower under the
  # default BiocParallel backend (SnowParam on Windows), which spawns a socket
  # cluster per call. Register SerialParam on load so every read path — the app
  # AND the test suite — is sub-second. See CLAUDE.md "THE performance story".
  # Deliberate global side effect: it is the core reason this package exists.
  BiocParallel::register(BiocParallel::SerialParam())
}
