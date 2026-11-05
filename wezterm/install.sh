#!/usr/bin/env bash
# Установка конфига WezTerm из этого каталога.
#
#   ./install.sh                 поставить WezTerm (если нет) и подключить конфиг
#   ./install.sh --config-only   только подключить конфиг, WezTerm не ставить
#
# Если WezTerm уже установлен — установка не запускается и скрипт не падает.
# Заглушка ~/.wezterm.lua перезаписывается; прежняя сохраняется рядом с датой.
# Машинное — в local.lua (см. local.example.lua).

set -euo pipefail

case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*)
        echo "На Windows запусти install.ps1 из PowerShell, а не install.sh" >&2
        exit 1
        ;;
esac

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
stub="$HOME/.wezterm.lua"
config_only=0

for arg in "$@"; do
    case "$arg" in
        --config-only) config_only=1 ;;
        -h | --help)
            sed -n '2,10p' "$0"
            exit 0
            ;;
        *)
            echo "неизвестный аргумент: $arg" >&2
            exit 2
            ;;
    esac
done

wezterm_installed() {
    if command -v wezterm >/dev/null 2>&1; then
        return 0
    fi
    if [ -d "/Applications/WezTerm.app" ] || [ -d "$HOME/Applications/WezTerm.app" ]; then
        return 0
    fi
    if command -v brew >/dev/null 2>&1 && brew list --cask wezterm >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

if [ "$config_only" = 0 ] && ! wezterm_installed; then
    if command -v brew >/dev/null 2>&1; then
        if ! brew install --cask wezterm; then
            if ! wezterm_installed; then
                echo "WezTerm не установился; поставь его и повтори с --config-only" >&2
                exit 1
            fi
        fi
    else
        echo "WezTerm не установлен, а Homebrew нет: поставь WezTerm и повтори с --config-only" >&2
        exit 1
    fi
fi

if [ -e "$stub" ]; then
    if grep -qF "$here" "$stub" 2>/dev/null && grep -qF "require('config')" "$stub" 2>/dev/null; then
        :
    else
        backup="$stub.backup.$(date +%Y%m%d-%H%M%S)"
        cp "$stub" "$backup"
        echo "прежний ~/.wezterm.lua сохранён: $backup"
    fi
fi

cat >"$stub" <<EOF
-- Конфиг WezTerm лежит в репозитории wezterm-config; файл пишет install.sh.
package.path = [==[$here/?.lua;]==] .. package.path
return require('config')
EOF

echo "подключено: $stub -> $here"
if [ ! -e "$here/local.lua" ]; then
    cp "$here/local.example.lua" "$here/local.lua"
    echo "создан $here/local.lua — машинное впиши туда."
else
    echo "машинное — в $here/local.lua (не коммитится)."
fi
echo "перезапусти WezTerm."
