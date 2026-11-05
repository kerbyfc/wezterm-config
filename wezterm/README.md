# wezterm-config

Личный конфиг WezTerm для macOS и Windows: клавиши, копирование/вставка в русской
раскладке, темы, панель вкладок, ссылки на файлы.

## Установка

### macOS

```bash
brew install --cask wezterm   # или поставь WezTerm сам
git clone <этот-репозиторий> ~/Projects/wezterm-config
cd ~/Projects/wezterm-config/wezterm
./install.sh
```

`install.sh` ставит WezTerm через Homebrew, если его нет, и пишет заглушку
`~/.wezterm.lua` на этот каталог. Прежняя заглушка сохраняется рядом с датой.
Если `local.lua` ещё нет, установщик копирует его из `local.example.lua`.

### Windows

```powershell
winget install --id wez.wezterm -e
git clone <этот-репозиторий> $HOME\Projects\wezterm-config
cd $HOME\Projects\wezterm-config\wezterm
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

`install.ps1` ставит WezTerm через winget, если его нет, и пишет
`%USERPROFILE%\.wezterm.lua`. Перезапусти WezTerm.

Клавиатурные перестановки и CapsLock — в отдельном репозитории
`windows-autohotkey`; на macOS их нет.

## local.lua

`local.lua` не коммитится: машинное живёт только там. Установщик создаёт его из
`local.example.lua`, если файла ещё нет.

Файл возвращает таблицу с `setup(ctx)` — или функцию, которая получает `ctx`:

```lua
return {
  setup = function(ctx)
    -- ctx.wezterm, ctx.act, ctx.config, ctx.windows, ctx.open_mods,
    -- ctx.key(name), ctx.pane_cwd(pane),
    -- ctx.add_key(binding), ctx.add_hyperlink_rule(rule)
  end,
}
```

`setup` вызывается в конце сборки конфига: `ctx.add_key` дописывает привязку в
`config.keys`, `ctx.add_hyperlink_rule` ставит правило в начало
`config.hyperlink_rules`, `ctx.config` — сам конфиг. Если `setup` нет, работает
только общая часть.

`windows_cli` в той же таблице — полный путь к CLI редактора на Windows. Без него
ссылка «путь:строка» на Windows показывает уведомление, а не открывает файл чем-то
другим.

## Клавиши

На Windows модификатор — `Ctrl`, на macOS — `Cmd`. На Windows основные сочетания
используют физическую позицию клавиши и работают в русской раскладке.

| Windows | macOS | Действие |
|---|---|---|
| `Ctrl+C` / `Ctrl+V` | `Cmd+C` / `Cmd+V` | копировать/вставить; без выделения `Ctrl+C` — прерывание |
| `Ctrl+N` | `Cmd+N` | новая вкладка в каталоге текущей |
| `Ctrl+Shift+N` | `Cmd+Shift+N` | новое окно |
| `Ctrl+W` | `Cmd+W` | закрыть вкладку |
| `Ctrl+Shift+T` | `Cmd+Shift+T` | выбор темы |
| `Ctrl+Shift+P` | `Cmd+Shift+P` | палитра команд |
| `Ctrl+G` | `Cmd+G` | навигатор вкладок |
| `Ctrl+1…9` | `Cmd+1…9` | переключить вкладку |

`Ctrl`/`Cmd`+клик по пути с расширением открывает файл; `file:строка:колонка`
открывает редактор (Zed), если задан `windows_cli`.

На macOS `Option+Left/Right` посылают `Esc+b`/`Esc+f` — слово назад/вперёд.

## Проверка

Конфиг читается WezTerm; после установки открой новое окно. Логи WezTerm:
`~/.local/share/wezterm/` (Windows — `%USERPROFILE%\.local\share\wezterm\`).

## Файлы

- `config.lua` — основной конфиг и привязки, вызов `local.lua`.
- `file_links.lua` — разбор путей и ссылок.
- `keybindings.lua` — вкладки и окна.
- `local.example.lua` — шаблон `local.lua`.
- `install.sh`, `install.ps1` — заглушка `~/.wezterm.lua`.
