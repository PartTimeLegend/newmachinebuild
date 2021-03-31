FROM mcr.microsoft.com/windows:1809
LABEL maintainer="hi@antonybailey.net"
RUN ["pwsh", "New-Item", "-Path \"C:\"", "-ItemType \"directory\"", "-Name \"temp\""]
WORKDIR C:/temp
COPY NewMachineSetup.ps1 c:/temp/
RUN pwsh.exe -ExecutionPolicy Bypass c:\temp\NewMachineSetup.ps1
