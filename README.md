# New Machine Build

[![CICD](https://github.com/PartTimeLegend/newmachinebuild/actions/workflows/cicd.yml/badge.svg)](https://github.com/PartTimeLegend/newmachinebuild/actions/workflows/cicd.yml) [![Docker Pulls](https://img.shields.io/docker/pulls/parttimelegend/newmachinebuild)](https://hub.docker.com/r/parttimelegend/newmachinebuild)

A new machine is a PITA. This makes it less, at least for me it does.

This is basically a [Chocolately](https://chocolatey.org) wrapper script.

As this is my personal set up I will not be accepting package PR's. I'm sorry, but I'm not installing things I don't need. You can fork it though.

## Manual
```powershell
powershell -nop -c "iex(New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/PartTimeLegend/newmachinebuild/master/NewMachineSetup.ps1')"
```

## Signed
If you're getting a message about it not being signed then you will have to get the build artifact.

## Docker
Because you totally wanted this as a container.
```powershell
docker pull parttimelegend/newmachinebuild
```
