param(
    [switch]$ConfigOnly
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$stub = Join-Path $env:USERPROFILE '.wezterm.lua'

function Find-WezTerm {
    $candidates = @()
    $command = Get-Command wezterm.exe -ErrorAction SilentlyContinue
    if ($command) {
        $candidates += $command.Source
    }
    $candidates += (Join-Path $env:ProgramFiles 'WezTerm\wezterm.exe')
    if (${env:ProgramFiles(x86)}) {
        $candidates += (Join-Path ${env:ProgramFiles(x86)} 'WezTerm\wezterm.exe')
    }
    $candidates += (Join-Path $env:LOCALAPPDATA 'Programs\WezTerm\wezterm.exe')
    foreach ($path in $candidates) {
        if ($path -and (Test-Path -LiteralPath $path)) {
            return $path
        }
    }
    return $null
}

if (-not $ConfigOnly -and -not (Find-WezTerm)) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'WezTerm не установлен, winget нет: поставь WezTerm и запусти с -ConfigOnly'
    }
    try {
        winget install --id wez.wezterm -e --accept-source-agreements --accept-package-agreements
    } catch {
        # winget мог отказать «уже установлен»; ниже проверяем, что WezTerm на месте.
    }
    if (-not (Find-WezTerm)) {
        throw 'WezTerm не установился: поставь его и запусти с -ConfigOnly'
    }
}

if (Test-Path -LiteralPath $stub) {
    $old = Get-Content -LiteralPath $stub -Raw -ErrorAction SilentlyContinue
    if ($old -notmatch [regex]::Escape($here) -or $old -notmatch "require\('config'\)") {
        $backup = "$stub.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -LiteralPath $stub -Destination $backup
        Write-Host "прежний ~/.wezterm.lua сохранён: $backup"
    }
}

$luaPath = $here -replace '\\', '/'
$content = @"
-- Конфиг WezTerm лежит в репозитории wezterm-config; файл пишет install.ps1.
package.path = [==[$luaPath/?.lua;]==] .. package.path
return require('config')
"@
[System.IO.File]::WriteAllText($stub, $content, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "подключено: $stub -> $here"
$local = Join-Path $here 'local.lua'
if (-not (Test-Path -LiteralPath $local)) {
    Copy-Item -LiteralPath (Join-Path $here 'local.example.lua') -Destination $local
    Write-Host "создан $local — машинное впиши туда."
} else {
    Write-Host "машинное — в $local (не коммитится)."
}
Write-Host "перезапусти WezTerm."
