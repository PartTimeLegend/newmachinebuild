Clear-Host
# req admin rights, so restart if not admin
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs;
    exit
}
# Begin logfile
$username= Get-Content env:username
$computer = Get-Content env:computername
$Logfile = "C:\$computer-$username-$(Get-Date -Format "MM/dd/yyyy-HH:mm")-install.log"
Start-Transcript -path $LogFile -append
# Install Chocolatey - We will use this for all our installs and upgrades
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
# Define Dir Structure
mkdir C:\workspace -ErrorAction SilentlyContinue -Force
# Define Choco Repo
$chocorepo = "https://chocolatey.org/api/v2//"
$windowsCaption = (Get-CimInstance -ClassName Win32_OperatingSystem).Caption
function installWithChoco()
{
  param(
      [Parameter(Mandatory=$true)][string]$package,
      [Parameter(Mandatory=$false)][string]$version
  )
  Write-Output "Starting install of $package at $(Get-Date -Format "MM/dd/yyyy HH:mm")"
  if (!$version)
  {
      choco install $package -y --source=$chocorepo --ignore-checksums
  }
  else
  {
      choco install $package -y --source=$chocorepo -v $version --ignore-checksums
  }
  $exitCode = $LASTEXITCODE
  Write-Verbose "Exit code was $exitCode"
  $validExitCodes = @(0, 1605, 1614, 1641, 3010)
  if ($validExitCodes -contains $exitCode)
  {
      Write-Output "The package $package was installed successfully"
  }
  else
  {
      Write-Output "The package $package was not correctly installed"
  }
}
function EnableHyperV()
{
  Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
}
# Install required software
refreshenv
# Source control
installWithChoco "git"
installWithChoco "git-lfs"
installWithChoco "poshgit"
# File comparison
installWithChoco "winmerge"
installWithChoco "meld"
# Languages
installWithChoco "ruby"
installWithChoco "golang"
installWithChoco "python"
installWithChoco "dotnetfx"
# IDEs
installWithChoco "vscode"
installWithChoco "postman"
# Not sure what Visual Studio to use - guess based on OS
switch ($windowsCaption)
{
  {$_.Contains("Home")} { installWithChoco "visualstudio2019community" }
  {$_.Contains("Business")} { installWithChoco "visualstudio2019professional" }
  {$_.Contains("Enterprise")} { installWithChoco "visualstudio2019enterprise" }
  Default { installWithChoco "visualstudio2019community" } # Just in case we will install community but tidy it up later
}
installWithChoco "resharper"
# Text Editors
installWithChoco "notepadplusplus"
# Browsers
installWithChoco "googlechrome"
installWithChoco "firefox"
# Infrastructure - Hashicorp
installWithChoco "terraform"
installWithChoco "packer"
installWithChoco "tflint"
# Utilities
installWithChoco "7zip"
installWithChoco "sysinternals"
installWithChoco "powershell"
installWithChoco "cmake"
installWithChoco "checksum"
# Database management
installWithChoco "pgadmin3"
installWithChoco "ssms"
installWithChoco "azure-documentdb-data-migration-tool"
installWithChoco "nosql-workbench"
installWithChoco "sqltoolbelt"
installWithChoco "studio3t"
# Network tools
installWithChoco "openssh"
installWithChoco "putty.install"
installWithChoco "openssl"
installWithChoco "slack"
installWithChoco "winscp"
installWithChoco "filezilla"
installWithChoco "mremoteng"
installWithChoco "teamviewer"
installWithChoco "curl"
installWithChoco "nmap"
# Cloud tools
installWithChoco "awscli"
installWithChoco "azure-cli"
installWithChoco "AWSTools.Powershell"
# Containers
installWithChoco "docker-desktop"
installWithChoco "kubernetes-helm"
installWithChoco "kubernetes-cli"
installWithChoco "minikube"
# Video Calls
installWithChoco "zoom"
installWithChoco "microsoft-teams.install"
# Media
installWithChoco "vlc"
installWithChoco "jabra-direct"
# Features
installWithChoco "wsl2"
# List Packages
choco list --local-only
# Enable Windows Features
switch ($windowsCaption)
{
  {$_.Contains("Business") -or $_.Contains("Enterprise")} { EnableHyperV }
}
# A reboot will be called here. Do not put any further code.
Stop-Transcript # Might not happen with reboot
