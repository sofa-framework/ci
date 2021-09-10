# escape=`

# Use the latest Windows Server Core image with .NET Framework 4.7.2.
FROM mcr.microsoft.com/dotnet/framework/sdk:4.7.2-windowsservercore-ltsc2019

# Restore the default Windows shell for correct batch processing.
SHELL ["cmd", "/S", "/C"]

# Set WORKDIR
ENV WORKDIR %TEMP%\sofa_nightly_windows
RUN if not exist %WORKDIR% mkdir %WORKDIR%

# Install SOFA binaries
ARG DOCKER_TAG
ADD https://ci.inria.fr/sofa-ci-dev/job/nightly-generate-binaries/CI_BRANCH=master,CI_SCOPE=${DOCKER_TAG}/lastSuccessfulBuild/artifact/Windows/*zip*/Windows.zip $WORKDIR
RUN powershell Expand-Archive %WORKDIR%\Windows.zip -DestinationPath %WORKDIR% `
 && powershell Expand-Archive %WORKDIR%\Windows\SOFA_*.zip -DestinationPath %WORKDIR%\binaries `
 && move %WORKDIR%\binaries\SOFA_* C:\SOFA
RUN setx /M SOFA_ROOT C:\SOFA `
 && setx /M PATH "%PATH%;C:\SOFA"

# Default entry point if no other command specified
# CMD ["powershell.exe", "-NoLogo", "-ExecutionPolicy", "Bypass"]
CMD ["cmd", "/S", "/C"]
