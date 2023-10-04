FROM ubuntu:22.04

SHELL ["/bin/bash", "-c"]

ADD "https://www.sofa-framework.org/rand/" ForceNoCache

RUN useradd --no-log-init ci --uid 1000 --home /home/ci --create-home --shell /bin/bash
ENV HOME="/home/ci"

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
    net-tools \
    vim \
    wget \
    curl \
    ca-certificates \
    zip \
    unzip \
    patchelf

# Install build tools
RUN apt-get install -y \
    build-essential \
    ninja-build=1.10.\* \
    gcc=4:11.\* \
    g++=4:11.\* \
    clang=1:14.0-\* \
    ccache=4.5.\*

# Install core deps
RUN apt-get install -y \
    libboost-all-dev=1.74.\* \
    libglew-dev=2.2.\* \
    freeglut3-dev=2.8.\* \
    zlib1g-dev=1:1.2.\* \
    libeigen3-dev=3.4.\*

# Install plugins deps
RUN apt-get install -y \
    python2.7-dev \
    python3.10-dev python3.10-distutils \
    libpng-dev libjpeg-dev libtiff-dev \
    libblas-dev \
    liblapack-dev \
    libsuitesparse-dev \
    libavcodec-dev libavformat-dev libavutil-dev libswscale-dev \
    libassimp-dev \
    liboce-ocaf-dev \
    libzmq3-dev liboscpack-dev \
    libxrandr-dev libxinerama-dev libxcursor-dev libxi-dev

# Install pip, numpy, scipy, pybind11
ARG PYBIND11_VERSION=2.9.1
RUN curl -L https://bootstrap.pypa.io/pip/2.7/get-pip.py --output /tmp/get-pip2.py \
    && python2.7 /tmp/get-pip2.py \
    && python2.7 -m pip install --upgrade "pip == 20.3.4" \
    && python2.7 -m pip install "numpy == 1.16.6" "scipy == 1.2.3" "matplotlib == 2.2.5"
RUN curl -L https://bootstrap.pypa.io/pip/get-pip.py --output /tmp/get-pip3.py \
    && python3.10 /tmp/get-pip3.py \
    && python3.10 -m pip install --upgrade pip \
    && python3.10 -m pip install numpy scipy matplotlib pybind11==$PYBIND11_VERSION
ENV VM_HAS_ASSIMP="true"
ENV VM_HAS_OPENCASCADE="true"

###################################

# Install CMake
ARG CMAKE_VERSION=3.22.1
ADD https://github.com/Kitware/CMake/releases/download/v$CMAKE_VERSION/cmake-$CMAKE_VERSION-Linux-x86_64.sh /tmp/cmake.sh
RUN chmod a+x /tmp/cmake.sh
RUN /tmp/cmake.sh --skip-license --prefix=/usr/local

# Install Qt
ARG QT_VERSION=5.12.12
ARG QT_INSTALLDIR="/opt/Qt"
RUN python3.10 -m pip install aqtinstall \
    && python3.10 -m aqt install-qt --outputdir $QT_INSTALLDIR linux desktop $QT_VERSION gcc_64 -m qtcharts qtwebengine
RUN apt-get install -y libxkbcommon-x11-0 libwayland-cursor0 libxcb-* \
    && python3.10 -m aqt install-tool --outputdir $QT_INSTALLDIR linux desktop tools_ifw \
    || true
ENV QT_INSTALLDIR="$QT_INSTALLDIR"
ENV QTDIR="$QT_INSTALLDIR/$QT_VERSION/gcc_64"
ENV LD_LIBRARY_PATH="$QTDIR/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
ENV PATH="$QTDIR/bin${PATH:+:${PATH}}"

# Install CGAL
# Due to dependencies on Boost and Qt, we have to build CGAL
ARG CGAL_VERSION=5.4.5
ADD https://github.com/CGAL/cgal/releases/download/v$CGAL_VERSION/CGAL-$CGAL_VERSION.tar.xz /tmp/CGAL.tar.xz
RUN apt-get install -y libgmp-dev libmpfr-dev
RUN tar -xJf /tmp/CGAL.tar.xz --directory /tmp \
    && cd /tmp/CGAL-$CGAL_VERSION \
    && mkdir build \
    && cd build \
    && cmake -DCMAKE_BUILD_TYPE=Release -DWITH_CGAL_Core=TRUE -DWITH_CGAL_ImageIO=TRUE -DWITH_CGAL_Qt5=TRUE .. \
    && make --silent install
ENV VM_HAS_CGAL="true"
ENV VM_CGAL_PATH="/usr/local/lib/cmake/CGAL"

# Install CUDA
RUN export DEBIAN_FRONTEND=noninteractive
RUN wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-ubuntu2204.pin
RUN mv cuda-ubuntu2204.pin /etc/apt/preferences.d/cuda-repository-pin-600
RUN wget https://developer.download.nvidia.com/compute/cuda/11.8.0/local_installers/cuda-repo-ubuntu2204-11-8-local_11.8.0-520.61.05-1_amd64.deb
RUN dpkg -i cuda-repo-ubuntu2204-11-8-local_11.8.0-520.61.05-1_amd64.deb
RUN cp /var/cuda-repo-ubuntu2204-11-8-local/cuda-*-keyring.gpg /usr/share/keyrings/
RUN apt-get update
RUN apt-get -y install cuda
ENV VM_HAS_CUDA="true"

# Install NodeEditor (needed by SofaQtQuick)
ARG NODEEDITOR_VERSION=2.2.4
RUN git clone -b $NODEEDITOR_VERSION --depth 1 https://github.com/paceholder/nodeeditor.git /tmp/nodeeditor/src \
    && mkdir /tmp/nodeeditor/build && cd /tmp/nodeeditor/build \
    && cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF ../src \
    && make --silent install

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
