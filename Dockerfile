FROM mcr.microsoft.com/windows/insider:10.0.20287.1
LABEL maintainer="hi@antonybailey.net"
RUN ["powershell", "New-Item", "-Path \"C:\"", "-ItemType \"directory\"", "-Name \"temp\""]
WORKDIR C:/temp
COPY NewMachineSetup.ps1 c:/temp/
RUN powershell.exe -ExecutionPolicy Bypass c:\temp\NewMachineSetup.ps1
