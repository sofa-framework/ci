FROM centos:7

SHELL ["/bin/bash", "-c"]

# Install yum repositories
RUN yum install -y -q deltarpm 
RUN yum install -y -q epel-release
RUN yum install -y -q centos-release-scl
RUN yum install -y -q centos-release-scl-rh
RUN yum install -y -q http://repo.okay.com.mx/centos/7/x86_64/release/okay-release-1-1.noarch.rpm
RUN yum update -y && yum upgrade -y && yum clean all

# Install tools
RUN yum install -y -q \
    git \
    wget \
    curl \
    vim \
    update-alternatives

# Install build tools
RUN yum install -y -q \
	cmake3 \
    ninja-build \
    devtoolset-7 \
    llvm-toolset-7 \
    ccache
RUN ln -sf /usr/bin/ninja-build /usr/bin/ninja || true

# Install core deps
RUN yum install -y -q \
    glew-devel \
    freeglut-devel \
    zlib-devel \
    eigen3-devel

# Install plugin deps
RUN yum install -y -q \
    python27-python-devel python27-python-pip \
    rh-python38-python-devel rh-python38-python-pip \
    libpng-devel libjpeg-devel libtiff-devel \
    blas-devel \
    lapack-devel \
    suitesparse-devel \
    ffmpeg-devel \
    assimp-devel \
    bullet-extras-devel \
    OCE-devel
RUN python2.7 -m pip install numpy
RUN python3.8 -m pip install numpy
ENV VM_HAS_ASSIMP="true"
 # BulletColisionDetection is broken
ENV VM_HAS_BULLET="disabled"
ENV VM_HAS_OPENCASCADE="true"

# Install Qt
ARG QT_MAJOR=5
ARG QT_MINOR=12
ARG QT_PATCH=6
RUN mkdir -p /root/.local/share/Qt
ADD qtaccount.ini /root/.local/share/Qt/qtaccount.ini
ADD qtinstaller_controlscript_template_linux.qs /tmp/qtinstaller_controlscript_template_linux.qs
RUN cat /tmp/qtinstaller_controlscript_template_linux.qs | sed "s/_QTVERSION_/$QT_MAJOR$QT_MINOR$QT_PATCH/g" > /tmp/qtinstaller_controlscript.qs
ADD http://download.qt.io/official_releases/online_installers/qt-unified-linux-x64-online.run /tmp/qt-unified-linux-x64-online.run
RUN yum install -y -q libxkbcommon-x11 libwayland-cursor
RUN chmod a+x /tmp/qt-unified-linux-x64-online.run \
    && /tmp/qt-unified-linux-x64-online.run --script /tmp/qtinstaller_controlscript.qs --platform minimal --verbose
ENV QTDIR="/opt/Qt/$QT_MAJOR.$QT_MINOR.$QT_PATCH/gcc_64"
ENV PATH="$QTDIR/bin${PATH:+:${PATH}}"
ENV LD_LIBRARY_PATH="$QTDIR/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

# Install Boost
RUN yum install -y -q boost169-devel
RUN ln -s -f "boost169/boost" "/usr/include/boost" || true
RUN ln -s -f "boost169" "/usr/lib64/boost" || true
ENV BOOST_INCLUDEDIR="/usr/include"
ENV BOOST_LIBRARYDIR="/usr/lib64/boost"
ENV LD_LIBRARY_PATH="${BOOST_LIBRARYDIR}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

# Set cmake3 the default CMake
RUN update-alternatives --install /usr/local/bin/cmake cmake /usr/bin/cmake3 20 \
    --slave /usr/local/bin/ctest ctest /usr/bin/ctest3 \
    --slave /usr/local/bin/cpack cpack /usr/bin/cpack3 \
    --slave /usr/local/bin/ccmake ccmake /usr/bin/ccmake3 \
    --family cmake

# Install CGAL
# Due to dependencies on Boost and Qt, we have to build CGAL
ADD https://github.com/CGAL/cgal/releases/download/releases/CGAL-4.14.3/CGAL-4.14.3.tar.xz /tmp
RUN yum install -y -q gmp-devel mpfr-devel
RUN tar -xJf /tmp/CGAL-4.14.3.tar.xz --directory /tmp \
    && cd /tmp/CGAL-4.14.3 \
    && mkdir build \
    && cd build \
    && source /opt/rh/devtoolset-7/enable || true \
	&& source /opt/rh/llvm-toolset-7/enable || true \
    && cmake -DCMAKE_BUILD_TYPE=Release -DWITH_CGAL_Core=TRUE -DWITH_CGAL_ImageIO=TRUE -DWITH_CGAL_Qt5=TRUE .. \
    && make install
ENV VM_HAS_CGAL="true"
ENV VM_CGAL_PATH="/usr/local/lib64/cmake/CGAL"

# Install CUDA
RUN yum-config-manager --add-repo \
    http://developer.download.nvidia.com/compute/cuda/repos/rhel7/x86_64/cuda-rhel7.repo \
    && yum clean all
RUN yum install -y -q cuda-toolkit-10-2
RUN yum install -y -q nvidia-driver-cuda
RUN yum install -y -q nvidia-kmod
ENV PATH="/usr/local/cuda-10.2/bin:/usr/local/cuda-10.2/NsightCompute-2019.1${PATH:+:${PATH}}"
ENV LD_LIBRARY_PATH="/usr/local/cuda-10.2/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
ENV VM_HAS_CUDA="true"
ENV VM_CUDA_HOST_COMPILER="/usr/bin/gcc"
ENV VM_CUDA_ARCH="sm_50"


# Init /builds directory
WORKDIR /builds

# Set env vars
ENV HOME="/root"

# Cleanup
RUN yum clean all \
    && rm -rf /tmp/*

# In-process env settings
COPY docker-entrypoint.sh /
RUN chmod a+x /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]

# Default command to run
CMD ["/bin/bash"]
