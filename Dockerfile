FROM ubuntu:22.04 as base

# things to make apt happy
ARG DEBIAN_FRONTEND=noninteractive
ARG DEBIAN_PRIORITY=critical
ENV LANG=C.UTF-8
HEALTHCHECK NONE

# turn off apt cache cleaning
RUN rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

# install base packages
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get -y update && apt-get -y install --no-install-recommends \
        apt-utils \
        apt-transport-https \
        build-essential \
        ca-certificates \
        clinfo \
        lsb-release \
        curl \
        git \
        gnupg2 \
        gpg-agent \
        rsync \
        sudo \
        unzip \
        wget \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# add intel GPU repos
RUN curl -fsSL https://repositories.intel.com/graphics/intel-graphics.key \
    | gpg --dearmor --output /usr/share/keyrings/intel-graphics.gpg \
    && echo 'deb [signed-by=/usr/share/keyrings/intel-graphics.gpg] https://repositories.intel.com/graphics/ubuntu jammy flex' \
    | tee  /etc/apt/sources.list.d/intel.gpu.jammy.list

# install intel support/userspace libs
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get -y update && apt-get -y install --no-install-recommends \
        intel-opencl-icd \
        intel-level-zero-gpu \
        level-zero \
        level-zero-dev \
        intel-media-va-driver-non-free \
        libegl-mesa0 \
        libegl1-mesa \
        libegl1-mesa-dev \
        libgbm1 \
        libgl1-mesa-dev \
        libgl1-mesa-dri \
        libglapi-mesa \
        libgles2-mesa-dev \
        libglx-mesa0 \
        libigdgmm12 \
        libmfx1 \
        libmfxgen1 \
        libvpl2 \
        libxatracker2 \
        libarchive13 \
        libglib2.0-0 \
        libjpeg-dev \
        libjpeg-turbo8-dev \
        libjpeg8-dev \
        libjsoncpp25 \
        libncurses5 \
        libncursesw5 \
        libpng-dev \
        libjpeg-dev \
        librhash0 \
        libssl-dev \
        libuv1 \
        libpng-dev \
        mesa-va-drivers \
        mesa-vdpau-drivers \
        mesa-vulkan-drivers \
        nano \
        va-driver-all \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# C compiler and whatnot
RUN curl -fsSL https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB \
    | gpg --dearmor --output /usr/share/keyrings/oneapi-archive-keyring.gpg  \
    && echo "deb [signed-by=/usr/share/keyrings/oneapi-archive-keyring.gpg] https://apt.repos.intel.com/oneapi all main" \
    | tee /etc/apt/sources.list.d/oneAPI.list

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get -y update && apt-get -y install --no-install-recommends \
        intel-oneapi-runtime-dpcpp-cpp \
        intel-oneapi-runtime-mkl \
        intel-basekit-runtime \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# acquire python
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get -y update && apt-get -y install --no-install-recommends \
        python3 \
        python3-pip \
        python3-setuptools \
        python3-wheel \
        python3-dev \
        python3-venv \
        python3-virtualenv \
        python-is-python3 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ARG PIP_PREFER_BINARY=1
ARG PY_VERSION=3.10

# do some linking of python things
RUN ln -sf /usr/bin/python${PY_VERSION} /usr/local/bin/python \
    && ln -sf /usr/bin/python${PY_VERSION} /usr/local/bin/python3 \
    && ln -sf /usr/bin/python${PY_VERSION} /usr/bin/python \
    && ln -sf /usr/bin/python${PY_VERSION} /usr/bin/python3

# python base deps
RUN --mount=type=cache,target=/root/.cache/pip \
    python3 -m pip install --upgrade pip setuptools wheel \
    && python3 -m pip install \
        pillow \
        mkl \
        numpy==1.22.3 \
        ninja \
        cmake

ARG TORCH_VERSION=1.13.0a0+gitb1dde16
ARG TORCHVISION_VERSION=0.14.1a0+0504df5
ARG IPEX_VERSION=1.13.10+xpu
ARG IPEX_WHEEL_URL=https://developer.intel.com/ipex-whl-stable-xpu

# intel extension for pytorch
RUN --mount=type=cache,target=/root/.cache/pip \
    python3 -m pip install -f ${IPEX_WHEEL_URL} torch==${TORCH_VERSION} \
    && python3 -m pip install -f ${IPEX_WHEEL_URL} intel-extension-for-pytorch==${IPEX_VERSION} \
    && python3 -m pip install -f ${IPEX_WHEEL_URL} torchvision==${TORCHVISION_VERSION} \
    && rm -rf /tmp/wheels

WORKDIR /workspace
VOLUME [ "/workspace" ]

FROM base AS pytorch

# create a non-root user
ARG USERNAME=ipex
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# Create the user
RUN groupadd --gid ${USER_GID} ${USERNAME} \
    && groupadd --gid 107 render \
    && useradd --uid ${USER_UID} --gid ${USER_GID} -m ${USERNAME} \
    && usermod -aG adm,dialout,cdrom,floppy,sudo,audio,dip,video,plugdev,render,staff ${USERNAME} \
    && apt-get update \
    && apt-get install -y sudo \
    && echo "${USERNAME} ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME}

USER ${USERNAME}
WORKDIR /home/${USERNAME}

