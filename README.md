# New Machine Build

[![CICD](https://github.com/PartTimeLegend/newmachinebuild/actions/workflows/cicd.yml/badge.svg)](https://github.com/PartTimeLegend/newmachinebuild/actions/workflows/cicd.yml) [![Windows Docker Pulls](https://img.shields.io/docker/pulls/parttimelegend/newmachinebuildwindows)](https://hub.docker.com/r/parttimelegend/newmachinebuildwindows) [![Linux Docker Pulls](https://img.shields.io/docker/pulls/parttimelegend/newmachinebuildlinux)](https://hub.docker.com/r/parttimelegend/newmachinebuildlinux)

A new machine is a PITA. This makes it less, at least for me it does.

This is basically a [Chocolately](https://chocolatey.org) or [Brew](https://brew.sh/) wrapper script.

As this is my personal set up I will not be accepting package PR's. I'm sorry, but I'm not installing things I don't need. You can fork it though.

## Manual
```powershell
powershell -nop -c "iex(New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/PartTimeLegend/newmachinebuild/master/NewMachineSetup.ps1')"
```

```bash
curl -sSL https://raw.githubusercontent.com/PartTimeLegend/newmachinebuild/master/NewMachineSetup.sh| bash
```

## Docker
Because you totally wanted this as a container.
```powershell
docker pull parttimelegend/newmachinebuildwindows
```

bashpowershell
docker pull parttimelegend/newmachinebuildlinux
```
