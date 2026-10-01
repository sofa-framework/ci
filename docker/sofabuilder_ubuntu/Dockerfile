FROM ubuntu:24.04

SHELL ["/bin/bash", "-c"]

ADD "https://www.sofa-framework.org/rand/" ForceNoCache

# Install APT tools and repos
RUN apt-get update && apt-get upgrade -y
RUN apt-get install -y \
    apt-utils \
    software-properties-common
RUN add-apt-repository ppa:git-core/ppa \
    && add-apt-repository ppa:deadsnakes/ppa
RUN apt-get update && apt-get upgrade -y

# Install system tools
RUN apt-get install -y \
    git \
    gh \
    net-tools \
    vim \
    wget \
    curl \
    ca-certificates \
    zip \
    unzip \
    cmake \
    patchelf

# Install build tools
RUN apt-get install -y \
    build-essential \
    ninja-build=1.11.\* \
    gcc=4:13.\* \
    g++=4:13.\* \
    clang=1:18.0-\* \
    ccache

# Install core deps
RUN apt-get install -y \
    libboost-all-dev=1.83.\* \
    libglew-dev=2.2.\* \
    freeglut3-dev=3.4.\* \
    zlib1g-dev=1:1.3.\* \
    libeigen3-dev=3.4.\*

# Install plugins deps
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get install -y \
    python3.12-dev \
    python3-pip \
    python3.13 \
    python3.13-dev \
    python3.14 \
    python3.14-dev \
    libpng-dev libjpeg-dev libtiff-dev \
    libblas-dev \
    liblapack-dev \
    libsuitesparse-dev \
    libavcodec-dev libavformat-dev libavutil-dev libswscale-dev \
    libassimp-dev \
    libzmq3-dev liboscpack-dev \
    libxrandr-dev libxinerama-dev libxcursor-dev libxi-dev \
    libtinyxml2-dev \
    xorg-dev\
    libgtk-3-dev



ENV VM_BUILDS_IMGUI="true"
# Install pip, numpy, scipy, pybind11
ARG PYBIND11_VERSION=3.0.1
RUN python3.12 -m pip install numpy scipy matplotlib pybind11==$PYBIND11_VERSION mypy pybind11-stubgen rpyc prettytable ct3 --break-system-packages
RUN python3.13 -m pip install numpy scipy matplotlib pybind11==$PYBIND11_VERSION mypy pybind11-stubgen rpyc prettytable ct3 --break-system-packages
RUN python3.14 -m pip install numpy scipy matplotlib pybind11==$PYBIND11_VERSION mypy pybind11-stubgen rpyc prettytable ct3 --break-system-packages
ENV VM_HAS_ASSIMP="true"
ENV VM_HAS_OPENCASCADE="true"


###################################
#
# Install CUDA
ENV DEBIAN_FRONTEND noninteractive
RUN wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
RUN dpkg -i cuda-keyring_1.1-1_all.deb
RUN apt-get update
RUN apt-get -y install cuda-toolkit-12-9
ENV VM_HAS_CUDA="true"
ENV PATH=$PATH:/usr/local/cuda/bin


###################################

# Disable core dumps
RUN printf '\n# Disable core dumps\n* soft core 0\n* hard core 0\n' >> /etc/security/limits.conf

# Init /builds directory
WORKDIR /builds

# Set env vars
ENV PYTHONIOENCODING="UTF-8"
ENV PYTHONUSERBASE="/tmp/pythonuserbase"
RUN mkdir -p "$PYTHONUSERBASE" && chmod -R 777 "$PYTHONUSERBASE"
ENV VM_PYTHON_EXECUTABLE="/usr/bin/python2.7"
ENV VM_PYTHON3_EXECUTABLE="/usr/bin/python3.10"
ENV VM_PYBIND11_CONFIG_EXECUTABLE="/usr/bin/python3.10 -m pybind11"
RUN git config --system user.name 'SOFA Bot' || git config --global user.name 'SOFA Bot'
RUN git config --system user.email '<>' || git config --global user.email '<>'

# TMP: fix Boost+CMake issue with a symlink
RUN ln -s /usr/include /include || true

# Cleanup
RUN apt-get clean -y \
    && apt-get autoremove -y \
    && rm -rf /tmp/*

# In-process env settings
COPY docker-entrypoint.sh /
RUN chmod a+x /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]

# Define default command.
CMD ["/bin/bash"]
