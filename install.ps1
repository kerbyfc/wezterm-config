param(
    [switch]$ConfigOnly
)

& (Join-Path $PSScriptRoot 'wezterm\install.ps1') @PSBoundParameters
