FROM fedora:34

SHELL ["/bin/bash", "-c"]

ADD "https://www.sofa-framework.org/rand/" ForceNoCache

RUN useradd --no-log-init ci --uid 1000 --home /home/ci --create-home --shell /bin/bash
ENV HOME="/home/ci"

# Install yum repositories
# RUN yum install -y -q deltarpm
# RUN yum install -y -q epel-release
# RUN yum install -y -q centos-release-scl
# RUN yum install -y -q centos-release-scl-rh
# RUN yum install -y -q http://repo.okay.com.mx/centos/7/x86_64/release/okay-release-1-5.el7.noarch.rpm
# RUN yum install -y -q https://packages.endpoint.com/rhel/7/os/x86_64/endpoint-repo-1.9-1.x86_64.rpm
RUN yum install -y -q http://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-34.noarch.rpm
RUN yum update -y && yum upgrade -y && yum clean all

# Install system tools
RUN yum install -y -q \
    dnf-utils \
    git \
    wget \
    curl \
    ca-certificates \
    vim

# Install build tools
RUN yum install -y -q \
    ninja-build \
    clang \
    ccache \
    libXdamage

# Install core deps
RUN yum install -y -q \
    glew-devel \
    freeglut-devel \
    zlib-devel \
    eigen3-devel

# Install plugin deps
RUN yum install -y -q \
    python2.7 \
    python3.8 \
    libpng-devel libjpeg-turbo-devel libtiff-devel \
    blas-devel \
    lapack-devel \
    suitesparse-devel \
    ffmpeg-devel \
    assimp-devel \
    opencascade-devel \
    libXrandr-devel
RUN curl -L https://bootstrap.pypa.io/pip/2.7/get-pip.py --output /tmp/get-pip2.py \
    && python2.7 /tmp/get-pip2.py \
    && python2.7 -m pip install --upgrade "pip == 20.3.4" \
    && python2.7 -m pip install "numpy == 1.16.6" "scipy == 1.2.3" "matplotlib == 2.2.5"
RUN curl -L https://bootstrap.pypa.io/pip/get-pip.py --output /tmp/get-pip3.py \
    && python3.8 /tmp/get-pip3.py \
    && python3.8 -m pip install --upgrade pip \
    && python3.8 -m pip install numpy scipy pygame
ENV PYTHONPATH=""
ENV VM_HAS_ASSIMP="true"
ENV VM_HAS_OPENCASCADE="true"

###################################

# Install CMake
ARG CMAKE_MAJOR=3
ARG CMAKE_MINOR=12
ARG CMAKE_PATCH=0
ADD https://github.com/Kitware/CMake/releases/download/v$CMAKE_MAJOR.$CMAKE_MINOR.$CMAKE_PATCH/cmake-$CMAKE_MAJOR.$CMAKE_MINOR.$CMAKE_PATCH-Linux-x86_64.sh /tmp/cmake.sh
RUN chmod a+x /tmp/cmake.sh
RUN /tmp/cmake.sh --skip-license --prefix=/usr/local

# Set cmake3 the default CMake
# RUN update-alternatives --install /usr/local/bin/cmake cmake /usr/bin/cmake 20 \
#     --slave /usr/local/bin/ctest ctest /usr/bin/ctest \
#     --slave /usr/local/bin/cpack cpack /usr/bin/cpack \
#     --slave /usr/local/bin/ccmake ccmake /usr/bin/ccmake \
#     --family cmake

# Install Qt
ARG QT_MAJOR=5
ARG QT_MINOR=12
ARG QT_PATCH=6
ARG QT_INSTALLDIR="/opt/Qt"
RUN python3.8 -m pip install aqtinstall \
    && python3.8 -m aqt install-qt   --outputdir $QT_INSTALLDIR linux desktop $QT_MAJOR.$QT_MINOR.$QT_PATCH gcc_64 -m qtcharts qtwebengine \
    && python3.8 -m aqt install-tool --outputdir $QT_INSTALLDIR linux desktop tools_ifw qt.tools.ifw.43
ENV QTDIR="$QT_INSTALLDIR/$QT_MAJOR.$QT_MINOR.$QT_PATCH/gcc_64"
ENV QTIFWDIR="$QT_INSTALLDIR/Tools/QtInstallerFramework/4.3"
ENV LD_LIBRARY_PATH="$QTDIR/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
ENV PATH="$QTDIR/bin:$QTIFWDIR/bin${PATH:+:${PATH}}"

# Install Boost
# ARG BOOST_MAJOR=1
# ARG BOOST_MINOR=69
RUN yum install -y -q boost-devel
# RUN ln -s -f "boost${BOOST_MAJOR}${BOOST_MINOR}/boost" "/usr/include/boost" || true
# RUN ln -s -f "boost${BOOST_MAJOR}${BOOST_MINOR}" "/usr/lib64/boost" || true
ENV BOOST_INCLUDEDIR="/usr/include"
ENV BOOST_LIBRARYDIR="/usr/lib64/boost"
ENV LD_LIBRARY_PATH="${BOOST_LIBRARYDIR}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

# Install CGAL
# Due to dependencies on Boost and Qt, we have to build CGAL
ARG CGAL_MAJOR=4
ARG CGAL_MINOR=14
ARG CGAL_PATCH=3
ADD https://github.com/CGAL/cgal/releases/download/releases/CGAL-$CGAL_MAJOR.$CGAL_MINOR.$CGAL_PATCH/CGAL-$CGAL_MAJOR.$CGAL_MINOR.$CGAL_PATCH.tar.xz /tmp/CGAL.tar.xz
RUN yum install -y -q gmp-devel mpfr-devel
RUN tar -xJf /tmp/CGAL.tar.xz --directory /tmp \
    && cd /tmp/CGAL-$CGAL_MAJOR.$CGAL_MINOR.$CGAL_PATCH \
    && mkdir build \
    && cd build \
    && source /opt/rh/devtoolset-7/enable || true \
    && source /opt/rh/llvm-toolset-7/enable || true \
    && cmake -DCMAKE_BUILD_TYPE=Release -DWITH_CGAL_Core=TRUE -DWITH_CGAL_ImageIO=TRUE -DWITH_CGAL_Qt5=TRUE .. \
    && make --silent install
ENV VM_HAS_CGAL="true"
ENV VM_CGAL_PATH="/usr/local/lib64/cmake/CGAL"

# Install CUDA
# ARG CUDA_MAJOR=11
# ARG CUDA_MINOR=3
# RUN yum-config-manager --add-repo http://developer.download.nvidia.com/compute/cuda/repos/fedora33/x86_64/cuda-fedora33.repo \
#     && yum clean expire-cache
# RUN yum install -y -q cuda-toolkit-$CUDA_MAJOR-$CUDA_MINOR
# ENV PATH="/usr/local/cuda-$CUDA_MAJOR.$CUDA_MINOR/bin:/usr/local/cuda-$CUDA_MAJOR.$CUDA_MINOR/NsightCompute-2019.1${PATH:+:${PATH}}"
# ENV LD_LIBRARY_PATH="/usr/local/cuda-$CUDA_MAJOR.$CUDA_MINOR/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
# ENV VM_CUDA_HOST_COMPILER="/usr/bin/gcc"
# ENV VM_CUDA_ARCH="sm_50"
ENV VM_HAS_CUDA="false"

# Install pybind11 (needed by SofaPython3)
ARG PYBIND_MAJOR=2
ARG PYBIND_MINOR=4
ARG PYBIND_PATCH=2
RUN git clone -b v$PYBIND_MAJOR.$PYBIND_MINOR.$PYBIND_PATCH --depth 1 https://github.com/pybind/pybind11.git /tmp/pybind11/src \
&& mkdir /tmp/pybind11/build && cd /tmp/pybind11/build \
&& cmake -DCMAKE_BUILD_TYPE=Release -DPYTHON_EXECUTABLE="$(which python3.8)" -DPYBIND11_TEST=OFF ../src \
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
ENV VM_PYTHON3_EXECUTABLE="/usr/bin/python3.8"
RUN git config --system user.name 'SOFA Bot' || git config --global user.name 'SOFA Bot'
RUN git config --system user.email '<>' || git config --global user.email '<>'

# Cleanup
RUN yum clean all \
    && rm -rf /tmp/*

# In-process env settings
COPY docker-entrypoint.sh /
RUN chmod a+x /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]

# Default command to run
CMD ["/bin/bash"]
