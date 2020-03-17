FROM centos:7

SHELL ["/bin/bash", "-c"]

# Run setup
ADD setup-centos.sh /tmp
RUN chmod a+x /tmp/setup-centos.sh && /tmp/setup-centos.sh

# Init /builds directory
WORKDIR /builds

# Set env vars
ENV HOME="/root"
ENV \
	BOOST_INCLUDEDIR="/usr/include/boost169" \
	BOOST_LIBRARYDIR="/usr/lib64/boost169" \
	VM_HAS_ASSIMP="true" \
	VM_HAS_BULLET="true" \
	VM_HAS_OPENCASCADE="true" \
	VM_HAS_CGAL="true" \
	VM_HAS_CUDA="true" \
	VM_CUDA_HOST_COMPILER="/root/bin/gcc-6" \
	VM_CUDA_ARCH="sm_50"
ENV \
	PATH="/root/bin:/usr/local/cuda-10.2/bin:/usr/local/cuda-10.2/NsightCompute-2019.1${PATH:+:${PATH}}" \
	LD_LIBRARY_PATH="/lib:/lib64:${BOOST_LIBRARYDIR}:/usr/local/cuda-10.2/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

# Define default command.
CMD ["/bin/bash"]

