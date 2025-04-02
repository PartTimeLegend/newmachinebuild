Clear-Host
# req admin rights, so restart if not admin
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs;
    exit
}

# Begin logfile
$username = Get-Content env:username
$computer = Get-Content env:computername
$Logfile = "C:\$computer-$username-$(Get-Date -Format "MM/dd/yyyy-HH:mm")-install.log"
Start-Transcript -path $LogFile -append
New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" `
-Name "LongPathsEnabled" -Value 1 -PropertyType DWORD -Force

# Define variables
$chocorepo = "https://chocolatey.org/api/v2//"
$windowsCaption = (Get-CimInstance -ClassName Win32_OperatingSystem).Caption
$windowsUpdate = $false

#region Functions

function Install-With-Choco {
  param(
      [Parameter(Mandatory=$true)][string]$package,
      [Parameter(Mandatory=$false)][string]$version
  )
  Write-Output "Starting install of $package at $(Get-Date -Format "MM/dd/yyyy HH:mm")"
  if (!$version) {
      choco install $package -y --source=$chocorepo --ignore-checksums
  } else {
      choco install $package -y --source=$chocorepo -v $version --ignore-checksums
  }
  $exitCode = $LASTEXITCODE
  Write-Verbose "Exit code was $exitCode"
  $validExitCodes = @(0, 1605, 1614, 1641, 3010)
  if ($validExitCodes -contains $exitCode) {
      Write-Output "The package $package was installed successfully"
  } else {
      Write-Output "The package $package was not correctly installed"
  }
}

function Install-Optional-Feature {
  param(
      [Parameter(Mandatory=$true)][string]$feature
  )
  Write-Output "Starting install of feature $feature at $(Get-Date -Format "MM/dd/yyyy HH:mm")"
  choco install $feature --source windowsfeatures
}

function Install-PIP {
  Write-Output "Starting install of Python packages from requirements.txt at $(Get-Date -Format "MM/dd/yyyy HH:mm")"
  if (Test-Path "requirements.txt" -PathType Leaf) {
    if (Get-Command pip -ErrorAction SilentlyContinue) {
      pip install -r requirements.txt
    } else {
      Write-Output "pip command not found, skipping Python package installation"
    }
  } else {
    Write-Output "requirements.txt not found, skipping Python package installation"
  }
}

function Install-Gemfile {
  Write-Output "Starting install of Ruby gems from Gemfile at $(Get-Date -Format "MM/dd/yyyy HH:mm")"
  if (Test-Path "Gemfile" -PathType Leaf) {
    if (Get-Command bundle -ErrorAction SilentlyContinue) {
      bundle install
    } else {
      Write-Output "bundle command not found, skipping Ruby gems installation"
    }
  } else {
    Write-Output "Gemfile not found, skipping Ruby gems installation"
  }
}

function EnableHyperV {
  Write-Output "Enabling Hyper-V..."
  Install-Optional-Feature "Microsoft-Hyper-V"
}

function Install-Windows-Update {
  $service = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
  if($null -eq $service) {
    Write-Output "Windows Update Service Does Not Exist."
  } else {
    if($service.Status -eq "Disabled") {
      Write-Output "Attempting to enable " $service.name
      Set-Service -Name $service.name -StartupType Automatic -Force
    }
    if($service.Status -eq "Stopped") {
      Write-Output "Attempting to start " $service.name
      Start-Service -Name $service.Name
    }
    Install-Module PSWindowsUpdate -Force
    Get-WindowsUpdate -AcceptAll
    Install-WindowsUpdate -MicrosoftUpdate -IgnoreReboot -AcceptAll
  }
}

#endregion Functions

# Install Chocolatey - We will use this for all our installs and upgrades
Write-Output "Installing Chocolatey package manager..."
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
} else {
    Write-Output "Chocolatey is already installed."
}

# Create workspace directory
Write-Output "Creating workspace directory..."
if (-not (Test-Path "c:\workspace")) {
    New-Item -Path "c:\" -Name "workspace" -ItemType "Directory" | Out-Null
}

# Install Windows features from features.txt
if (Test-Path "features.txt" -PathType Leaf) {
    $features = Get-Content features.txt
    Write-Output "Installing Windows features..."
    foreach ($feature in $features) {
        try {
            Install-Optional-Feature $feature
        } catch {
            Write-Output "Failed to install feature: $feature - $_"
        }
    }
} else {
    Write-Output "features.txt not found, skipping Windows features installation"
}

# Add Visual Studio and Office based on Windows edition
Write-Output "Detecting Windows edition: $windowsCaption"
$vsPackage = "visualstudio2022community"
$officePackage = ""

switch ($windowsCaption)
{
  {$_.Contains("Home")} {
      $vsPackage = "visualstudio2022community"
      $officePackage = "office365homepremium"
      Write-Output "Windows Home edition detected, will install $vsPackage and $officePackage"
    }
  {$_.Contains("Business")} {
      $vsPackage = "visualstudio2022professional"
      $officePackage = "office365business"
      Write-Output "Windows Business edition detected, will install $vsPackage and $officePackage"
      try { EnableHyperV } catch { Write-Output "Failed to enable Hyper-V: $_" }
    }
  {$_.Contains("Enterprise")} {
      $vsPackage = "visualstudio2022enterprise"
      $officePackage = "office365business"
      Write-Output "Windows Enterprise edition detected, will install $vsPackage and $officePackage"
      try { EnableHyperV } catch { Write-Output "Failed to enable Hyper-V: $_" }
    }
  Default {
      Write-Output "Could not determine Windows edition, defaulting to Visual Studio Community"
      $vsPackage = "visualstudio2022community"
  }
}

# Install packages from chocolatey.config
if (Test-Path "chocolatey.config" -PathType Leaf) {
    Write-Output "Installing packages from chocolatey.config..."
    try {
        choco install chocolatey.config --source=$chocorepo --ignore-checksums
    } catch {
        Write-Output "Failed to install packages from chocolatey.config: $_"
    }
} else {
    Write-Output "chocolatey.config not found, trying fallback to chocolatey.txt"
    if (Test-Path "chocolatey.txt" -PathType Leaf) {
        $chocolateypackages = Get-Content chocolatey.txt
        foreach ($package in $chocolateypackages) {
            try {
                Install-With-Choco -package $package
            } catch {
                Write-Output "Failed to install package: $package - $_"
            }
        }
    } else {
        Write-Output "Neither chocolatey.config nor chocolatey.txt found, skipping package installation"
    }
}

# Install Visual Studio and Office separately
if ($vsPackage -ne "") {
    Write-Output "Installing $vsPackage..."
    try {
        Install-With-Choco -package $vsPackage
    } catch {
        Write-Output "Failed to install $vsPackage: $_"
    }
}

if ($officePackage -ne "") {
    Write-Output "Installing $officePackage..."
    try {
        Install-With-Choco -package $officePackage
    } catch {
        Write-Output "Failed to install $officePackage: $_"
    }
}

# Install Python packages and Ruby Gems
try {
    Install-PIP
} catch {
    Write-Output "Failed to install Python packages: $_"
}

try {
    Install-Gemfile
} catch {
    Write-Output "Failed to install Ruby gems: $_"
}

# Run Windows Updates if enabled
if($true -eq $windowsUpdate) {
    try {
        Install-Windows-Update
    } catch {
        Write-Output "Failed to install Windows updates: $_"
    }
}

Write-Output "Setup completed successfully!"
Stop-Transcript # Might not happen with reboot
