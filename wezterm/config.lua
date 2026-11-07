-- config.lua — общий конфиг WezTerm для macOS и Windows.
--
-- Подключается из ~/.wezterm.lua: заглушка, которую пишет install.sh/install.ps1,
-- добавляет этот каталог в package.path и делает require('config') (подробности —
-- README.md рядом). Что даёт:
--   • Cmd+клик (macOS) / Ctrl+клик (Windows) по пути к файлу с расширением открывает
--     файл приложением ОС по умолчанию, «путь:строка:колонка» — в редакторе;
--     разбор — file_links.lua;
--   • обычный клик только выделяет текст и ссылок не открывает;
--   • Cmd+N (macOS) / Ctrl+N (Windows) — новая вкладка в каталоге текущей,
--     Cmd/Ctrl+Shift+N — новое окно, Cmd/Ctrl+G — навигатор вкладок;
--     список — keybindings.lua;
--   • Cmd/Ctrl+Shift+T — выбор темы, Cmd/Ctrl+Shift+P — палитра команд;
--   • на Windows Ctrl+C копирует только при выделении, иначе уходит приложению
--     как прерывание; Ctrl+V вставляет; все сочетания работают в русской раскладке;
--   • на macOS Option+стрелка — слово назад/вперёд;
--   • своя панель вкладок: без «fancy» стиля, без кнопки (+), вкладки растянуты
--     на всю ширину окна пропорционально длине заголовка — tab_layout.lua;
--   • на Windows оболочка — Git Bash.
--
-- Машинная часть — local.lua рядом с конфигом: функция или таблица с setup(ctx).
-- Она получает собранный конфиг и добавляет свои привязки, правила ссылок и
-- обработчики.

local wezterm = require('wezterm')
local act = wezterm.action

local file_links = require('file_links')
local keybindings = require('keybindings')
local tab_layout = require('tab_layout')

local machine = {}
do
  local ok, value = pcall(require, 'local')
  if ok then
    if type(value) == 'function' then
      machine.setup = value
    elseif type(value) == 'table' then
      machine = value
    end
  end
end

-- WezTerm сам отслеживает для автоперезагрузки только файл конфига, то есть
-- заглушку; правки в репозитории должны подхватываться так же.
for _, module in ipairs({ 'config', 'file_links', 'keybindings', 'tab_layout' }) do
  wezterm.add_to_config_reload_watch_list(package.searchpath(module, package.path))
end

local windows = wezterm.target_triple:find('windows') ~= nil
local config = wezterm.config_builder()

-- Windows отдаёт Ctrl+букву как заглавную, а на русской раскладке — кириллицей.
-- Привязки с префиксом phys: (US-позиция клавиши) переживают смену раскладки:
-- Ctrl+N открывает вкладку, Ctrl+W закрывает её, Ctrl+C/V работают и в русской
-- раскладке. Глобальный key_map_preference = 'Physical' не годится: он ломает
-- встроенные односоставные Ctrl-сочетания, которые WezTerm выводит из Cmd-вариантов.
local function key(name)
  return windows and ('phys:' .. name) or name
end

-- FORCE_HYPERLINK: WezTerm нет в списке терминалов с гиперссылками OSC 8 у Claude Code
-- (и у пакета supports-hyperlinks на Windows), и без переменной markdown-ссылка выводится
-- текстом «имя (адрес)». Такой текст Claude Code сам переносит переводом строки по ширине
-- панели, и длинный путь рассыпается на куски, которые правила ссылок уже не узнают.
-- Гиперссылка OSC 8 привязана к ячейкам и переживает перенос; адрес без схемы разбирает
-- file_links.link_text.
local environment = { FORCE_HYPERLINK = '1' }

if windows then
  -- Путь установки Git for Windows по умолчанию.
  config.default_prog = { 'C:\\Program Files\\Git\\bin\\bash.exe', '-i', '-l' }
  -- OSC 7 на каждом приглашении: так WezTerm знает каталог Git Bash, и
  -- относительные пути из вывода разрешаются от него. Если ~/.bashrc
  -- переопределяет PROMPT_COMMAND целиком, строку нужно дописать туда.
  environment.PROMPT_COMMAND = [[printf '\033]7;file://%s\033\\' "$PWD"]]
end

config.set_environment_variables = environment

-- Размер шрифта: пять шагов IncreaseFontSize (каждый — +10 %) от 12 pt по
-- умолчанию, 12 × 1.1⁵ ≈ 19.3 — столько владелец выставлял руками в каждом окне.
config.font_size = 19.3
-- Тема по умолчанию; Cmd/Ctrl+Shift+T меняет её только для текущего окна.
-- Регистр важен: «catppuccin-frappe» — другая встроенная тема, без цветов вкладок.
config.color_scheme = 'Catppuccin Frappe'

-- Правила ссылок перечислены явно, а не взяты из wezterm.default_hyperlink_rules(): во
-- встроенном правиле голого URL завершающая `)` входит в адрес, и закрывающая скобка
-- markdown-ссылки `[имя](url)` оказывалась частью URL. Здесь тот же набор, но `)` в
-- конце адреса не захватывается. Первые три правила разбирают URL, уже заключённый в
-- скобки, и отдают его без них. Машинные правила добавляет local.lua в начало списка.
config.hyperlink_rules = {
  { regex = [==[\((\w+://\S+)\)]==], format = '$1' },
  { regex = [==[\[(\w+://\S+)\]]==], format = '$1' },
  { regex = [==[<(\w+://\S+)>]==], format = '$1' },
  { regex = [==[\b\w+://\S+[/a-zA-Z0-9-]+]==], format = '$0' },
  { regex = [==[\b\w+@[\w-]+(\.[\w-]+)+\b]==], format = 'mailto:$0' },
  { regex = file_links.hyperlink_regex, format = file_links.scheme .. ':$0' },
}

-- Ссылки — только с модификатором, как в iTerm2 и mintty: правило для путей с
-- пробелами подчёркивает длинные куски строки, и открывать их обычным кликом
-- мешало бы выделению. Вторая пара привязок работает, когда приложение в панели
-- (например, полноэкранный TUI) забрало мышь себе.
local open_mods = windows and 'CTRL' or 'SUPER'
config.mouse_bindings = {
  {
    event = { Up = { streak = 1, button = 'Left' } },
    mods = 'NONE',
    action = act.CompleteSelection('ClipboardAndPrimarySelection'),
  },
  {
    event = { Up = { streak = 1, button = 'Left' } },
    mods = open_mods,
    action = act.OpenLinkAtMouseCursor,
  },
  {
    event = { Down = { streak = 1, button = 'Left' } },
    mods = open_mods,
    action = act.Nop,
  },
  {
    event = { Up = { streak = 1, button = 'Left' } },
    mods = open_mods,
    mouse_reporting = true,
    action = act.OpenLinkAtMouseCursor,
  },
  {
    event = { Down = { streak = 1, button = 'Left' } },
    mods = open_mods,
    mouse_reporting = true,
    action = act.Nop,
  },
}

-- Существование файла — через wezterm.read_dir: io.open на Windows понимает
-- путь в ANSI-кодировке, и кириллица в именах заметок до файла не доходит.
-- Файловые системы macOS и Windows по умолчанию не различают регистр, поэтому
-- и сравнение имён — без учёта регистра (латиница).
local function exists(path)
  local dir, name = path:match('^(.*)/([^/]+)$')
  if dir == nil then
    return false
  end
  if dir == '' or dir:match('^%a:$') then
    dir = dir .. '/'
  end
  local ok, entries = pcall(wezterm.read_dir, dir)
  if not ok then
    return false
  end
  name = name:lower()
  for _, entry in ipairs(entries) do
    if (entry:match('[^/\\]+$') or ''):lower() == name then
      return true
    end
  end
  return false
end

-- Файлы с таким именем в рабочем дереве каталога панели: имя без каталога сами по
-- себе печатают компилятор и тесты Go («card.go:358: …»), и от каталога панели оно
-- не разрешается. Дерево и список файлов даёт git — так ссылка ведёт в то же
-- дерево, где шёл прогон, а не в основной каталог репозитория.
local git = windows and 'C:\\Program Files\\Git\\bin\\git.exe' or '/usr/bin/git'

local function find_in_tree(cwd, name)
  if cwd == nil then
    return {}
  end
  local located, root = wezterm.run_child_process({ git, '-C', cwd, 'rev-parse', '--show-toplevel' })
  if not located then
    return {}
  end
  root = root:gsub('%s+$', '')
  local listed, files = wezterm.run_child_process({ git, '-C', root, 'ls-files', '--', name, '*/' .. name })
  if not listed then
    return {}
  end
  local paths = {}
  for line in files:gmatch('[^\r\n]+') do
    paths[#paths + 1] = root .. '/' .. line
  end
  return paths
end

local link_opts = {
  windows = windows,
  home = wezterm.home_dir,
  exists = exists,
  find = find_in_tree,
  windows_cli = machine.windows_cli,
}

-- Каталог панели: объект Url в современных версиях WezTerm, строка file://… в
-- старых, nil — если неизвестен. На Windows Git Bash отдаёт /c/Users/…; для
-- spawn_window и cmd.exe нужен родной C:/Users/….
local function native_path(path)
  if windows and path ~= nil then
    path = path:gsub('^/(%a)/', '%1:/'):gsub('^/(%a:)/', '%1/')
  end
  return path
end

local function pane_cwd(pane)
  local cwd = pane:get_current_working_dir()
  if cwd == nil then
    return nil
  end
  if type(cwd) == 'string' then
    return native_path(file_links.file_uri_path(cwd))
  end
  return native_path(cwd.file_path)
end

-- Решение по каждому клику — в лог WezTerm (~/.local/share/wezterm/wezterm-gui-log-<pid>.txt),
-- рядом с его собственной строкой «clicking …».
local function open_target(text, target)
  wezterm.log_info('open-uri: ' .. text .. ' -> ' .. target)
  wezterm.open_with(target)
end

-- Создаем список всех встроенных тем для меню выбора
local schemes = wezterm.color.get_builtin_schemes()
local choices = {}
for name, _ in pairs(schemes) do
    table.insert(choices, { label = name })
end
-- Сортируем темы по алфавиту
table.sort(choices, function(a, b) return a.label < b.label end)

config.keys = {
  -- Односоставные сочетания на обеих системах: Ctrl на Windows, Cmd на macOS.
  { key = key('t'), mods = open_mods .. '|SHIFT', action = act.InputSelector {
    title = 'Выберите тему (Color Scheme)',
    choices = choices,
    fuzzy = true,
    action = wezterm.action_callback(function(window, pane, id, label)
      if label then
        window:set_config_overrides({
          color_scheme = label,
          colors = tab_layout.colors_for(config.colors, schemes[label]),
        })
      end
    end),
  } },
  { key = key('p'), mods = open_mods .. '|SHIFT', action = act.ActivateCommandPalette },
}

if windows then
  -- Ctrl+C: с выделением — копия, без выделения — прерывание процесса.
  config.keys[#config.keys + 1] = {
    key = key('c'),
    mods = 'CTRL',
    action = wezterm.action_callback(function(window, pane)
      if window:get_selection_text_for_pane(pane) ~= '' then
        window:perform_action(act.CopyTo 'Clipboard', pane)
        window:perform_action(act.ClearSelection, pane)
      else
        window:perform_action(act.SendKey { key = 'c', mods = 'CTRL' }, pane)
      end
    end),
  }
  config.keys[#config.keys + 1] = {
    key = key('v'),
    mods = 'CTRL',
    action = act.PasteFrom 'Clipboard',
  }
  -- Основные встроенные Ctrl-команды: на русской раскладке их Mapped-варианты
  -- не совпадают с кириллицей, поэтому дублируются физической клавишей.
  local builtin = {
    { 'w', 'CTRL', act.CloseCurrentTab { confirm = true } },
    { 'c', 'SHIFT|CTRL', act.CopyTo 'Clipboard' },
    { 'v', 'SHIFT|CTRL', act.PasteFrom 'Clipboard' },
    { 'f', 'CTRL', act.Search 'CurrentSelectionOrEmptyString' },
    { 'x', 'CTRL', act.ActivateCopyMode },
    { 'z', 'CTRL', act.TogglePaneZoomState },
    { 'k', 'CTRL', act.ClearScrollback 'ScrollbackOnly' },
    { 'u', 'CTRL', act.CharSelect { copy_on_select = true, copy_to = 'ClipboardAndPrimarySelection' } },
    { 'r', 'CTRL', act.ReloadConfiguration },
  }
  for i = 1, 9 do
    builtin[#builtin + 1] = { tostring(i), 'CTRL', act.ActivateTab(i == 9 and -1 or i - 1) }
  end
  for _, binding in ipairs(builtin) do
    config.keys[#config.keys + 1] = {
      key = key(binding[1]),
      mods = binding[2],
      action = binding[3],
    }
  end
else
  -- Option+стрелка: слово назад/вперёд, как Esc+b / Esc+f в readline и zsh.
  config.keys[#config.keys + 1] = { key = 'LeftArrow', mods = 'OPT', action = act.SendString '\x1bb' }
  config.keys[#config.keys + 1] = { key = 'RightArrow', mods = 'OPT', action = act.SendString '\x1bf' }
end

-- Список keybindings.lua — сюда же, модификатор тот же: Cmd на macOS,
-- Ctrl на Windows. На Windows клавиши физические, как и остальные выше.
for _, binding in ipairs(keybindings.keys(open_mods)) do
  if windows then
    binding.key = key(binding.key)
  end
  config.keys[#config.keys + 1] = binding
end

-- Файл открывает редактор — путь с позицией, ОС — всё остальное.
local function open_path(window, text, path, position)
  if position ~= nil then
    local argv = file_links.editor_argv(path, position, windows, link_opts.windows_cli)
    if argv == nil then
      local message = 'Редактор: на Windows задайте путь к CLI Zed в переменной ZED_CLI_WINDOWS'
      wezterm.log_error(message)
      window:toast_notification('WezTerm', message, nil, 4000)
      return
    end
    wezterm.log_info('open-uri: ' .. text .. ' -> ' .. table.concat(argv, ' '))
    wezterm.background_child_process(argv)
    return
  end

  open_target(text, file_links.target(path, windows))
end

wezterm.on('open-uri', function(window, pane, uri)
  local text = file_links.link_text(uri)
  if text == nil then
    -- Не наш случай: WezTerm открывает ссылку сам или её разбирает local.lua.
    return
  end

  local cwd = pane_cwd(pane)
  local path, position = file_links.resolve(text, cwd, link_opts)
  if path ~= nil then
    open_path(window, text, path, position)
    return false
  end

  -- Имени без каталога соответствуют все одноимённые файлы дерева: один — открыть,
  -- несколько — выбор владельца, ни одного — уведомление.
  local matches = file_links.repo_matches(text, cwd, link_opts)
  local _, bare_position = file_links.split_position(text)
  if #matches == 1 then
    open_path(window, text, matches[1], bare_position)
    return false
  end
  if #matches > 1 then
    local choices = {}
    for _, match in ipairs(matches) do
      choices[#choices + 1] = { label = match, id = match }
    end
    window:perform_action(act.InputSelector({
      title = 'Какой ' .. text .. ' открыть',
      choices = choices,
      fuzzy = true,
      action = wezterm.action_callback(function(inner_window, _, id)
        if id ~= nil then
          open_path(inner_window, text, id, bare_position)
        end
      end),
    }), pane)
    return false
  end

  local message = 'Файл не найден: ' .. text
  wezterm.log_error(message)
  window:toast_notification('WezTerm', message, nil, 4000)
  return false
end)

tab_layout.apply(config, schemes)

if type(machine.setup) == 'function' then
  machine.setup({
    wezterm = wezterm,
    act = act,
    config = config,
    windows = windows,
    open_mods = open_mods,
    key = key,
    pane_cwd = pane_cwd,
    add_key = function(binding)
      config.keys[#config.keys + 1] = binding
    end,
    add_hyperlink_rule = function(rule)
      table.insert(config.hyperlink_rules, 1, rule)
    end,
  })
end

return config
