-- file_links.lua — куда открывать файл, по которому кликнули в терминале.
--
-- Кликабелен путь к любому файлу с расширением (hyperlink_regex). Правило:
--   • путь с позицией — «путь:строка» или «путь:строка:колонка» — Zed
--     (editor_argv): только он ставит курсор на строку, приложению ОС позицию не
--     передать;
--   • всё остальное — приложением, которое ОС назначила для файла по умолчанию.
--
-- Имя файла без каталога — так его печатают компилятор и тесты Go
-- («card.go:358: …») — от каталога панели не разрешается; такие имена ищет по
-- рабочему дереву opts.find (repo_matches).
--
-- Модуль не зависит от wezterm: файловая система и платформа приходят снаружи
-- в opts, поэтому логика проверяется обычным lua (file_links_test.lua).
--
-- opts = {
--   windows     = boolean,               -- пути Windows: диск, обратные слэши, MSYS
--   home        = string | nil,          -- для путей вида ~/…
--   exists      = function(path) -> bool -- путь в виде «C:/a/b» или «/a/b»
--   find        = function(cwd, name) -> { path }  -- файлы с таким именем в рабочем
--                                        -- дереве каталога cwd
--   windows_cli = string | nil,          -- путь к CLI редактора на Windows
-- }
--
-- Внутри модуля путь всегда с прямыми слэшами; на Windows — с буквой диска в
-- верхнем регистре («C:/Users/…»). Родная форма нужна только на выходе — target.

local M = {}

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
--   2. Путь к любому файлу с расширением, без пробелов: «src/app/x.go»,
--      «README.md», «archive.tar.gz». Расширение начинается с буквы, поэтому
--      числа («0.577», «v1.2») ссылками не становятся.
-- Для обеих:
--   • lookbehind не даёт начать совпадение с середины слова, пути, URL или почты;
--   • внутри пути двоеточие допустимо только в букве диска, а после расширения —
--     хвост позиции «:строка» или «:строка:колонка»: так место в файле печатают
--     компилятор Go, линтеры и агент;
--   • «@» исключён, чтобы не пересекаться со встроенным правилом почты WezTerm.
M.hyperlink_regex = [==[(?<![\w:/\\.~@-])(?:(?:[A-Za-z]:)?[^\s"'`<>|()\[\]{}:*?@]*[/\\](?:(?!\.[A-Za-z][A-Za-z0-9_]*\s)[^\n"'`<>|:*?])*?\.md\b|(?:[A-Za-z]:)?[^\s"'`<>|()\[\]{}:*?@]*[^\s"'`<>|()\[\]{}:*?@/\\.]\.[A-Za-z][A-Za-z0-9_]*\b)(?::[0-9]+(?::[0-9]+)?)?]==]

-- Кодирование/раскодирование %XX: пути из markdown-ссылок и других URI.
function M.percent_decode(s)
  return (s:gsub('%%(%x%x)', function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

-- Кодирует всё, кроме unreserved из RFC 3986 (слэши — %2F, пробелы — %20).
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

-- Редактор, который открывает файл на строке, — Zed: CLI принимает
-- «путь:строка» или «путь:строка:колонка» позиционным аргументом, без ключа.
-- На macOS его ставит действие редактора cli::InstallCliBinary симлинком
-- в /usr/local/bin/zed.
-- На Windows путь CLI Zed не выяснен — это открытый вопрос, путь не угадывается;
-- ветку держит windows_cli из opts, которую задаёт владелец: полный путь к
-- исполняемому файлу, запускается через cmd.exe (работает и для .exe, и для
-- .cmd/.bat). Не задана — результат nil, вызывающий показывает уведомление, а не
-- тихо открывает файл чем-то другим.
-- Позиция есть не у всякой ссылки; без неё файл открывает ОС (target).
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

-- Что передать ОС на открытие: родной путь к файлу.
function M.target(path, windows)
  if windows then
    return path:gsub('/', '\\')
  end
  return path
end

return M
