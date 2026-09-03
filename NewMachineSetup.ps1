param(
    [switch]$ValidateOnly,
    [switch]$IQOnly,
    [switch]$OQOnly,
    [switch]$PQOnly,
    [switch]$SkipElevation,
    [switch]$DryRun,
    [switch]$WindowsUpdate,
    [int]$MaxRetries = 2
)

$ErrorActionPreference = "Stop"
$script:QualificationOnlyMode = $ValidateOnly.IsPresent -or $IQOnly.IsPresent -or $OQOnly.IsPresent -or $PQOnly.IsPresent
$script:minRamMB = 4096
$script:minDiskMB = 10240
$script:minAvailableMemoryMB = 512
$script:packageManagerThresholdSeconds = 5.0
$script:networkThresholdSeconds = 5
$script:diskWriteMbpsMin = 5.0

function Get-EnvIntValue {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][int]$DefaultValue
    )

    $value = (Get-Item -Path "Env:$Name" -ErrorAction SilentlyContinue).Value
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $DefaultValue
    }

    return [int]$value
}

function Get-EnvDoubleValue {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][double]$DefaultValue
    )

    $value = (Get-Item -Path "Env:$Name" -ErrorAction SilentlyContinue).Value
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $DefaultValue
    }

    return [double]$value
}

function Test-IsCIEnvironment {
    return $env:CI -eq "true" -or $env:GITHUB_ACTIONS -eq "true"
}

$script:minRamMB = Get-EnvIntValue -Name "NMB_MIN_RAM_MB" -DefaultValue $script:minRamMB
$script:minDiskMB = Get-EnvIntValue -Name "NMB_MIN_DISK_MB" -DefaultValue $script:minDiskMB
$script:minAvailableMemoryMB = Get-EnvIntValue -Name "NMB_MIN_AVAILABLE_MEMORY_MB" -DefaultValue $script:minAvailableMemoryMB
$script:networkThresholdSeconds = Get-EnvIntValue -Name "NMB_NETWORK_THRESHOLD_SECONDS" -DefaultValue $script:networkThresholdSeconds
$script:packageManagerThresholdSeconds = Get-EnvDoubleValue -Name "NMB_PACKAGE_MANAGER_THRESHOLD_SECONDS" -DefaultValue $script:packageManagerThresholdSeconds
$script:diskWriteMbpsMin = Get-EnvDoubleValue -Name "NMB_DISK_WRITE_MBPS_MIN" -DefaultValue $script:diskWriteMbpsMin

if (-not $script:QualificationOnlyMode) {
    try {
        Clear-Host
    } catch {
        Write-Verbose "Skipping Clear-Host because the current host UI does not support it."
    }
}

if (-not $script:QualificationOnlyMode -and -not $SkipElevation) {
    if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        $argumentList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath)
        if ($DryRun) { $argumentList += "-DryRun" }
        if ($WindowsUpdate) { $argumentList += "-WindowsUpdate" }
        $argumentList += @("-MaxRetries", $MaxRetries)
        Start-Process powershell.exe -ArgumentList $argumentList -Verb RunAs
        exit
    }
}

$script:chocoRepo = "https://community.chocolatey.org/api/v2/"
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

function Get-CommandIfAvailable {
    param([Parameter(Mandatory=$true)][string]$Name)

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        return $null
    }

    return $command
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

    $failureCount = $script:failedInstallations.Count
    Set-OperationState -Operation $StageName -State "planned"
    Set-OperationState -Operation $StageName -State "running"

    try {
        $result = & $Action
        if ($false -eq $result -or $script:failedInstallations.Count -gt $failureCount) {
            Set-OperationState -Operation $StageName -State "failed"
            return $false
        }

        Set-OperationState -Operation $StageName -State "succeeded"
        return $true
    } catch {
        Set-OperationState -Operation $StageName -State "failed" -Message $_.Exception.Message
        Add-FailedInstallation -Package $StageName -Reason $_.Exception.Message
        return $false
    }
}

function Test-Connectivity {
    param([Parameter(Mandatory=$true)][string]$Uri)

    try {
        Invoke-WebRequest -Method Head -Uri $Uri -TimeoutSec $script:networkThresholdSeconds | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Measure-CommandSeconds {
    param(
        [Parameter(Mandatory=$true)][string]$CommandName,
        [string[]]$Arguments = @()
    )

    $LASTEXITCODE = 0
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        & $CommandName @Arguments | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "$CommandName exited with code $LASTEXITCODE"
        }
    } finally {
        $stopwatch.Stop()
    }

    return [Math]::Round($stopwatch.Elapsed.TotalSeconds, 2)
}

function Measure-UrlSeconds {
    param([Parameter(Mandatory=$true)][string]$Uri)

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        Invoke-WebRequest -Method Head -Uri $Uri -TimeoutSec $script:networkThresholdSeconds | Out-Null
    } finally {
        $stopwatch.Stop()
    }

    return [Math]::Round($stopwatch.Elapsed.TotalSeconds, 2)
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

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        if (-not $os.Caption.Contains("Windows")) {
            Add-FailedInstallation -Package "preflight-validation" -Reason "unsupported operating system"
            $valid = $false
        }
    } catch {
        Add-FailedInstallation -Package "preflight-validation" -Reason "unable to determine operating system"
        $valid = $false
    }

    try {
        $system = Get-CimInstance -ClassName Win32_ComputerSystem
        $ramMB = [int]($system.TotalPhysicalMemory / 1MB)
        if ($ramMB -lt $script:minRamMB) {
            Add-FailedInstallation -Package "preflight-validation" -Reason "insufficient RAM ${ramMB}MB"
            $valid = $false
        }
    } catch {
        Add-FailedInstallation -Package "preflight-validation" -Reason "unable to determine RAM"
        $valid = $false
    }

    try {
        $drive = Get-PSDrive -Name C
        $diskMB = [int]($drive.Free / 1MB)
        if ($diskMB -lt $script:minDiskMB) {
            Add-FailedInstallation -Package "preflight-validation" -Reason "insufficient disk ${diskMB}MB"
            $valid = $false
        }
    } catch {
        Add-FailedInstallation -Package "preflight-validation" -Reason "unable to determine free disk"
        $valid = $false
    }

    foreach ($endpoint in @($script:chocoRepo, "https://pypi.org/simple/", "https://rubygems.org")) {
        if (-not (Test-Connectivity -Uri $endpoint)) {
            $sanitized = $endpoint -replace "https?://", "" -replace "[^A-Za-z0-9]", "_"
            Add-FailedInstallation -Package "preflight-validation" -Reason "network unreachable $sanitized"
            $valid = $false
        }
    }

    return $valid
}

function Invoke-IQStage {
    $success = $true
    $choco = Get-CommandIfAvailable -Name "choco"

    if ($null -ne $choco) {
        try {
            Get-FileHash -Path $choco.Source -Algorithm SHA256 | Out-Null
        } catch {
            Add-FailedInstallation -Package "IQ" -Reason "chocolatey checksum failed"
            $success = $false
        }
    } elseif ($script:QualificationOnlyMode) {
        Add-FailedInstallation -Package "IQ" -Reason "Chocolatey not installed"
        $success = $false
    } else {
        Write-Output "Chocolatey is not installed yet; bootstrap will install it."
    }

    foreach ($tool in @("git", "python", "pip", "bundle")) {
        $command = Get-CommandIfAvailable -Name $tool
        if ($null -ne $command) {
            try {
                Get-FileHash -Path $command.Source -Algorithm SHA256 | Out-Null
            } catch {
                Add-FailedInstallation -Package "IQ" -Reason "$tool checksum failed"
                $success = $false
            }
        } elseif ($script:QualificationOnlyMode) {
            Add-FailedInstallation -Package "IQ" -Reason "$tool not installed"
            $success = $false
        } else {
            Write-Output "$tool is not installed yet; later stages may provision it."
        }
    }

    return $success
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
    param([Parameter(Mandatory=$true)][string]$Feature)

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
            $service = Get-Service -Name $service.Name
        }

        if ($service.Status -eq "Stopped") {
            Start-Service -Name $service.Name
        }

        Install-Module PSWindowsUpdate -Force -Confirm:$false -Scope CurrentUser
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
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
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
    if (Test-IsCIEnvironment) {
        Write-Output "Skipping chocolatey.config bulk install in CI."
        return $true
    }

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
    if (Test-IsCIEnvironment) {
        Write-Output "Skipping edition package installs in CI."
        return $true
    }

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

function Invoke-OQStage {
    $success = $true

    if (Get-Command choco -ErrorAction SilentlyContinue) {
        try {
            choco --version | Out-Null
            choco source list | Out-Null
            choco uninstall --help | Out-Null
        } catch {
            Add-FailedInstallation -Package "OQ" -Reason "Chocolatey is not operational"
            $success = $false
        }
    } else {
        Add-FailedInstallation -Package "OQ" -Reason "Chocolatey not available"
        $success = $false
    }

    if (Get-Command python -ErrorAction SilentlyContinue) {
        try {
            python --version | Out-Null
        } catch {
            Add-FailedInstallation -Package "OQ" -Reason "Python is not operational"
            $success = $false
        }
    } else {
        Add-FailedInstallation -Package "OQ" -Reason "Python not available"
        $success = $false
    }

    if (Get-Command pip -ErrorAction SilentlyContinue) {
        try {
            pip --version | Out-Null
            pip check | Out-Null
            pip uninstall --help | Out-Null
            if (Test-Path "requirements.txt" -PathType Leaf) {
                pip install --dry-run -r requirements.txt | Out-Null
            }
        } catch {
            Add-FailedInstallation -Package "OQ" -Reason "pip dependency validation failed"
            $success = $false
        }
    } else {
        Add-FailedInstallation -Package "OQ" -Reason "pip not available"
        $success = $false
    }

    if (Get-Command bundle -ErrorAction SilentlyContinue) {
        try {
            bundle --version | Out-Null
            bundle check | Out-Null
            if (Get-Command gem -ErrorAction SilentlyContinue) {
                gem uninstall --help | Out-Null
            }
        } catch {
            Add-FailedInstallation -Package "OQ" -Reason "bundle dependency validation failed"
            $success = $false
        }
    } elseif (Test-Path "Gemfile" -PathType Leaf) {
        Add-FailedInstallation -Package "OQ" -Reason "bundle not available"
        $success = $false
    }

    if (-not (Test-Connectivity -Uri $script:chocoRepo)) {
        Add-FailedInstallation -Package "OQ" -Reason "Chocolatey repository unreachable"
        $success = $false
    }

    return $success
}

function Invoke-PQStage {
    $success = $true

    if (Get-Command choco -ErrorAction SilentlyContinue) {
        try {
            $seconds = Measure-CommandSeconds -CommandName "choco" -Arguments @("--version")
            if ($seconds -gt $script:packageManagerThresholdSeconds) {
                Add-FailedInstallation -Package "PQ" -Reason "Chocolatey response too slow ${seconds}s"
                $success = $false
            }
        } catch {
            Add-FailedInstallation -Package "PQ" -Reason "Chocolatey response measurement failed"
            $success = $false
        }
    } else {
        Add-FailedInstallation -Package "PQ" -Reason "Chocolatey not available"
        $success = $false
    }

    if (Get-Command pip -ErrorAction SilentlyContinue) {
        try {
            $seconds = Measure-CommandSeconds -CommandName "pip" -Arguments @("--version")
            if ($seconds -gt $script:packageManagerThresholdSeconds) {
                Add-FailedInstallation -Package "PQ" -Reason "pip response too slow ${seconds}s"
                $success = $false
            }
        } catch {
            Add-FailedInstallation -Package "PQ" -Reason "pip response measurement failed"
            $success = $false
        }
    }

    try {
        $tempFile = Join-Path $env:TEMP ("newmachinebuild-" + [guid]::NewGuid().ToString() + ".bin")
        $buffer = New-Object byte[] (8 * 1MB)
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        [System.IO.File]::WriteAllBytes($tempFile, $buffer)
        $stopwatch.Stop()
        if ($stopwatch.Elapsed.TotalSeconds -gt 0) {
            $mbps = [Math]::Round(8 / $stopwatch.Elapsed.TotalSeconds, 2)
            if ($mbps -lt $script:diskWriteMbpsMin) {
                Add-FailedInstallation -Package "PQ" -Reason "Disk write below threshold ${mbps}MBps"
                $success = $false
            }
        }
        Remove-Item $tempFile -ErrorAction SilentlyContinue
    } catch {
        Add-FailedInstallation -Package "PQ" -Reason "disk IO test failed"
        $success = $false
    }

    try {
        $seconds = Measure-UrlSeconds -Uri $script:chocoRepo
        if ($seconds -gt $script:networkThresholdSeconds) {
            Add-FailedInstallation -Package "PQ" -Reason "network response too slow ${seconds}s"
            $success = $false
        }
    } catch {
        Add-FailedInstallation -Package "PQ" -Reason "network measurement failed"
        $success = $false
    }

    try {
        $availableMemory = (Get-Counter '\Memory\Available MBytes').CounterSamples[0].CookedValue
        if ($availableMemory -lt $script:minAvailableMemoryMB) {
            Add-FailedInstallation -Package "PQ" -Reason "available memory below threshold ${availableMemory}MB"
            $success = $false
        }
    } catch {
        Add-FailedInstallation -Package "PQ" -Reason "resource utilization measurement failed"
        $success = $false
    }

    return $success
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
    if (-not $script:QualificationOnlyMode) {
        $username = Get-Content env:username
        $computer = Get-Content env:computername
        $logFile = "C:\$computer-$username-$(Get-Date -Format 'MM-dd-yyyy-HH-mm')-install.log"
        Start-Transcript -Path $logFile -Append
        $transcriptStarted = $true

        New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1 -PropertyType DWORD -Force | Out-Null
    }

    $preflightPassed = Invoke-Stage -StageName "preflight-validation" -Action {
        Test-SetupPrerequisites
    }

    if (-not $script:QualificationOnlyMode -and -not $preflightPassed) {
        Show-SetupSummary | Out-Null
        exit 1
    }

    if ($IQOnly) {
        Invoke-Stage -StageName "IQ" -Action { Invoke-IQStage } | Out-Null
        if (-not (Show-SetupSummary)) { exit 1 }
        exit 0
    }

    if ($OQOnly) {
        Invoke-Stage -StageName "OQ" -Action { Invoke-OQStage } | Out-Null
        if (-not (Show-SetupSummary)) { exit 1 }
        exit 0
    }

    if ($PQOnly) {
        Invoke-Stage -StageName "PQ" -Action { Invoke-PQStage } | Out-Null
        if (-not (Show-SetupSummary)) { exit 1 }
        exit 0
    }

    if ($ValidateOnly) {
        Invoke-Stage -StageName "IQ" -Action { Invoke-IQStage } | Out-Null
        Invoke-Stage -StageName "OQ" -Action { Invoke-OQStage } | Out-Null
        Invoke-Stage -StageName "PQ" -Action { Invoke-PQStage } | Out-Null
        Invoke-Stage -StageName "post-checks" -Action { $true } | Out-Null
        if (-not (Show-SetupSummary)) { exit 1 }
        exit 0
    }

    Invoke-Stage -StageName "IQ" -Action { Invoke-IQStage } | Out-Null

    Invoke-Stage -StageName "bootstrap" -Action {
        if (-not (Install-Chocolatey)) { return $false }
        if (-not (Initialize-Workspace)) { return $false }
        return $true
    } | Out-Null

    Invoke-Stage -StageName "package-installation" -Action {
        Set-EditionPackages
        $allSucceeded = $true
        if (-not (Install-WindowsFeatures)) { $allSucceeded = $false }
        if (-not (Install-ChocolateyConfigPackages)) { $allSucceeded = $false }
        if (-not (Install-EditionPackages)) { $allSucceeded = $false }
        return $allSucceeded
    } | Out-Null

    Invoke-Stage -StageName "OQ" -Action { Invoke-OQStage } | Out-Null

    Invoke-Stage -StageName "language-dependencies" -Action {
        $allSucceeded = $true
        if (-not (Install-PIP)) { $allSucceeded = $false }
        if (-not (Install-Gemfile)) { $allSucceeded = $false }
        return $allSucceeded
    } | Out-Null

    Invoke-Stage -StageName "PQ" -Action { Invoke-PQStage } | Out-Null

    Invoke-Stage -StageName "post-checks" -Action {
        if ($script:windowsUpdate -and -not (Install-Windows-Update)) {
            return $false
        }
        return $true
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
