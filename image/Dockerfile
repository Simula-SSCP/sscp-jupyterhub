FROM ghcr.io/prefix-dev/pixi:0.46.0 AS build

# copy source code, pixi.toml and pixi.lock to the container
RUN mkdir /opt/pixi
COPY pixi.* /opt/pixi/
WORKDIR /opt/pixi

ENV NB_UID=1001
RUN chown -R $NB_UID /opt/pixi
USER $NB_UID

ENV XDG_CACHE_HOME=/tmp/cache

RUN --mount=type=cache,uid=$NB_UID,target=$XDG_CACHE_HOME pixi install
# install some extra things with requirements.txt
COPY requirements.txt /tmp/requirements.txt
RUN  --mount=type=cache,uid=$NB_UID,target=$XDG_CACHE_HOME pixi run pip install -r /tmp/requirements.txt

COPY clean-conda.bash /tmp/clean-conda.bash
RUN pixi run bash /tmp/clean-conda.bash

USER root
# Create the shell-hook bash script to activate the environment
RUN pixi shell-hook > /shell-hook.sh \
 && echo 'exec "$@"' >> /shell-hook.sh

FROM ubuntu:24.04

USER root
ENV DEBIAN_FRONTEND=noninteractive
COPY apt.txt /tmp/apt.txt
RUN rm -vf /etc/apt/apt.conf.d/docker-clean
RUN --mount=type=cache,target=/var/cache/apt apt-get update && apt-get -yq dist-upgrade \
 && apt-get install -yq --no-install-recommends \
    $(cat /tmp/apt.txt | grep -v '^#' | sort) \
 && rm -rf /var/lib/apt/lists/*

RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen \
 && locale-gen

ENV NB_UID=1001 \
    NB_USER=user \
    CONDA_DIR=/opt/pixi/.pixi/envs/default \
    SHELL=/bin/bash \
    LANG=en_US.UTF-8

RUN useradd -m -s /bin/bash -N -u $NB_UID $NB_USER

COPY --from=build /opt/pixi /opt/pixi
COPY --from=build /shell-hook.sh /shell-hook.sh
# RUN ls -la /opt/pixi/ && exit 1
# setup conda env
ENV PATH=$CONDA_DIR/bin:$PATH
COPY condarc $CONDA_DIR/.condarc

USER $NB_UID

# enable nbdime globally, configure carputils
USER root
RUN cusettings $CONDA_DIR/etc/carputils-settings.yml
RUN nbdime config-git --enable --system
USER $NB_UID

# fenics 3d plotting doesn't like mpl 3
# RUN pip install --no-cache 'matplotlib<3'

COPY pull_server_ext.py ${CONDA_DIR}/lib/python3.12/site-packages/pull_server_ext.py
COPY pull-button.js /tmp/
RUN jupyter server extension enable --sys-prefix pull_server_ext

# disable "Jupyter news" pop-up
RUN jupyter labextension disable  "@jupyterlab/apputils-extension:announcements"

WORKDIR /home/$NB_USER
COPY jupyter_server_config.py /etc/jupyter/jupyter_server_config.py

USER root
# setup entrypoint
RUN ln -s $CONDA_DIR/etc/profile.d/conda.sh /etc/profile.d/conda.sh
USER $NB_UID
ENTRYPOINT ["/bin/bash", "/shell-hook.sh"]
CMD ["jupyter", "lab", "--ip=0.0.0.0"]

# late, small changes, to avoid large image rebuilds
# move to pixi.toml on next large update

# jupyter-server-mathjax 0.2.2 unconditionally sets the wrong mathjax_url
# RUN pip install --no-cache jupyter-server-mathjax==0.2.0
