#!/usr/bin/env bash
# Установка конфига WezTerm из этого каталога.
#
#   ./install.sh                 поставить WezTerm (если нет) и подключить конфиг
#   ./install.sh --config-only   только подключить конфиг, WezTerm не ставить
#
# Заглушка ~/.wezterm.lua перезаписывается; прежняя сохраняется рядом с датой.
# Пути проекта и команда запускалки — в local.lua (см. local.example.lua).

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
stub="$HOME/.wezterm.lua"
config_only=0

for arg in "$@"; do
    case "$arg" in
        --config-only) config_only=1 ;;
        -h | --help)
            sed -n '2,9p' "$0"
            exit 0
            ;;
        *)
            echo "неизвестный аргумент: $arg" >&2
            exit 2
            ;;
    esac
done

if [ "$config_only" = 0 ] && ! command -v wezterm >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
        brew install --cask wezterm
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
echo "дальше: cp '$here/local.example.lua' '$here/local.lua' и заполни пути проекта (если нужны ссылки Obsidian и запускалка)."
echo "перезапусти WezTerm."
