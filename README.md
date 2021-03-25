# newmachinebuild

[![CICD](https://github.com/PartTimeLegend/newmachinebuild/actions/workflows/cicd.yml/badge.svg)](https://github.com/PartTimeLegend/newmachinebuild/actions/workflows/cicd.yml) [![Docker Pulls](https://img.shields.io/docker/pulls/parttimelegend/newmachinebuild)](https://hub.docker.com/r/parttimelegend/newmachinebuild)

A new machine is a PITA. This makes it less, at least for me it does.

This is basically a [Chocolately](https://chocolatey.org) wrapper script. Don't pay it much attention. Oh it also installs WSL if you uncomment that bit. GitHub can't do WSL.

Relies on

## Docker
There's a Dockerfile. I try and build with Github Actions but Windows containers...
```bash
docker pull parttimelegend/newmachinebuild
```

## Vagrant
There's a Vagrantfile. I try to build with Github Actions but not enough space.
