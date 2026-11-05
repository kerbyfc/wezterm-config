-- file_links.lua — куда открывать файл, по которому кликнули в терминале.
--
-- Кликабелен путь к любому файлу с расширением (hyperlink_regex). Правило:
--   • репозиторий — ближайший к корню каталог пути с именем project
--     (без учёта регистра);
--   • файл *.md под <репозиторий>/obsidian/ — заметка хранилища, открывается в
--     Obsidian через obsidian://open?path=<абсолютный путь>: Obsidian сам находит
--     зарегистрированное хранилище, в котором лежит файл;
--   • файл *.md под <репозиторий>/.claude/worktrees/<имя>/obsidian/ — заметка
--     хранилища дерева (tree_note): такое хранилище в Obsidian не
--     зарегистрировано, его сначала открывает scripts/obsidian-tree.sh
--     (регистрирует, при необходимости перезапускает Obsidian), затем заметку;
--   • путь с позицией — «путь:строка» или «путь:строка:колонка» — Zed
--     (editor_argv): только он ставит курсор на строку, приложению ОС позицию не
--     передать;
--   • всё остальное — приложением, которое ОС назначила для файла по умолчанию.
--     Сюда же попадают файлы из скрытых каталогов хранилища вроде obsidian/.trash
--     (Obsidian их не индексирует).
--
-- Имя файла без каталога — так его печатают компилятор и тесты Go
-- («card.go:358: …») — от каталога панели не разрешается; такие имена ищет по
-- рабочему дереву opts.find (repo_matches).
--
-- Модуль не зависит от wezterm: файловая система и платформа приходят снаружи
-- в opts, поэтому логика проверяется обычным lua (file_links_test.lua).
--
-- opts = {
--   windows = boolean,               -- пути Windows: диск, обратные слэши, MSYS
--   home    = string | nil,          -- для путей вида ~/…
--   exists  = function(path) -> bool -- путь в виде «C:/a/b» или «/a/b»
--   find    = function(cwd, name) -> { path }  -- файлы с таким именем в рабочем
--                                              -- дереве каталога cwd
-- }
--
-- Внутри модуля путь всегда с прямыми слэшами; на Windows — с буквой диска в
-- верхнем регистре («C:/Users/…»). Родная форма нужна только на выходе — target.

local M = {}

-- Настройка проекта задаётся в local.lua рядом с конфигом. Без неё ссылки на
-- заметки хранилища, worktree и запускалка выключены, а обычные пути и URL работают.
M.project_root = nil
M.vault = 'obsidian'
M.obsidian_tree = 'scripts/obsidian-tree.sh'

-- Схема ссылок, которые создаёт hyperlink_regex: open-uri отличает их от
-- остальных URI по этому префиксу.
M.scheme = 'file-line'

-- Правило для hyperlink_rules (fancy-regex), две ветки.
--   1. Путь к .md с пробелами: от первого токена с разделителем каталогов до
--      ближайшего «.md» — в именах заметок хранилища есть пробелы, и без этого
--      кликабельным оказался бы только хвост имени. Пробел пропускается, только
--      если перед ним нет расширения другого файла: «a/b.go и c/d e.md» — две
--      ссылки, а не одна. Лишний текст, захваченный слева, отрезает resolve —
--      перебором суффиксов.
--   2. Путь к любому файлу с расширением, без пробелов: «apps/game/x.go»,
--      «README.md», «archive.tar.gz». Расширение начинается с буквы, поэтому
--      числа («0.577», «v1.2») ссылками не становятся.
-- Для обеих:
--   • lookbehind не даёт начать совпадение с середины слова, пути, URL или почты;
--   • внутри пути двоеточие допустимо только в букве диска, а после расширения —
--     хвост позиции «:строка» или «:строка:колонка»: так место в файле печатают
--     компилятор Go, линтеры и агент;
--   • «@» исключён, чтобы не пересекаться со встроенным правилом почты WezTerm.
M.hyperlink_regex = [==[(?<![\w:/\\.~@-])(?:(?:[A-Za-z]:)?[^\s"'`<>|()\[\]{}:*?@]*[/\\](?:(?!\.[A-Za-z][A-Za-z0-9_]*\s)[^\n"'`<>|:*?])*?\.md\b|(?:[A-Za-z]:)?[^\s"'`<>|()\[\]{}:*?@]*[^\s"'`<>|()\[\]{}:*?@/\\.]\.[A-Za-z][A-Za-z0-9_]*\b)(?::[0-9]+(?::[0-9]+)?)?]==]

-- Кодирование/раскодирование %XX. Нужно и этому модулю (пути из markdown-ссылок,
-- Obsidian URI), и agent_links.lua (значения его ссылок), поэтому обе функции —
-- часть интерфейса.
function M.percent_decode(s)
  return (s:gsub('%%(%x%x)', function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

-- Кодирует всё, кроме unreserved из RFC 3986: так требует Obsidian URI
-- (слэши — %2F, пробелы — %20).
function M.percent_encode(s)
  return (s:gsub('[^%w%-%._~]', function(c)
    return string.format('%%%02X', c:byte())
  end))
end

-- Путь из file://-URI (OSC 8, OSC 7, голый URI в выводе) или nil.
function M.file_uri_path(uri)
  local path = uri:match('^file://[^/]*(/.*)$')
  if path == nil then
    return nil
  end
  return M.percent_decode(path)
end

-- Текст ссылки, которую надо разбирать этим модулем, или nil — тогда URI
-- открывает сам WezTerm. Наши ссылки: созданные hyperlink_regex, file://-URI и
-- URI без схемы — путь, отданный программой гиперссылкой OSC 8 (так Claude Code
-- выводит markdown-ссылку на файл, в том числе file://-ссылку). Схема — от двух
-- символов: «C:» — буква диска.
-- Префикс схемы сравнивается строкой, а не шаблоном: «-» в M.scheme —
-- спецсимвол шаблонов Lua.
function M.link_text(uri)
  local prefix = M.scheme .. ':'
  if uri:sub(1, #prefix) == prefix then
    return uri:sub(#prefix + 1)
  end
  local path = M.file_uri_path(uri)
  if path ~= nil then
    return path
  end
  if uri:match('^%a[%w+.-]+:') then
    return nil
  end
  return uri
end

-- Прямые слэши; на Windows — буква диска для MSYS-путей («/c/Users») и
-- для путей из file://-URI («/C:/Users»).
local function to_internal(path, windows)
  path = path:gsub('\\', '/')
  if not windows then
    return path
  end
  local drive, rest = path:match('^/(%a):(.*)$')
  if drive == nil then
    drive, rest = path:match('^/(%a)(/.*)$')
  end
  if drive == nil then
    drive = path:match('^/(%a)$')
    rest = drive and '/'
  end
  if drive == nil then
    drive, rest = path:match('^(%a):(.*)$')
  end
  if drive == nil then
    return path
  end
  return drive:upper() .. ':' .. rest
end

local function is_absolute(path, windows)
  if windows then
    return path:match('^%a:/') ~= nil
  end
  return path:sub(1, 1) == '/'
end

-- Убирает «.», «..» и пустые сегменты. Корень — «/» или «C:/».
local function canonical(path, windows)
  local root, rest
  if windows then
    root, rest = path:match('^(%a:)/(.*)$')
    root = root .. '/'
  else
    root, rest = '/', path:sub(2)
  end
  local segments = {}
  for segment in rest:gmatch('[^/]+') do
    if segment == '..' then
      segments[#segments] = nil
    elseif segment ~= '.' then
      segments[#segments + 1] = segment
    end
  end
  return root .. table.concat(segments, '/')
end

local function absolute(text, cwd, opts)
  local path = to_internal(text, opts.windows)
  if path:match('^~/') then
    if opts.home == nil then
      return nil
    end
    path = to_internal(opts.home, opts.windows) .. path:sub(2)
  end
  if not is_absolute(path, opts.windows) then
    if cwd == nil then
      return nil
    end
    local base = to_internal(cwd, opts.windows)
    if not is_absolute(base, opts.windows) then
      return nil
    end
    path = base .. '/' .. path
  end
  return canonical(path, opts.windows)
end

-- Кандидаты на путь внутри совпадения: весь текст, затем суффиксы после
-- каждого пробела — слева мог прилипнуть текст до пути. Для каждого ещё и
-- вариант с раскодированными %XX (пути из markdown-ссылок).
local function candidates(text)
  local list = {}
  local function add(candidate)
    list[#list + 1] = candidate
    local decoded = M.percent_decode(candidate)
    if decoded ~= candidate then
      list[#list + 1] = decoded
    end
  end
  add(text)
  for start in text:gmatch('%s+()') do
    if start <= #text then
      add(text:sub(start))
    end
  end
  return list
end

-- Путь без хвоста позиции и сама позиция ({ line, col } или nil): «x.go:12:5».
-- Буква диска хвостом не считается — после двоеточия только цифры до конца
-- текста.
function M.split_position(text)
  local path, line, col = text:match('^(.+):(%d+):(%d+)$')
  if path == nil then
    path, line = text:match('^(.+):(%d+)$')
  end
  if path == nil then
    return text, nil
  end
  return path, { line = tonumber(line), col = col and tonumber(col) }
end

local function resolve_path(text, cwd, opts)
  for _, candidate in ipairs(candidates(text)) do
    local path = absolute(candidate, cwd, opts)
    if path ~= nil and opts.exists(path) then
      return path
    end
  end
  return nil
end

-- Абсолютный путь к существующему файлу из текста ссылки и позиция в нём
-- ({ line, col } или nil) — либо nil, если файла нет. Относительные пути
-- разрешаются от cwd (строка пути или nil, если каталог панели неизвестен).
-- Хвост позиции отрезается первым: файл с двоеточием и цифрами в имени
-- открывается, когда пути с отрезанным хвостом не существует.
function M.resolve(text, cwd, opts)
  local bare, position = M.split_position(text)
  if position ~= nil then
    local path = resolve_path(bare, cwd, opts)
    if path ~= nil then
      return path, position
    end
  end
  return resolve_path(text, cwd, opts)
end

-- Файлы рабочего дерева с таким именем — для имени без каталога, которое сами по
-- себе печатают компилятор и тесты Go. Путь с разделителем каталогов сюда не
-- попадает: он либо разрешается от cwd, либо не существует.
function M.repo_matches(text, cwd, opts)
  local name = M.split_position(text)
  if name:match('[/\\]') ~= nil or name == '' then
    return {}
  end
  return opts.find(cwd, name)
end

-- Корень проекта и путь внутри него (сегменты) или nil, если путь не из проекта.
function M.repo_split(path)
  local normalized = path:gsub('\\', '/')
  local root = M.project_root
  if root == nil or root == '' then
    return nil
  end
  root = root:gsub('\\', '/'):gsub('/+$', '')
  if normalized:sub(1, #root):lower() ~= root:lower() then
    return nil
  end
  local rest = normalized:sub(#root + 2)
  local segments = {}
  for segment in rest:gmatch('[^/]+') do
    segments[#segments + 1] = segment
  end
  return root, segments
end

-- Корень проекта как путь или nil.
function M.repo_root(path)
  return M.repo_split(path)
end

-- Заметка хранилища worktree: { tree = '<репозиторий>/.claude/worktrees/<имя>',
-- note = 'путь относительно obsidian/' } или nil. Скрытые каталоги хранилища —
-- как у is_vault_note.
function M.tree_note(path)
  local root, relative = M.repo_split(path)
  if root == nil or #relative < 5 then
    return nil
  end
  if relative[1] ~= '.claude' or relative[2] ~= 'worktrees' or relative[4]:lower() ~= M.vault:lower() then
    return nil
  end
  for i = 5, #relative do
    if relative[i]:sub(1, 1) == '.' then
      return nil
    end
  end
  if relative[#relative]:lower():match('%.md$') == nil then
    return nil
  end
  local tree = M.repo_root(path) .. '/' .. table.concat(relative, '/', 1, 3)
  return { tree = tree, note = table.concat(relative, '/', 5) }
end

local function shell_quote(s)
  return "'" .. s:gsub("'", [['\'']]) .. "'"
end

-- Команда открытия заметки worktree для wezterm.background_child_process:
-- scripts/obsidian-tree.sh основного каталога через интерактивный login-shell
-- (node приходит из профиля оболочки; на Windows — Git Bash, каталог по
-- умолчанию у Git for Windows). Пути — в форме bash: на Windows он понимает
-- «C:/…».
function M.tree_open_argv(note, windows)
  local root = M.repo_root(note.tree)
  if root == nil or M.obsidian_tree == nil or M.obsidian_tree == '' then
    return nil
  end
  local script = M.obsidian_tree
  if script:sub(1, 1) ~= '/' and script:match('^%a:[/\\]') == nil then
    script = root .. '/' .. script
  end
  local command = 'exec ' .. shell_quote(script)
    .. ' ' .. shell_quote(note.tree) .. ' ' .. shell_quote(note.note)
  if windows then
    return { 'C:\\Program Files\\Git\\bin\\bash.exe', '-l', '-i', '-c', command }
  end
  return { '/bin/zsh', '-l', '-i', '-c', command }
end

-- Скрытые каталоги хранилища (.trash, .obsidian) Obsidian не индексирует, и
-- obsidian://open файлы из них не открывает.
function M.is_vault_note(path)
  local root, relative = M.repo_split(path)
  if root == nil then
    return false
  end
  if #relative < 2 or relative[1]:lower() ~= M.vault:lower() then
    return false
  end
  for i = 2, #relative do
    if relative[i]:sub(1, 1) == '.' then
      return false
    end
  end
  return relative[#relative]:lower():match('%.md$') ~= nil
end

-- Редактор, который открывает файл на строке, — Zed: CLI принимает
-- «путь:строка» или «путь:строка:колонка» позиционным аргументом, без ключа.
-- На macOS его ставит действие редактора cli::InstallCliBinary симлинком
-- в /usr/local/bin/zed.
-- На Windows путь CLI Zed не выяснен — это открытый вопрос, путь не угадывается;
-- ветку держит переменная окружения windows_cli (ZED_CLI_WINDOWS на стороне
-- вызывающего), которую задаёт владелец: полный путь к исполняемому файлу,
-- запускается через cmd.exe (работает и для .exe, и для .cmd/.bat). Переменная
-- не задана — результат nil, вызывающий показывает уведомление, а не тихо
-- открывает файл чем-то другим.
-- Позиция есть не у всякой ссылки; без неё файл открывает ОС (target), а заметка
-- хранилища и с позицией идёт в Obsidian — строку он не откроет.
function M.editor_argv(path, position, windows, windows_cli)
  local target = path
  if windows then
    target = path:gsub('/', '\\')
  end
  target = target .. ':' .. position.line
  if position.col ~= nil then
    target = target .. ':' .. position.col
  end
  if windows then
    if windows_cli == nil or windows_cli == '' then
      return nil
    end
    return { 'cmd.exe', '/c', windows_cli, target }
  end
  return { '/usr/local/bin/zed', target }
end

-- Что передать ОС на открытие: Obsidian URI для заметки хранилища, иначе
-- родной путь к файлу.
function M.target(path, windows)
  local native = path
  if windows then
    native = path:gsub('/', '\\')
  end
  if M.is_vault_note(path) then
    return 'obsidian://open?path=' .. M.percent_encode(native)
  end
  return native
end

-- Команда открытия цели для wezterm.background_child_process или nil — тогда
-- цель открывает wezterm.open_with.
-- На Windows obsidian://-адрес, открытый через ОС, доходит до уже запущенного
-- Obsidian, но окно на передний план не выходит — кнопка только мигает на панели
-- задач. Такой адрес открывает script (open_obsidian.ps1): он же активирует
-- окно. Адрес идёт отдельным аргументом -File, без разбора PowerShell.
function M.open_argv(target, windows, script)
  if not windows or target:sub(1, #'obsidian://') ~= 'obsidian://' then
    return nil
  end
  return {
    'powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
    '-File', script, target,
  }
end

return M
