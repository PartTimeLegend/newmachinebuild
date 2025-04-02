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

# Array to track failed installations
$failedInstallations = @()

#region Functions

function Install-With-Choco {
  param(
      [Parameter(Mandatory=$true)][string]$package,
      [Parameter(Mandatory=$false)][string]$version
  )
  Write-Output "Starting install of $package at $(Get-Date -Format "MM/dd/yyyy HH:mm")"
  try {
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
          $script:failedInstallations += [PSCustomObject]@{
              Package = $package
              Reason = "Exit code $exitCode"
          }
      }
  } catch {
      Write-Output ("Failed to install {0}: {1}" -f $package, $_.Exception.Message)
      $script:failedInstallations += [PSCustomObject]@{
          Package = $package
          Reason = $_.Exception.Message
      }
  }
}

function Install-Optional-Feature {
  param(
      [Parameter(Mandatory=$true)][string]$feature
  )
  Write-Output "Starting install of feature $feature at $(Get-Date -Format "MM/dd/yyyy HH:mm")"
  try {
      choco install $feature --source windowsfeatures
  } catch {
      Write-Output ("Failed to install feature: {0} - {1}" -f $feature, $_.Exception.Message)
      $script:failedInstallations += [PSCustomObject]@{
          Package = "Feature: $feature"
          Reason = $_.Exception.Message
      }
  }
}

function Install-PIP {
  Write-Output "Starting install of Python packages from requirements.txt at $(Get-Date -Format "MM/dd/yyyy HH:mm")"
  if (Test-Path "requirements.txt" -PathType Leaf) {
    if (Get-Command pip -ErrorAction SilentlyContinue) {
      try {
          pip install -r requirements.txt
      } catch {
          Write-Output ("Failed to install Python packages: {0}" -f $_.Exception.Message)
          $script:failedInstallations += [PSCustomObject]@{
              Package = "Python packages"
              Reason = $_.Exception.Message
          }
      }
    } else {
      Write-Output "pip command not found, skipping Python package installation"
      $script:failedInstallations += [PSCustomObject]@{
          Package = "Python packages"
          Reason = "pip command not found"
      }
    }
  } else {
    Write-Output "requirements.txt not found, skipping Python package installation"
    $script:failedInstallations += [PSCustomObject]@{
        Package = "Python packages"
        Reason = "requirements.txt not found"
    }
  }
}

function Install-Gemfile {
  Write-Output "Starting install of Ruby gems from Gemfile at $(Get-Date -Format "MM/dd/yyyy HH:mm")"
  if (Test-Path "Gemfile" -PathType Leaf) {
    if (Get-Command bundle -ErrorAction SilentlyContinue) {
      try {
          bundle install
      } catch {
          Write-Output ("Failed to install Ruby gems: {0}" -f $_.Exception.Message)
          $script:failedInstallations += [PSCustomObject]@{
              Package = "Ruby gems"
              Reason = $_.Exception.Message
          }
      }
    } else {
      Write-Output "bundle command not found, skipping Ruby gems installation"
      $script:failedInstallations += [PSCustomObject]@{
          Package = "Ruby gems"
          Reason = "bundle command not found"
      }
    }
  } else {
    Write-Output "Gemfile not found, skipping Ruby gems installation"
    $script:failedInstallations += [PSCustomObject]@{
        Package = "Ruby gems"
        Reason = "Gemfile not found"
    }
  }
}

function EnableHyperV {
  Write-Output "Enabling Hyper-V..."
  try {
      Install-Optional-Feature "Microsoft-Hyper-V"
  } catch {
      # Use format operator for error messages
      Write-Output ("Failed to enable Hyper-V: {0}" -f $_.Exception.Message)
      $script:failedInstallations += [PSCustomObject]@{
          Package = "Hyper-V"
          Reason = $_.Exception.Message
      }
  }
}

function Install-Windows-Update {
  try {
      $service = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
      if($null -eq $service) {
        Write-Output "Windows Update Service Does Not Exist."
        $script:failedInstallations += [PSCustomObject]@{
            Package = "Windows Updates"
            Reason = "Windows Update Service does not exist"
        }
        return
      }

      if($service.Status -eq "Disabled") {
        Write-Output "Attempting to enable $($service.name)"
        Set-Service -Name $service.name -StartupType Automatic -Force
      }
      if($service.Status -eq "Stopped") {
        Write-Output "Attempting to start $($service.Name)"
        Start-Service -Name $service.Name
      }

      Install-Module PSWindowsUpdate -Force
      Get-WindowsUpdate -AcceptAll
      Install-WindowsUpdate -MicrosoftUpdate -IgnoreReboot -AcceptAll
  } catch {
      Write-Output ("Failed to install Windows updates: {0}" -f $_.Exception.Message)
      $script:failedInstallations += [PSCustomObject]@{
          Package = "Windows Updates"
          Reason = $_.Exception.Message
      }
  }
}

#endregion Functions

# Install Chocolatey - We will use this for all our installs and upgrades
Write-Output "Installing Chocolatey package manager..."
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
    } catch {
        Write-Output ("Failed to install Chocolatey: {0}" -f $_.Exception.Message)
        $script:failedInstallations += [PSCustomObject]@{
            Package = "Chocolatey"
            Reason = $_.Exception.Message
        }
    }
} else {
    Write-Output "Chocolatey is already installed."
}

# Create workspace directory
Write-Output "Creating workspace directory..."
if (-not (Test-Path "c:\workspace")) {
    try {
        New-Item -Path "c:\" -Name "workspace" -ItemType "Directory" | Out-Null
    } catch {
        Write-Output ("Failed to create workspace directory: {0}" -f $_.Exception.Message)
        $script:failedInstallations += [PSCustomObject]@{
            Package = "Workspace directory"
            Reason = $_.Exception.Message
        }
    }
}

# Install Windows features from features.txt
if (Test-Path "features.txt" -PathType Leaf) {
    $features = Get-Content features.txt
    Write-Output "Installing Windows features..."
    foreach ($feature in $features) {
        Install-Optional-Feature $feature
    }
} else {
    Write-Output "features.txt not found, skipping Windows features installation"
    $script:failedInstallations += [PSCustomObject]@{
        Package = "Windows Features"
        Reason = "features.txt not found"
    }
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
      EnableHyperV
    }
  {$_.Contains("Enterprise")} {
      $vsPackage = "visualstudio2022enterprise"
      $officePackage = "office365business"
      Write-Output "Windows Enterprise edition detected, will install $vsPackage and $officePackage"
      EnableHyperV
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
        Write-Output ("Failed to install packages from chocolatey.config: {0}" -f $_.Exception.Message)
        $script:failedInstallations += [PSCustomObject]@{
            Package = "Chocolatey packages (config)"
            Reason = $_.Exception.Message
        }
    }
} else {
    Write-Output "chocolatey.config not found, trying fallback to chocolatey.txt"
    if (Test-Path "chocolatey.txt" -PathType Leaf) {
        $chocolateypackages = Get-Content chocolatey.txt
        foreach ($package in $chocolateypackages) {
            Install-With-Choco -package $package
        }
    } else {
        Write-Output "Neither chocolatey.config nor chocolatey.txt found, skipping package installation"
        $script:failedInstallations += [PSCustomObject]@{
            Package = "Chocolatey packages"
            Reason = "Neither chocolatey.config nor chocolatey.txt found"
        }
    }
}

# Install Visual Studio and Office separately
if ($vsPackage -ne "") {
    Write-Output "Installing $vsPackage..."
    Install-With-Choco -package $vsPackage
}

if ($officePackage -ne "") {
    Write-Output "Installing $officePackage..."
    Install-With-Choco -package $officePackage
}

# Install Python packages and Ruby Gems
Install-PIP
Install-Gemfile

# Run Windows Updates if enabled
if($true -eq $windowsUpdate) {
    Install-Windows-Update
}

# Display summary of installations
Write-Output "`nInstallation Summary"
Write-Output "===================="

if ($failedInstallations.Count -gt 0) {
    Write-Output "`nFailed Installations:"
    Write-Output "---------------------"
    $failedInstallations | Format-Table -Property @{Label="Package"; Expression={$_.Package}}, @{Label="Reason"; Expression={$_.Reason}} -AutoSize -Wrap

    Write-Output "`nSetup completed with some failures. Please check the errors above."
} else {
    Write-Output "`nAll applications were installed successfully!"
}

Write-Output "`nSetup completed!"
Stop-Transcript # Might not happen with reboot
