-- agent_links.lua — куда ведёт кубик агента в полосе статусной строки: переписка
-- прогона OpenCode, фоновой сессии Claude Code или стенограмма субагента Claude
-- Code. Схема ссылки своя (M.scheme), рядом с file-line из file_links.lua: ссылку
-- ставит полоса кубиков (tools/statusline, internal/agents) на последнюю строку кубика
-- — ту, где написано, чем агент занят.
--
-- Три вида открываются по-разному, и обещание совпадает с тем, что происходит:
--   • opencode        — прогон OpenCode, сессия известна по id: открывается
--     интерфейсом OpenCode (`opencode --session <id>`);
--   • claude-session  — фоновая сессия Claude Code верхнего уровня: `claude attach
--     <id>` возвращает в живой агент (пока не задан disableAgentView);
--   • claude-subagent — субагент текущей сессии: войти в живого агента снаружи
--     нечем (изнутри это /tasks и Enter), снаружи достижима только стенограмма на
--     диске. Поэтому открывается переписка, отрисованная по-человечески, а не
--     «провал внутрь агента» — обещать второе нельзя.
--
-- Модуль не зависит от wezterm: платформа и путь к отрисовщику стенограммы
-- приходят снаружи, поэтому логика проверяется обычным lua
-- (agent_links_test.lua), а связка с mux — в wezterm.lua.
--
-- Формат ссылки: agent:<вид>:<значение>. Значение — одно поле, и хвоста
-- параметров у него нет: всё, что нужно команде, лежит в самом значении. Путь к
-- стенограмме и id процент-кодируются (пробелы, кириллица).

local file_links = require('file_links')

local M = {}

M.scheme = 'agent'

local function shell_quote(s)
  return "'" .. s:gsub("'", [['\'']]) .. "'"
end

-- Разбор ссылки: { kind, value } либо nil, если схема не наша. Схема проверяется
-- префиксом, а не шаблоном: «-» в M.scheme — спецсимвол шаблонов Lua.
-- Вид неизвестен или значение пустое — это тоже ответ разбора: обработчик
-- отличит «не наша ссылка» от «наша, но открыть нечем» и скажет о втором.
function M.parse(uri)
  local prefix = M.scheme .. ':'
  if uri:sub(1, #prefix) ~= prefix then
    return nil
  end
  local kind, value = uri:sub(#prefix + 1):match('^([%a][%w%-]*):(.*)$')
  if kind == nil then
    return { kind = nil }
  end
  return { kind = kind:lower(), value = file_links.percent_decode(value) }
end

-- Команда для нового окна WezTerm. script — путь к
-- scripts/dev/agent_transcript.py (сосед файла_links, как open_obsidian.ps1 рядом
-- с ним), нужен только стенограмме субагента. nil — открыть нечем: неизвестный
-- вид, пустое значение или отсутствующий отрисовщик.
--
-- Окно, а не background_child_process: `opencode --session`, `claude attach` и
-- пейджер — интерактивные программы, им нужен tty, и живое окно закрывается
-- вместе с ними.
function M.argv(link, windows, script)
  if link == nil or link.value == nil or link.value == '' then
    return nil
  end
  if link.kind == 'opencode' then
    return M.window_argv(windows, 'exec opencode --session ' .. shell_quote(link.value))
  end
  if link.kind == 'claude-session' then
    return M.window_argv(windows, 'exec claude attach ' .. shell_quote(link.value))
  end
  if link.kind == 'claude-subagent' then
    if script == nil then
      return nil
    end
    local python = windows and 'python' or 'python3'
    return M.window_argv(windows, python .. ' ' .. shell_quote(script) .. ' '
      .. shell_quote(link.value) .. ' | less -R')
  end
  return nil
end

-- Окно mux не наследует PATH терминала: opencode, claude и python приходят из
-- профиля оболочки, поэтому команда идёт через интерактивный login-shell — так же,
-- как запускалка (launcher_window.argv). На Windows оболочка — Git Bash.
function M.window_argv(windows, command)
  if windows then
    return { 'C:\\Program Files\\Git\\bin\\bash.exe', '-l', '-i', '-c', command }
  end
  return { '/bin/zsh', '-l', '-i', '-c', command }
end

return M
