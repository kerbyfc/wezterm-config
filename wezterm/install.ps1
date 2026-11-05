param(
    [switch]$ConfigOnly
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$stub = Join-Path $env:USERPROFILE '.wezterm.lua'

if (-not $ConfigOnly) {
    $wezterm = Get-Command wezterm -ErrorAction SilentlyContinue
    if (-not $wezterm) {
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            throw 'WezTerm не установлен, winget нет: поставь WezTerm и запусти с -ConfigOnly'
        }
        winget install --id wez.wezterm -e --accept-source-agreements --accept-package-agreements
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
Set-Content -LiteralPath $stub -Value $content -Encoding UTF8

Write-Host "подключено: $stub -> $here"
Write-Host "дальше: скопируй local.example.lua в local.lua и заполни пути проекта (если нужны ссылки Obsidian и запускалка)."
Write-Host "перезапусти WezTerm."
