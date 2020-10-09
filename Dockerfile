FROM nfcore/base:1.9
LABEL authors="Steffen Lemke" \
      description="Docker image containing all software requirements for the steffenlem/sradownloader pipeline"

# Install the conda environment
COPY environment.yml /
RUN conda env create -f /environment.yml && conda clean -a

# Add conda installation dir to PATH (instead of doing 'conda activate')
ENV PATH /opt/conda/envs/nf-core-sradownloader-1.0.0/bin:$PATH

# Dump the details of the installed packages to a file for posterity
RUN conda env export --name nf-core-sradownloader-1.0.0 > nf-core-sradownloader-1.0.0.yml
RUN mkdir -p /root/.ncbi
RUN printf '/LIBS/GUID = "%s"\n' `uuid` > /root/.ncbi/user-settings.mkfg
