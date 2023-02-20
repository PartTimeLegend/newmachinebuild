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
New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" `
-Name "LongPathsEnabled" -Value 1 -PropertyType DWORD -Force
# Install Chocolatey - We will use this for all our installs and upgrades
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
# Define Dir Structure
New-Item -Path "c:\" -Name "workspace" -ItemType "Directory"
# Define Choco Repo
$chocorepo = "https://chocolatey.org/api/v2//"
$windowsCaption = (Get-CimInstance -ClassName Win32_OperatingSystem).Caption
$windowsUpdate = $false
$chocolateypackages = Get-Content chocolatey.txt

$features = Get-Content features.txt

function Install-With-Choco()
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

function Install-Optional-Feature()
{
  param(
      [Parameter(Mandatory=$true)][string]$feature
  )
  Write-Output "Starting install of $feature at $(Get-Date -Format "MM/dd/yyyy HH:mm")"
  choco install $feature --source windowsfeatures
}

function Install-PIP()
{
  Write-Output "Starting install of requirements.txt at $(Get-Date -Format "MM/dd/yyyy HH:mm")"
  pip install -r requirements.txt
}

function Install-Gemfile()
{
  Write-Output "Starting install of Gemfile at $(Get-Date -Format "MM/dd/yyyy HH:mm")"
  bundle install
}


function EnableHyperV()
{
  Install-Optional-Feature "Microsoft-Hyper-V"
}

function Install-Windows-Update()
{
  $service = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
  if($null -eq $service)
  {
    Write-Output "Windows Update Service Does Not Exist."
  }
  else
  {
    if($serice.Status -eq "Disabled")
    {
      Write-Output "Attempting to enable " $service.name
      Set-Service -Name $service.name -StartupType Automatic -Force
    }
    if($service.Status -eq "Stopped")
    {
      Write-Output "Attempting to start " $service.name
      Start-Service -Name $service.Name
    }
    Install-Module PSWindowsUpdate -Force
    Get-WindowsUpdate -AcceptAll
    Install-WindowsUpdate -MicrosoftUpdate -IgnoreReboot -AcceptAll
  }
}

switch ($windowsCaption)
{
  {$_.Contains("Home")} {
      $packages += "visualstudio2022community"
      $packages += "office365homepremium"
    }
  {$_.Contains("Business")} {
      $packages += "visualstudio2022professional"
      $packages += "office365business"
      EnableHyperV
    }
  {$_.Contains("Enterprise")} {
      $packages += "visualstudio2022enterprise"
      $packages += "office365business"
      EnableHyperV
    }
  Default { $packages += "visualstudio2019community" } # Just in case we will install community but tidy it up later
}

foreach ($feature in $features)
{
    Install-Optional-Feature $feature
}

foreach ($package in $chocolateypackages)
{
    Install-With-Choco $package
}

Install-Pip
Install-Gemfile

# List Packages
choco list --local-only
# Run Windows Updates
if($true -eq $windowsUpdate)
{
  Install-Windows-Update
}
# A reboot will be called here. Do not put any further code.
Stop-Transcript # Might not happen with reboot
