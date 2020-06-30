FROM ubuntu:18.04

SHELL ["/bin/bash", "-c"]

ADD "https://www.sofa-framework.org/rand/" ForceNoCache

RUN apt-get update && apt-get upgrade -y

# Install tools
RUN apt-get install -y \
    apt-utils \
    git \
    net-tools \
    vim \
    wget \
    curl \
    zip \
    unzip

# Install compilers
RUN apt-get install -y \
    build-essential \
    software-properties-common \
    ninja-build \
    gcc-7 g++-7 \
    clang \
    ccache

# Install core deps
RUN apt-get install -y \
    libglew-dev \
    freeglut3-dev \
    zlib1g-dev \
    libeigen3-dev

# Install plugins deps
RUN apt-get install -y \
    python2.7-dev python-pip python-numpy python-scipy \
    libpng-dev libjpeg-dev libtiff-dev \
    libblas-dev \
    liblapack-dev \
    libsuitesparse-dev \
    libavcodec-dev libavformat-dev libavutil-dev libswscale-dev \
    libassimp-dev \
    libbullet-dev \
    liboce-ocaf-dev
ENV VM_HAS_ASSIMP="true"
 # BulletColisionDetection is broken
ENV VM_HAS_BULLET="disabled"
ENV VM_HAS_OPENCASCADE="true"

# Install CMake
ADD https://github.com/Kitware/CMake/releases/download/v3.12.0/cmake-3.12.0-Linux-x86_64.sh /tmp
RUN chmod a+x /tmp/cmake-3.12.0-Linux-x86_64.sh
RUN /tmp/cmake-3.12.0-Linux-x86_64.sh --skip-license --prefix=/usr/local

# Install Qt
RUN add-apt-repository -y ppa:beineri/opt-qt-5.12.6-bionic \
    && apt-get update \
    && apt-get install -y qt512-meta-full qt512charts-no-lgpl
ADD https://www.sofa-framework.org/wp-content/uploads/2020/06/QtInstallerFramework_3.0_Linux.zip /tmp
RUN unzip /tmp/QtInstallerFramework_3.0_Linux.zip -d /root && chmod -R a+x /root/Qt
ENV QTIFWDIR="/root/Qt/Tools/QtInstallerFramework/3.0"
ENV PATH="${QTIFWDIR}/bin:${PATH}"

# Install Boost
RUN add-apt-repository -y ppa:mhier/libboost-latest \
    && apt-get update \
    && apt-get install -y libboost1.67-dev

# Install CGAL
# Due to dependencies on Boost and Qt, we have to build CGAL
ADD https://github.com/CGAL/cgal/releases/download/releases/CGAL-4.14.3/CGAL-4.14.3.tar.xz /tmp
RUN apt-get install -y libgmp-dev libmpfr-dev
RUN tar -xJf /tmp/CGAL-4.14.3.tar.xz --directory /tmp \
    && cd /tmp/CGAL-4.14.3 \
    && mkdir build \
    && cd build \
    && cmake -DCMAKE_BUILD_TYPE=Release -DWITH_CGAL_Core=TRUE -DWITH_CGAL_ImageIO=TRUE -DWITH_CGAL_Qt5=TRUE .. \
    && make install
ENV VM_HAS_CGAL="true"
ENV VM_CGAL_PATH="/usr/local/lib/cmake/CGAL"

# Install CUDA
RUN apt-get install -y nvidia-cuda-toolkit
ENV VM_HAS_CUDA="true"
ENV VM_CUDA_HOST_COMPILER="/usr/bin/gcc-6"
ENV VM_CUDA_ARCH="sm_50"


# Init /builds directory
WORKDIR /builds

# Set env vars
ENV HOME="/root"

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

