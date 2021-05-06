FROM mcr.microsoft.com/windows:1809
HEALTHCHECK NONE
LABEL maintainer="hi@antonybailey.net"
RUN NET USER parttimelegend /add
RUN NET LOCALGROUP Administrators /add parttimelegend
USER parttimelegend
RUN ["powershell", "New-Item", "-Path \"C:\"", "-ItemType \"directory\"", "-Name \"temp\""]
WORKDIR C:/temp
COPY NewMachineSetup.ps1 c:/temp/
RUN powershell -ExecutionPolicy Bypass c:\temp\NewMachineSetup.ps1
RUN ["powershell", "Get-ChildItem", "C:\temp", "-Recurse", "|", "Remove-Item", "-Force"]
