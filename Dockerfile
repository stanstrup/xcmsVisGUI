# Run xcmsVisGUI as a Shiny server app.
#
#   docker build -t xcmsvisgui .
#   docker run --rm -p 3838:3838 -v /path/to/ms-data:/data xcmsvisgui
#
# Then open http://localhost:3838 and paste /data (your mounted MS files) into the
# Files box. Settings persist to a per-user config dir inside the container; mount
# a volume at /root/.config/R if you want them to survive container restarts.
#
# Based on the Bioconductor image so the RforMassSpectrometry stack
# (Spectra/MsExperiment/xcms/mzR) and its system libraries (e.g. netCDF for CDF)
# are available. Match the tag to the Bioconductor release the lockfile targets.
FROM bioconductor/bioconductor_docker:RELEASE_3_21

# This repo is renv-managed; disable the autoloader so dependencies install into
# the image's default library instead of the (image-absent) project renv library.
ENV RENV_CONFIG_AUTOLOADER_ENABLED=false

WORKDIR /srv/xcmsVisGUI
COPY . /srv/xcmsVisGUI

# Install the package and its hard dependencies (Imports/Depends/LinkingTo only;
# Suggests — testthat, msdata, faahKO, svglite — are not needed to run the app).
# pak resolves Bioconductor packages and installs system requirements via apt.
RUN Rscript -e "install.packages('pak', repos = 'https://cloud.r-project.org')" \
 && Rscript -e "pak::local_install('.', ask = FALSE, dependencies = NA)" \
 && Rscript -e "library(xcmsVisGUI)"  # fail the build early if it can't load

# Large uploads via the browser are allowed (run_app sets shiny.maxRequestSize);
# prefer mounting data and pasting the path for big/many files.
EXPOSE 3838
CMD ["Rscript", "-e", "xcmsVisGUI::run_app(host = '0.0.0.0', port = 3838, launch.browser = FALSE)"]
