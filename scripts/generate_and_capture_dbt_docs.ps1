<#
Generate dbt docs and capture portfolio screenshots.

Run from the repository root:
  powershell -ExecutionPolicy Bypass -File scripts/generate_and_capture_dbt_docs.ps1

Use metadata-only mode while Snowflake connection details are being fixed:
  powershell -ExecutionPolicy Bypass -File scripts/generate_and_capture_dbt_docs.ps1 -EmptyCatalog
#>

param(
    [string]$dbtProjectPath = "dbt/github_dbt",
    [int]$port = 8000,
    [string]$outputFolder = "docs/screenshots",
    [switch]$EmptyCatalog
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$repoRoot = (Resolve-Path (Join-Path $scriptRoot "..")).Path
$profilesDir = Join-Path $repoRoot "dbt"

function Resolve-RepoPath {
    param([string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return (Resolve-Path $PathValue).Path
    }

    return (Resolve-Path (Join-Path $repoRoot $PathValue)).Path
}

function Import-DotEnv {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        Write-Warning ".env file not found at $Path. dbt will rely on existing environment variables."
        return
    }

    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
            $parts = $line.Split("=", 2)
            $key = $parts[0].Trim()
            $value = $parts[1].Trim()

            if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
                ($value.StartsWith("'") -and $value.EndsWith("'"))) {
                $value = $value.Substring(1, $value.Length - 2)
            }

            Set-Item -Path "Env:$key" -Value $value
        }
    }
}

function Get-DbtExecutable {
    $candidates = @(
        (Join-Path $repoRoot ".venv\Scripts\dbt.exe"),
        (Join-Path $repoRoot "venv\Scripts\dbt.exe"),
        "C:\Users\abdul\AppData\Local\Programs\Python\Python312\Scripts\dbt.exe",
        "C:\Users\abdul\AppData\Local\Programs\Python\Python311\Scripts\dbt.exe",
        "C:\Program Files\Python312\Scripts\dbt.exe",
        "C:\Program Files\Python311\Scripts\dbt.exe"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    $fromPath = Get-Command dbt -ErrorAction SilentlyContinue
    if ($fromPath) {
        return $fromPath.Source
    }

    throw "dbt executable not found. Activate the venv or install dependencies with pip install -r requirements.txt."
}

function Get-BrowserExecutable {
    $commands = @(
        (Get-Command chrome -ErrorAction SilentlyContinue),
        (Get-Command chrome.exe -ErrorAction SilentlyContinue),
        (Get-Command msedge -ErrorAction SilentlyContinue),
        (Get-Command msedge.exe -ErrorAction SilentlyContinue)
    ) | Where-Object { $_ }

    $candidates = @(
        "C:\Program Files\Google\Chrome\Application\chrome.exe",
        "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
        "C:\Program Files\Microsoft\Edge\Application\msedge.exe",
        "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
    ) + ($commands | ForEach-Object { $_.Source })

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    throw "Chrome or Edge was not found. Install one browser or capture screenshots manually from dbt docs serve."
}

$dbtProjectFullPath = Resolve-RepoPath $dbtProjectPath
$outputFullPath = Join-Path $repoRoot $outputFolder
New-Item -ItemType Directory -Path $outputFullPath -Force | Out-Null

Import-DotEnv -Path (Join-Path $repoRoot ".env")

$dbtExe = Get-DbtExecutable
$browserExe = Get-BrowserExecutable
$serveProc = $null

Write-Host "Using dbt executable: $dbtExe"
Write-Host "Using dbt profiles directory: $profilesDir"
Write-Host "Writing screenshots to: $outputFullPath"

Push-Location $dbtProjectFullPath

try {
    if (Test-Path "packages.yml") {
        Write-Host "Installing dbt package dependencies..."
        & $dbtExe deps --profiles-dir $profilesDir
        if ($LASTEXITCODE -ne 0) {
            throw "dbt deps failed with exit code $LASTEXITCODE"
        }
    }

    if ($EmptyCatalog) {
        Write-Warning "EmptyCatalog mode enabled: skipping dbt debug connection test and generating docs without warehouse catalog metadata."
        Write-Host "Parsing project to create manifest.json..."
        & $dbtExe parse --profiles-dir $profilesDir
        if ($LASTEXITCODE -ne 0) {
            throw "dbt parse failed with exit code $LASTEXITCODE"
        }
    }
    else {
        Write-Host "Validating dbt profile and Snowflake connection..."
        & $dbtExe debug --profiles-dir $profilesDir
        if ($LASTEXITCODE -ne 0) {
            throw "dbt debug failed with exit code $LASTEXITCODE"
        }
    }

    Write-Host "Generating dbt documentation artifacts..."
    $docsArgs = @("docs", "generate", "--profiles-dir", $profilesDir, "--static")
    if ($EmptyCatalog) {
        $docsArgs += @("--empty-catalog", "--no-compile", "--no-populate-cache")
    }

    & $dbtExe @docsArgs
    if ($LASTEXITCODE -ne 0) {
        throw "dbt docs generate failed with exit code $LASTEXITCODE"
    }

    $staticIndex = Join-Path $dbtProjectFullPath "target\static_index.html"
    if (Test-Path $staticIndex) {
        $baseUrl = ([System.Uri]$staticIndex).AbsoluteUri
        Write-Host "Capturing screenshots from static docs: $baseUrl"
    }
    else {
        Write-Host "Starting dbt docs serve on port $port..."
        $serveArgs = @("docs", "serve", "--profiles-dir", $profilesDir, "--host", "127.0.0.1", "--port", $port.ToString(), "--no-browser")
        $serveProc = Start-Process -FilePath $dbtExe -ArgumentList $serveArgs -WorkingDirectory $dbtProjectFullPath -WindowStyle Hidden -PassThru

        $baseUrl = "http://127.0.0.1:$port/"
        $ready = $false
        for ($i = 0; $i -lt 15; $i++) {
            try {
                Invoke-WebRequest -UseBasicParsing -Uri $baseUrl -TimeoutSec 1 | Out-Null
                $ready = $true
                break
            }
            catch {
                Start-Sleep -Seconds 1
            }
        }

        if (-not $ready) {
            throw "dbt docs server did not become ready at $baseUrl"
        }
    }

    $screens = @(
        @{ Route = "#!/overview"; File = "dbt-lineage.png" },
        @{ Route = "#!/model/model.github_dbt.fact_events"; File = "dbt-fact_events.png" },
        @{ Route = "#!/model/model.github_dbt.dim_actor"; File = "dbt-dim_actor.png" }
    )

    foreach ($screen in $screens) {
        $url = "$baseUrl$($screen.Route)"
        $out = Join-Path -Path $outputFullPath -ChildPath $screen.File
        Write-Host "Capturing $url -> $out"
        & $browserExe --headless --disable-gpu --allow-file-access-from-files --hide-scrollbars --virtual-time-budget=5000 --screenshot="$out" --window-size=1600,900 "$url"
        if ($LASTEXITCODE -ne 0) {
            throw "Screenshot capture failed for $url with exit code $LASTEXITCODE"
        }
    }

    Write-Host "dbt docs artifacts and screenshots generated successfully."
}
finally {
    if ($serveProc -and -not $serveProc.HasExited) {
        Write-Host "Stopping dbt docs serve (PID $($serveProc.Id))"
        $serveProc | Stop-Process -Force
    }

    Pop-Location
}

exit 0
