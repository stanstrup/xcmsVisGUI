suppressWarnings(suppressMessages(source("global.R")))
for (f in list.files("R", full.names = TRUE)) source(f)
mzml <- list.files(system.file("proteomics", package = "msdata"),
                   full.names = TRUE, pattern = "mzML$")[1]
h <- read_ms_header(mzml)
cat("charges in file:", h$summary$charges, "\n")
v  <- brewer_seq("viridis", invert = FALSE)(5)
vi <- brewer_seq("viridis", invert = TRUE)(5)
cat("viridis[1]:", v[1], " inverted[1]:", vi[1], " reversed-ok:", v[1] == vi[5], "\n")
cat("CHARGE TEST OK\n")
