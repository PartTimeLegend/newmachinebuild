FROM mcr.microsoft.com/windows:2009
HEALTHCHECK NONE
LABEL maintainer="hi@antonybailey.net"
RUN ["powershell", "New-Item", "-Path \"C:\"", "-ItemType \"directory\"", "-Name \"temp\""]
WORKDIR C:/temp
COPY NewMachineSetup.ps1 c:/temp/
COPY chocolatey.config c:/temp/
COPY features.txt c:/temp/
COPY requirements.txt c:/temp/
COPY Gemfile c:/temp/
RUN powershell -ExecutionPolicy Bypass c:\temp\NewMachineSetup.ps1
RUN ["powershell", "Get-ChildItem", "C:\temp", "-Recurse", "|", "Remove-Item", "-Force"]
