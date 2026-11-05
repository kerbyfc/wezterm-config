# wezterm-config

Личный конфиг WezTerm для macOS и Windows. Клавиши, копирование/вставка в русской
раскладке, темы, панель вкладок, ссылки на файлы и заметки. Ссылки на Obsidian,
worktree, запускалка и ссылки агентов включаются через `local.lua`.

## Установка

### macOS

```bash
brew install --cask wezterm   # или поставь WezTerm сам
git clone <этот-репозиторий> ~/Projects/wezterm-config
cd ~/Projects/wezterm-config/wezterm
./install.sh
cp local.example.lua local.lua   # заполни пути проекта
```

`install.sh` ставит WezTerm через Homebrew, если его нет, и пишет заглушку
`~/.wezterm.lua` на этот каталог. Прежняя заглушка сохраняется рядом с датой.

### Windows

```powershell
winget install --id wez.wezterm -e
git clone <этот-репозиторий> $HOME\Projects\wezterm-config
cd $HOME\Projects\wezterm-config\wezterm
powershell -ExecutionPolicy Bypass -File .\install.ps1
Copy-Item local.example.lua local.lua
```

`install.ps1` ставит WezTerm через winget, если его нет, и пишет
`%USERPROFILE%\.wezterm.lua`. Перезапусти WezTerm.

Клавиатурные перестановки и CapsLock — в отдельном репозитории
`windows-autohotkey`; на macOS их нет.

## local.lua

`local.lua` не коммитится. Скопируй `local.example.lua` и заполни:

| Поле | Что задаёт |
|---|---|
| `project_root` | корень проекта: ссылки на заметки Obsidian, worktree, запускалка |
| `vault` | каталог хранилища внутри проекта, по умолчанию `obsidian` |
| `obsidian_tree` | скрипт регистрации хранилища worktree, по умолчанию `scripts/obsidian-tree.sh` |
| `agent_scheme` | схема ссылок кубиков агентов; по умолчанию `agent` |
| `launcher_title` | заголовок вкладки запускалки |
| `launcher_command` | `function(root, windows) -> argv`; без неё запускалка выключена |
| `windows_cli` | полный путь к CLI Zed на Windows (`ZED_CLI_WINDOWS`) |

Без `project_root` работают обычные пути, URL, редактор и запускалка не включается;
ссылки на заметки и агентов пропускаются.

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
| `Ctrl+Shift+L` (и `Ctrl+L`) | `Cmd+Shift+L` (и `Cmd+L`) | запускалка (если задана в `local.lua`) |
| `Ctrl+1…9` | `Cmd+1…9` | переключить вкладку |

`Ctrl`/`Cmd`+клик по пути с расширением открывает файл; `file:строка:колонка`
открывает редактор (Zed), если задан `windows_cli`; заметка хранилища открывается
в Obsidian при заданном `project_root`.

На macOS `Option+Left/Right` посылают `Esc+b`/`Esc+f` — слово назад/вперёд.

## Проверка

Конфиг читается WezTerm; после установки открой новое окно. Логи WezTerm:
`~/.local/share/wezterm/` (Windows — `%USERPROFILE%\.local\share\wezterm\`).

## Файлы

- `config.lua` — основной конфиг и привязки.
- `file_links.lua` — разбор путей и ссылок, Obsidian.
- `agent_links.lua`, `agent_transcript.py` — ссылки кубиков агентов.
- `keybindings.lua`, `launcher_window.lua` — вкладки/окна и запускалка.
- `open_obsidian.ps1` — вывод Obsidian на передний план на Windows.
- `install.sh`, `install.ps1` — заглушка `~/.wezterm.lua`.
