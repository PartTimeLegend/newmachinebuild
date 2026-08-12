param(
    [switch]$ValidateOnly,
    [switch]$SkipElevation,
    [switch]$DryRun,
    [switch]$WindowsUpdate,
    [int]$MaxRetries = 2
)

$ErrorActionPreference = "Stop"

if (-not $ValidateOnly) {
    Clear-Host
}

if (-not $ValidateOnly -and -not $SkipElevation) {
    if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        exit
    }
}

$script:chocoRepo = "https://chocolatey.org/api/v2//"
$script:windowsUpdate = $WindowsUpdate.IsPresent
$script:failedInstallations = @()
$script:operationStates = @()
$script:vsPackage = "visualstudio2022community"
$script:officePackage = ""
$script:windowsCaption = "Unknown"

function Add-FailedInstallation {
    param(
        [Parameter(Mandatory=$true)][string]$Package,
        [Parameter(Mandatory=$true)][string]$Reason
    )

    $script:failedInstallations += [PSCustomObject]@{
        Package = $Package
        Reason = $Reason
    }
}

function Set-OperationState {
    param(
        [Parameter(Mandatory=$true)][string]$Operation,
        [Parameter(Mandatory=$true)][string]$State,
        [string]$Message = ""
    )

    $script:operationStates += [PSCustomObject]@{
        Operation = $Operation
        State = $State
        Message = $Message
        Timestamp = (Get-Date)
    }
}

function Invoke-WithRetry {
    param(
        [Parameter(Mandatory=$true)][string]$Description,
        [Parameter(Mandatory=$true)][ScriptBlock]$Action
    )

    if ($DryRun) {
        Write-Output "[dry-run] $Description"
        return $true
    }

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            & $Action
            return $true
        } catch {
            if ($attempt -lt $MaxRetries) {
                Write-Output "Retrying '$Description' (attempt $($attempt + 1)/$MaxRetries)..."
                Start-Sleep -Seconds 2
                continue
            }

            Write-Output "Failed '$Description': $($_.Exception.Message)"
            return $false
        }
    }

    return $false
}

function Invoke-Stage {
    param(
        [Parameter(Mandatory=$true)][string]$StageName,
        [Parameter(Mandatory=$true)][ScriptBlock]$Action
    )

    Set-OperationState -Operation $StageName -State "planned"
    Set-OperationState -Operation $StageName -State "running"

    try {
        & $Action
        Set-OperationState -Operation $StageName -State "succeeded"
        return $true
    } catch {
        Set-OperationState -Operation $StageName -State "failed" -Message $_.Exception.Message
        Add-FailedInstallation -Package $StageName -Reason $_.Exception.Message
        return $false
    }
}

function Test-SetupPrerequisites {
    $valid = $true

    if (-not (Test-Path "features.txt" -PathType Leaf)) {
        Add-FailedInstallation -Package "Windows Features" -Reason "features.txt not found"
        $valid = $false
    }

    if (-not (Test-Path "chocolatey.config" -PathType Leaf)) {
        Add-FailedInstallation -Package "Chocolatey packages" -Reason "chocolatey.config not found"
        $valid = $false
    } else {
        try {
            [xml]$null = Get-Content -Path "chocolatey.config" -Raw
        } catch {
            Add-FailedInstallation -Package "Chocolatey Config Validation" -Reason $_.Exception.Message
            $valid = $false
        }
    }

    return $valid
}

function Install-With-Choco {
    param(
        [Parameter(Mandatory=$true)][string]$Package,
        [string]$Version
    )

    Write-Output "Starting install of $Package at $(Get-Date -Format 'MM/dd/yyyy HH:mm')"

    $installSucceeded = Invoke-WithRetry -Description "choco install $Package" -Action {
        if ([string]::IsNullOrWhiteSpace($Version)) {
            choco install $Package -y --source=$script:chocoRepo --ignore-checksums
        } else {
            choco install $Package -y --source=$script:chocoRepo --version $Version --ignore-checksums
        }

        $exitCode = $LASTEXITCODE
        $validExitCodes = @(0, 1605, 1614, 1641, 3010)
        if ($validExitCodes -notcontains $exitCode) {
            throw "Exit code $exitCode"
        }
    }

    if (-not $installSucceeded) {
        Add-FailedInstallation -Package $Package -Reason "Chocolatey install failed"
        return $false
    }

    return $true
}

function Install-Optional-Feature {
    param(
        [Parameter(Mandatory=$true)][string]$Feature
    )

    Write-Output "Starting install of feature $Feature at $(Get-Date -Format 'MM/dd/yyyy HH:mm')"
    $featureSucceeded = Invoke-WithRetry -Description "Install optional feature $Feature" -Action {
        choco install $Feature --source windowsfeatures -y
    }

    if (-not $featureSucceeded) {
        Add-FailedInstallation -Package "Feature: $Feature" -Reason "Feature install failed"
        return $false
    }

    return $true
}

function Install-PIP {
    if (-not (Test-Path "requirements.txt" -PathType Leaf)) {
        Write-Output "requirements.txt not found, skipping Python package installation"
        return $true
    }

    if (-not (Get-Command pip -ErrorAction SilentlyContinue)) {
        Add-FailedInstallation -Package "Python packages" -Reason "pip command not found"
        return $false
    }

    $pipSucceeded = Invoke-WithRetry -Description "Install Python requirements" -Action {
        pip install -r requirements.txt
    }

    if (-not $pipSucceeded) {
        Add-FailedInstallation -Package "Python packages" -Reason "pip install failed"
        return $false
    }

    return $true
}

function Install-Gemfile {
    if (-not (Test-Path "Gemfile" -PathType Leaf)) {
        Write-Output "Gemfile not found, skipping Ruby gems installation"
        return $true
    }

    if (-not (Get-Command bundle -ErrorAction SilentlyContinue)) {
        Add-FailedInstallation -Package "Ruby gems" -Reason "bundle command not found"
        return $false
    }

    $bundleSucceeded = Invoke-WithRetry -Description "Install Ruby gems" -Action {
        bundle install
    }

    if (-not $bundleSucceeded) {
        Add-FailedInstallation -Package "Ruby gems" -Reason "bundle install failed"
        return $false
    }

    return $true
}

function Enable-HyperV {
    return (Install-Optional-Feature -Feature "Microsoft-Hyper-V")
}

function Install-Windows-Update {
    $updateSucceeded = Invoke-WithRetry -Description "Install Windows updates" -Action {
        $service = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
        if ($null -eq $service) {
            throw "Windows Update service does not exist"
        }

        if ($service.StartType -eq "Disabled") {
            Set-Service -Name $service.Name -StartupType Automatic -Force
        }

        if ($service.Status -eq "Stopped") {
            Start-Service -Name $service.Name
        }

        Install-Module PSWindowsUpdate -Force
        Get-WindowsUpdate -AcceptAll
        Install-WindowsUpdate -MicrosoftUpdate -IgnoreReboot -AcceptAll
    }

    if (-not $updateSucceeded) {
        Add-FailedInstallation -Package "Windows Updates" -Reason "Windows update stage failed"
        return $false
    }

    return $true
}

function Install-Chocolatey {
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Output "Chocolatey is already installed."
        return $true
    }

    $chocoSucceeded = Invoke-WithRetry -Description "Install Chocolatey" -Action {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
    }

    if (-not $chocoSucceeded) {
        Add-FailedInstallation -Package "Chocolatey" -Reason "Chocolatey install failed"
        return $false
    }

    return $true
}

function Initialize-Workspace {
    if (Test-Path "c:\workspace") {
        return $true
    }

    $workspaceSucceeded = Invoke-WithRetry -Description "Create workspace directory" -Action {
        New-Item -Path "c:\" -Name "workspace" -ItemType "Directory" | Out-Null
    }

    if (-not $workspaceSucceeded) {
        Add-FailedInstallation -Package "Workspace directory" -Reason "Workspace directory creation failed"
        return $false
    }

    return $true
}

function Install-WindowsFeatures {
    $allSucceeded = $true
    $features = Get-Content features.txt
    foreach ($feature in $features) {
        if ([string]::IsNullOrWhiteSpace($feature)) {
            continue
        }

        if (-not (Install-Optional-Feature -Feature $feature)) {
            $allSucceeded = $false
        }
    }

    return $allSucceeded
}

function Set-EditionPackages {
    $script:windowsCaption = (Get-CimInstance -ClassName Win32_OperatingSystem).Caption
    Write-Output "Detecting Windows edition: $script:windowsCaption"

    switch ($script:windowsCaption) {
        { $_.Contains("Home") } {
            $script:vsPackage = "visualstudio2022community"
            $script:officePackage = "office365homepremium"
        }
        { $_.Contains("Business") } {
            $script:vsPackage = "visualstudio2022professional"
            $script:officePackage = "office365business"
            Enable-HyperV | Out-Null
        }
        { $_.Contains("Enterprise") } {
            $script:vsPackage = "visualstudio2022enterprise"
            $script:officePackage = "office365business"
            Enable-HyperV | Out-Null
        }
        Default {
            $script:vsPackage = "visualstudio2022community"
            $script:officePackage = ""
        }
    }
}

function Install-ChocolateyConfigPackages {
    [xml]$xmlContent = Get-Content -Path "chocolatey.config" -Raw
    if ($null -eq $xmlContent.packages -or $null -eq $xmlContent.packages.package) {
        throw "No package nodes were found in chocolatey.config"
    }

    $configSucceeded = Invoke-WithRetry -Description "Install chocolatey.config" -Action {
        choco install chocolatey.config --source=$script:chocoRepo --ignore-checksums -y
    }

    if (-not $configSucceeded) {
        Add-FailedInstallation -Package "Chocolatey packages (config)" -Reason "Config package install failed"
        return $false
    }

    return $true
}

function Install-EditionPackages {
    $allSucceeded = $true

    if (-not [string]::IsNullOrWhiteSpace($script:vsPackage)) {
        if (-not (Install-With-Choco -Package $script:vsPackage)) {
            $allSucceeded = $false
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($script:officePackage)) {
        if (-not (Install-With-Choco -Package $script:officePackage)) {
            $allSucceeded = $false
        }
    }

    return $allSucceeded
}

function Show-SetupSummary {
    Write-Output "`nInstallation Summary"
    Write-Output "===================="

    Write-Output "`nOperation State Summary"
    Write-Output "-----------------------"
    foreach ($operation in $script:operationStates) {
        if ([string]::IsNullOrWhiteSpace($operation.Message)) {
            Write-Output ("{0} [{1}]" -f $operation.Operation, $operation.State)
        } else {
            Write-Output ("{0} [{1}] - {2}" -f $operation.Operation, $operation.State, $operation.Message)
        }
    }

    if ($script:failedInstallations.Count -gt 0) {
        Write-Output "`nFailed Installations:"
        Write-Output "---------------------"
        $script:failedInstallations | Format-Table -Property @{Label="Package"; Expression={$_.Package}}, @{Label="Reason"; Expression={$_.Reason}} -AutoSize -Wrap
        Write-Output "`nSetup completed with some failures."
        return $false
    }

    Write-Output "`nAll applications were installed successfully!"
    return $true
}

$transcriptStarted = $false

try {
    if (-not $ValidateOnly) {
        $username = Get-Content env:username
        $computer = Get-Content env:computername
        $logFile = "C:\$computer-$username-$(Get-Date -Format 'MM-dd-yyyy-HH-mm')-install.log"
        Start-Transcript -Path $logFile -Append
        $transcriptStarted = $true

        New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1 -PropertyType DWORD -Force | Out-Null
    }

    Invoke-Stage -StageName "preflight-validation" -Action {
        if (-not (Test-SetupPrerequisites)) {
            throw "Preflight validation failed"
        }
    } | Out-Null

    if ($ValidateOnly) {
        if (-not (Show-SetupSummary)) {
            exit 1
        }
        exit 0
    }

    Invoke-Stage -StageName "bootstrap" -Action {
        if (-not (Install-Chocolatey)) { throw "Chocolatey bootstrap failed" }
        if (-not (Initialize-Workspace)) { throw "Workspace setup failed" }
    } | Out-Null

    Invoke-Stage -StageName "feature-installation" -Action {
        if (-not (Install-WindowsFeatures)) { throw "One or more Windows features failed" }
    } | Out-Null

    Invoke-Stage -StageName "package-installation" -Action {
        if (-not (Install-ChocolateyConfigPackages)) { throw "Chocolatey config package installation failed" }
    } | Out-Null

    Invoke-Stage -StageName "edition-packages" -Action {
        Set-EditionPackages
        if (-not (Install-EditionPackages)) { throw "Edition-specific package installation failed" }
    } | Out-Null

    Invoke-Stage -StageName "language-dependencies" -Action {
        if (-not (Install-PIP)) { throw "Python dependency installation failed" }
        if (-not (Install-Gemfile)) { throw "Ruby dependency installation failed" }
    } | Out-Null

    Invoke-Stage -StageName "post-checks" -Action {
        if ($script:windowsUpdate -and -not (Install-Windows-Update)) {
            throw "Windows update stage failed"
        }
    } | Out-Null

    if (-not (Show-SetupSummary)) {
        exit 1
    }

    Write-Output "`nSetup completed!"
} finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
