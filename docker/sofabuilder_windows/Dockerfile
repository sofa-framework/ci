# escape=`

# Use the latest Windows Server Core image with .NET Framework 4.7.2.
FROM mcr.microsoft.com/dotnet/framework/sdk:4.7.2-windowsservercore-ltsc2019

# Restore the default Windows shell for correct batch processing.
SHELL ["cmd", "/S", "/C"]

# Install Visual Studio Build Tools 2017
# To see component names, run Visual Studio Installer and play with configuration export.
# Use --passive instead of --quiet when testing (GUI will appear with progress bar).
ADD https://aka.ms/vs/15/release/vs_buildtools.exe C:\TEMP\vs_buildtools.exe
ADD https://raw.githubusercontent.com/guparan/DockerSofaBuilder/master/sofabuilder_windows_vs2017/wait_process_to_end.bat C:\TEMP\wait_process_to_end.bat	
RUN C:\TEMP\vs_buildtools.exe --wait --quiet --norestart --nocache `
    --installPath C:\BuildTools `
    --add Microsoft.VisualStudio.Workload.VCTools `
	--add microsoft.visualstudio.component.vc.cmake.project `
	--add microsoft.visualstudio.component.testtools.buildtools `
	--add microsoft.visualstudio.component.vc.atlmfc `
	--add microsoft.visualstudio.component.vc.cli.support `
	--includeRecommended `
	& C:\TEMP\wait_process_to_end.bat "vs_bootstrapper.exe" `
	& C:\TEMP\wait_process_to_end.bat "vs_BuildTools.exe" `
	& C:\TEMP\wait_process_to_end.bat "vs_installer.exe"
ENV VS150COMNTOOLS C:\BuildTools\Common7\Tools\\
ENV VSINSTALLDIR C:\BuildTools\\

# Install Qt
ENV QT_VERSION_MAJOR 5
ENV QT_VERSION_MINOR 12
ENV QT_VERSION_PATCH 6
ENV QTDIR C:\Qt\${QT_VERSION_MAJOR}.${QT_VERSION_MINOR}.${QT_VERSION_PATCH}\msvc2017_64
ENV QTDIR64 $QTDIR
ENV Qt5_DIR $QTDIR
ADD https://download.qt.io/official_releases/online_installers/qt-unified-windows-x86-online.exe C:\TEMP\qtinstaller.exe
ADD https://raw.githubusercontent.com/guparan/DockerSofaBuilder/master/sofabuilder_windows_vs2017/qtinstaller_controlscript_template.qs C:\TEMP\qtinstaller_controlscript_template.qs
RUN powershell -Command "(gc C:\TEMP\qtinstaller_controlscript_template.qs) -replace '_QTVERSION_', %QT_VERSION_MAJOR%%QT_VERSION_MINOR%%QT_VERSION_PATCH% | Out-File -encoding ASCII C:\TEMP\qtinstaller_controlscript.qs"
RUN C:\TEMP\qtinstaller.exe --script C:\TEMP\qtinstaller_controlscript.qs

# Install Boost
ENV BOOST_VERSION_MAJOR 1
ENV BOOST_VERSION_MINOR 69
ENV BOOST_VERSION_PATCH 0
ADD https://downloads.sourceforge.net/project/boost/boost-binaries/${BOOST_VERSION_MAJOR}.${BOOST_VERSION_MINOR}.${BOOST_VERSION_PATCH}/boost_${BOOST_VERSION_MAJOR}_${BOOST_VERSION_MINOR}_${BOOST_VERSION_PATCH}-msvc-14.1-64.exe C:\TEMP\boostinstaller.exe
ADD https://raw.githubusercontent.com/guparan/DockerSofaBuilder/master/sofabuilder_windows_vs2017/wait_process_to_end.bat C:\TEMP\wait_process_to_end.bat	
RUN C:\TEMP\boostinstaller.exe /NORESTART /VERYSILENT /DIR="C:\boost" `
	& C:\TEMP\wait_process_to_end.bat "boostinstaller.exe"

# Install Chocolatey
RUN @powershell -NoProfile -InputFormat None -ExecutionPolicy Bypass -Command `
    "iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))" `
	&& SET "PATH=%PATH%;%ALLUSERSPROFILE%\chocolatey\bin"

# Install dependencies with Chocolatey
RUN choco install -y git `
 && choco install -y zip `
 && choco install -y unzip `
 && choco install -y curl `
 && choco install -y ninja `
 && choco install -y cmake --installargs 'ADD_CMAKE_TO_PATH=System' `
 && choco install -y python2 `
 && refreshenv
RUN pip install --upgrade pip `
 && pip install numpy scipy `
 && refreshenv

# Finalize environment
ENV PYTHONIOENCODING UTF-8
RUN setx PATH "%PATH%;C:\Program Files (x86)\Windows Kits\8.1\bin\x64" `
 && setx PATH "%PATH%;C:\Program Files (x86)\Windows Kits\10\bin\x64" `
 && setx PATH "%PATH%;C:\Qt\%QT_VERSION_MAJOR%.%QT_VERSION_MINOR%.%QT_VERSION_PATCH%\msvc2017_64\bin" `
 && setx PATH "%PATH%;C:\Qt\Tools\QtCreator\bin" `
 && setx PATH "%PATH%;C:\boost" `
 && setx PATH "%PATH%;C:\boost\lib64-msvc-14.1" `
 && setx PATH "%PATH%;C:\Program Files\Git\bin" `
 && setx PATH "%PATH%;C:\Windows\System32\downlevel" `
 && refreshenv

# Default entry point if no other command specified
# CMD ["powershell.exe", "-NoLogo", "-ExecutionPolicy", "Bypass"]
# CMD ["C:\Program Files\Git\bin\bash.exe"]
# ENTRYPOINT C:\BuildTools\Common7\Tools\VsDevCmd.bat &&
# ENTRYPOINT "bash"
CMD ["cmd", "/S", "/C"]
