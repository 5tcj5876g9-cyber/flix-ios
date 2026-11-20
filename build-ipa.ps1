# Builds the iOS app into an unsigned .ipa using a free GitHub macOS runner.
#
#   pwsh -NoProfile -File build-ipa.ps1            # create/push repo, run Actions, fetch ipa
#   pwsh -NoProfile -File build-ipa.ps1 -RepoName flix-ios-ipa
#
# Needs: git, gh. One-time: gh auth login   (choose GitHub.com -> HTTPS -> browser)
# Output: <Desktop>\Flix-unsigned.ipa  plus SHA-256 so the file can be verified.

[CmdletBinding()]
param(
    [string]$RepoName = 'flix-ios-ipa',
    [string]$Private = 'true'
)

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$desktop = [Environment]::GetFolderPath('Desktop')

function Assert-Tool([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name is not installed or not on PATH."
    }
}

Assert-Tool 'git'
Assert-Tool 'gh'

$authState = (& gh auth status 2>&1 | Out-String)
if ($authState -match 'not logged into any GitHub hosts') {
    throw "Not signed in to GitHub. Run:  gh auth login   then re-run this script."
}

$owner = (& gh api user --jq .login).Trim()
if (-not $owner) { throw "Could not read the GitHub account from gh." }
Write-Host "GitHub account: $owner" -ForegroundColor Cyan

# The repo root is this folder: project.yml + Flix/ + .github/workflows/ipa.yml.
Push-Location $projectDir
try {
    if (-not (Test-Path (Join-Path $projectDir '.git'))) {
        & git init --initial-branch=main | Out-Null
    }

    $gitignore = @'
build/
DerivedData/
*.xcodeproj/
*.xcworkspace/
.DS_Store
'@
    if (-not (Test-Path (Join-Path $projectDir '.gitignore'))) {
        Set-Content -Path (Join-Path $projectDir '.gitignore') -Value $gitignore -Encoding ascii
    }

    & git add -A | Out-Null
    $pending = (& git status --porcelain | Out-String).Trim()
    if ($pending) {
        & git -c user.name="flix" -c user.email="flix@local" commit -m "iOS shell: offline downloads, in-frame media sniffer, app icons" | Out-Null
        Write-Host "Committed local changes." -ForegroundColor Cyan
    }

    # Create the repo only when it does not exist yet.
    $exists = $false
    & gh repo view "$owner/$RepoName" --json name 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $exists = $true }

    if (-not $exists) {
        $visibility = if ($Private -eq 'true') { '--private' } else { '--public' }
        & gh repo create "$RepoName" $visibility --source=. --remote=origin --push
        if ($LASTEXITCODE -ne 0) { throw "gh repo create failed." }
        Write-Host "Created $owner/$RepoName" -ForegroundColor Green
    } else {
        if (-not ((& git remote) -match '^origin$')) {
            & git remote add origin "https://github.com/$owner/$RepoName.git"
        }
        & git push -u origin main
        if ($LASTEXITCODE -ne 0) { throw "git push failed." }
    }

    Write-Host "Triggering the ipa workflow..." -ForegroundColor Cyan
    & gh workflow run ipa.yml --ref main
    if ($LASTEXITCODE -ne 0) { throw "Could not trigger ipa.yml - is Actions enabled on the repo?" }

    # Give GitHub a moment to register the run, then find it.
    Start-Sleep -Seconds 12
    $runId = $null
    for ($i = 0; $i -lt 10; $i++) {
        $runId = (& gh run list --workflow=ipa.yml --limit 1 --json databaseId --jq '.[0].databaseId' 2>$null)
        if ($runId) { break }
        Start-Sleep -Seconds 6
    }
    if (-not $runId) { throw "No workflow run found. Open https://github.com/$owner/$RepoName/actions" }

    Write-Host "Watching run $runId (a macOS build is ~5 minutes)..." -ForegroundColor Cyan
    & gh run watch $runId --exit-status --interval 20
    if ($LASTEXITCODE -ne 0) { throw "The workflow failed. Logs: https://github.com/$owner/$RepoName/actions/runs/$runId" }

    $outDir = Join-Path $env:TEMP "flix-ipa-$runId"
    Remove-Item $outDir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $outDir | Out-Null

    Write-Host "Downloading artifact..." -ForegroundColor Cyan
    & gh run download $runId --name Flix-unsigned-ipa --dir $outDir
    if ($LASTEXITCODE -ne 0) { throw "Artifact download failed." }

    $ipa = Get-ChildItem $outDir -Filter '*.ipa' -Recurse | Select-Object -First 1
    if (-not $ipa) { throw "No .ipa inside the artifact." }

    $target = Join-Path $desktop 'Flix-unsigned.ipa'
    Copy-Item $ipa.FullName $target -Force

    $hash = (Get-FileHash $target -Algorithm SHA256).Hash
    $sizeMb = [math]::Round((Get-Item $target).Length / 1MB, 2)

    Write-Host ""
    Write-Host "IPA ready: $target" -ForegroundColor Green
    Write-Host "Size: $sizeMb MB   SHA-256: $hash"
    Write-Host ""
    Write-Host "Next: sign it with Sideloadly and a free Apple ID (7-day certificate)." -ForegroundColor Yellow
    Write-Host "  1. Open Sideloadly, drag $target in, sign in with your Apple ID."
    Write-Host "  2. Enter the Apple ID password in the app-specific box, Start."
    Write-Host "  3. On the phone: Settings > General > VPN & Device Management > trust the profile."
}
finally {
    Pop-Location
}
