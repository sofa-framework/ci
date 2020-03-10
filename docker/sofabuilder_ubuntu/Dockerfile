FROM ubuntu:18.04

SHELL ["/bin/bash", "-c"]

RUN apt-get -qq update && apt-get -qq upgrade -y

# Install tools
RUN apt-get -qq install -y \
    apt-utils \
    git \
    net-tools \
    vim \
    wget \
    curl

# Install compilers
RUN apt-get -qq install -y \
    build-essential \
    software-properties-common \
    ninja-build \
    gcc-7 g++-7 \
    clang \
    ccache

# Install plugins deps
RUN apt-get -qq install -y \
    python2.7-dev python-pip python-numpy python-scipy \
    libpng-dev libjpeg-dev libtiff-dev zlib1g-dev libglew-dev libblas-dev liblapack-dev \
    libxml2-dev \
    freeglut3-dev \
    libsuitesparse-dev \
    libassimp-dev \
    libbullet-dev \
    nvidia-cuda-toolkit \
    liboce-ocaf-dev \
    libavcodec-dev libswscale-dev libavutil-dev libavformat-dev 

# Install CMake
ADD https://github.com/Kitware/CMake/releases/download/v3.12.0/cmake-3.12.0-Linux-x86_64.sh /tmp
RUN chmod a+x /tmp/cmake-3.12.0-Linux-x86_64.sh
RUN /tmp/cmake-3.12.0-Linux-x86_64.sh --skip-license --prefix=/usr/local

# Install Qt
RUN add-apt-repository -y ppa:beineri/opt-qt-5.12.6-bionic \
    && apt-get -qq update \
    && apt-get -qq install -y qt512-meta-full qt512charts-no-lgpl

# Install Boost
RUN add-apt-repository -y ppa:mhier/libboost-latest \
    && apt-get -qq update \
    && apt-get -qq install -y libboost1.67-dev

# Install CGAL
# Due to dependencies on Boost and Qt, we have to build CGAL
ADD https://github.com/CGAL/cgal/releases/download/releases/CGAL-4.14.3/CGAL-4.14.3.tar.xz /tmp
RUN apt-get -qq install -y libgmp-dev libmpfr-dev
RUN tar -xJf /tmp/CGAL-4.14.3.tar.xz --directory /tmp \
    && cd /tmp/CGAL-4.14.3 \
    && mkdir build \
    && cd build \
    && cmake -DCMAKE_BUILD_TYPE=Release -DWITH_CGAL_Core=TRUE -DWITH_CGAL_ImageIO=TRUE -DWITH_CGAL_Qt5=TRUE .. \
    && make install

# Init /builds directory
WORKDIR /builds

# Set env vars
ENV HOME="/root"
ENV VM_CUDA_NVCC_FLAGS="-ccbin gcc-6"
ENV VM_CUDA_ARCH="sm_50"
ENV QTDIR="/opt/qt512"
ENV PATH="$QTDIR/bin:$PATH"
ENV LD_LIBRARY_PATH="$QTDIR/lib/x86_64-linux-gnu:$QTDIR/lib:$LD_LIBRARY_PATH"

# Cleanup
RUN apt-get -qq clean -y \
    && apt-get -qq autoremove -y \
    && rm -rf /tmp/*

# Define default command.
CMD ["/bin/bash"]

