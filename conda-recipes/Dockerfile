FROM quay.io/condaforge/miniforge3:25.3.0-1
# USER root
RUN apt-get -y update && apt-get -y install rsync patch git make
RUN mamba install -yq anaconda-client conda-build rattler-build
RUN conda config --system --append channels minrk
RUN mamba install -y conda-forge-pinning \
 && cp /opt/conda/conda_build_config.yaml $HOME/
# opencarp relies of file-transport submodules
RUN git config --global --add protocol.file.allow always

COPY build-conda /usr/local/bin/build-conda
