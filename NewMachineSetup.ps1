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
New-Item -Path "c:\" -Name "workspace" -ItemType "Directory"
# Define Choco Repo
$chocorepo = "https://chocolatey.org/api/v2//"
$windowsCaption = (Get-CimInstance -ClassName Win32_OperatingSystem).Caption
$packages = @(
  "git",
  "git-lfs",
  "poshgit",
  "gitversion.portable",
  "winmerge",
  "meld",
  "ruby",
  "golang",
  "python",
  "dotnetfx",
  "dotnetcore-sdk",
  "nodejs",
  "vscode",
  "postman",
  "resharper",
  "notepadplusplus",
  "010editor",
  "googlechrome",
  "firefox",
  "flux",
  "terraformer",
  "terraform",
  "terragrunt",
  "packer",
  "tflint",
  "azure-pipelines-agent",
  "7zip",
  "sysinternals",
  "cmake",
  "checksum",
  "spin",
  "apimonitor",
  "yarn",
  "keepass",
  "jq",
  "expresso",
  "ssms",
  "azure-documentdb-data-migration-tool",
  "nosql-workbench",
  "openssh",
  "putty.install",
  "openssl",
  "winscp",
  "filezilla",
  "mremoteng",
  "curl",
  "usbpcap",
  "wireshark",
  "nmap",
  "tapwindows",
  "awscli",
  "azure-cli",
  "ServiceBusExplorer",
  "microsoftazurestorageexplorer",
  "nugetpackageexplorer",
  "docker-desktop",
  "kubernetes-helm",
  "kubernetes-cli",
  "minikube",
  "microsoft-teams.install",
  "wsl2",
  "pscodehealth",
  "azure-cosmosdb-emulator",
  "wiremockui",
  "k9s",
  "microsoft-windows-terminal",
  "zoom",
  "fiddler",
  "gnupg",
  "logitechgaming",
  "logitech-options"
)
$features = @(
  "IIS-WebServerRole",
  "IIS-WebServer",
  "IIS-CommonHttpFeatures",
  "IIS-ManagementConsole",
  "IIS-HttpErrors",
  "IIS-HttpRedirect",
  "IIS-WindowsAuthentication",
  "IIS-StaticContent",
  "IIS-DefaultDocument",
  "IIS-HttpCompressionStatic",
  "IIS-DirectoryBrowsing",
  "Microsoft-Windows-Subsystem-Linux"
)
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
function installOptionalFeature()
{
  param(
      [Parameter(Mandatory=$true)][string]$feature
  )
  Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart
}

function EnableHyperV()
{
  installOptionalFeature "Microsoft-Hyper-V"
}

switch ($windowsCaption)
{
  {$_.Contains("Home")} {
      $packages += "visualstudio2019community"
      $packages += "office365homepremium"
    }
  {$_.Contains("Business")} {
      $packages += "visualstudio2019professional"
      $packages += "office365business"
      EnableHyperV
    }
  {$_.Contains("Enterprise")} {
      $packages += "visualstudio2019enterprise"
      $packages += "office365business"
      EnableHyperV
    }
  Default { $packages += "visualstudio2019community" } # Just in case we will install community but tidy it up later
}

foreach ($package in $packages) {
    installWithChoco $package
}
foreach ($feature in $features) {
    installOptionalFeature $feature
}
# List Packages
choco list --local-only
# Go get
go get -u -u github.com/jrhouston/tfk8s
# Ruby gems - I will put these in a Gemfile
gem install terraforming
# Enable Windows Features
# A reboot will be called here. Do not put any further code.
Stop-Transcript # Might not happen with reboot
