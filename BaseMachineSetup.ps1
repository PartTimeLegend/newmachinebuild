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

function Read-KeyOrTimeout
{
    Param(
        [int]$seconds = 5,
        [string]$prompt = 'Value',
        [string]$default = 'Unknown'
    )
    $startTime = Get-Date
    $timeOut = New-TimeSpan -Seconds $seconds
    Write-Output $prompt
    while (-not $host.ui.RawUI.KeyAvailable) {
        $currentTime = Get-Date
        if ($currentTime -gt $startTime + $timeOut) {
            Break
        }
    }
    if ($host.ui.RawUI.KeyAvailable) {
        [string]$response = ($host.ui.RawUI.ReadKey("IncludeKeyDown,NoEcho")).character
    }
    else
    {
        $response = $default
    }
    return $response
}
 
function installWithChoco()
{
    param(
        [Parameter(Mandatory=$true)][string]$package,
        [Parameter(Mandatory=$false)][string]$version
    )
    Write-Output "Starting install of $package at $(Get-Date -Format "MM/dd/yyyy HH:mm")"
    if (!$version)
    {
        choco install $package -y --source='$chocorepo'
    }
    else
    {
        choco install $package -y --source='$chocorepo' -v $version
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
function installGems()
{
    param(
        [Parameter(Mandatory=$true)][string]$package,
        [Parameter(Mandatory=$false)][string]$version
    )
    Write-Output "Starting install of $package at $(Get-Date -Format "MM/dd/yyyy HH:mm")"
    if (!$version)
    {
        gem install $package
    }
    else
    {
        gem install $package -v $version
    }
}
# Define user vars
try
{
    # Assuming we can access AD get creds
    $personname = Get-ADUser -identity $env:Username -Properties DisplayName | Select-Object DisplayName
    $personemail = Get-ADUser -identity $env:Username -Properties EmailAddress | Select-Object EmailAddress
}
catch
{
    # AD didn't work
    $personname = Read-KeyOrTimeout 30, 'What is your name?', 'Unknown'
    $personemail = Read-KeyOrTimeout 30, 'What is your email?', 'Unknown'
}
# Install required software
Invoke-Expression "refreshenv"
# Source control
installWithChoco "git"
installWithChoco "git-lfs"
installWithChoco "poshgit"
# File comparison
installWithChoco "winmerge"
installWithChoco "meld"
# Languages
installWithChoco "ruby","2.5.1.1"
installWithChoco "golang"
# IDEs
installWithChoco "vscode"
# Text Editors
installWithChoco "notepadplusplus"
# Browsers
installWithChoco "googlechrome"
# Infrastructure - Hashicorp
installWithChoco "terraform"
installWithChoco "vagrant"
installWithChoco "packer"
# Utilities
installWithChoco "7zip"
installWithChoco "sysinternals"
# Database management
installWithChoco "pgadmin3"
installWithChoco "ssms"
# Network tools
installWithChoco "openssh"
installWithChoco "putty.install"
installWithChoco "openssl"
installWithChoco "slack"
installWithChoco "winscp"
installWithChoco "filezilla"
installWithChoco "mremoteng"
# Cloud tools
installWithChoco "awscli"
installWithChoco "azure-cli"
installWithChoco "AWSTools.Powershell"
# Containers
installWithChoco "docker-desktop"
installWithChoco "kubernetes-helm"
# Enable Windows Features
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
# A reboot will be called here. Do not put any further code.
Stop-Transcript # Might not happen with reboot
