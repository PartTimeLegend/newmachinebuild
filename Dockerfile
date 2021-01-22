FROM mcr.microsoft.com/windows/servercore
LABEL maintainer="hi@antonybailey.net"
RUN ["powershell", "New-Item", "-Path \"C:\"", "-ItemType \"directory\"", "-Name \"temp\""]
WORKDIR C:/temp
COPY BaseMachineSetup.ps1 c:/temp/
RUN powershell.exe -ExecutionPolicy Bypass c:\temp\BaseMachineSetup.ps1
