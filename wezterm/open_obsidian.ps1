# open_obsidian.ps1 — открыть obsidian://-адрес и вывести Obsidian на передний план (Windows).
#
# Запускается из wezterm.lua дочерним процессом WezTerm. Адрес доставляется уже
# запущенному Obsidian, но сам Obsidian окно вперёд вывести не может: Windows блокирует
# смену переднего плана чужим процессом, и кнопка только мигает на панели задач. Процессу,
# запущенному процессом переднего плана (WezTerm в момент клика), смена разрешена —
# поэтому окно активирует этот скрипт.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File open_obsidian.ps1 <obsidian://…>

param([Parameter(Mandatory = $true)][string]$Uri)

$ErrorActionPreference = 'Stop'

# Окно Obsidian (Electron) принадлежит главному процессу; остальные его процессы окон не
# имеют. Окна нет — Obsidian не запущен: его запустит Start-Process, и новый процесс
# выйдет вперёд сам.
$window = Get-Process -Name Obsidian -ErrorAction SilentlyContinue |
  Where-Object { $_.MainWindowHandle -ne 0 } |
  Select-Object -First 1

Start-Process $Uri

if ($null -ne $window) {
  if (-not (New-Object -ComObject WScript.Shell).AppActivate($window.Id)) {
    throw "Не удалось активировать окно Obsidian (pid $($window.Id))"
  }
}
