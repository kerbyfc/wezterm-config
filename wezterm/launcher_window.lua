-- launcher_window.lua — окно запускалки по горячей клавише (Cmd+L на macOS,
-- Ctrl+L на Windows): откуда брать каталог проекта, какой командой запускать, как
-- узнать уже открытое окно. Логика без зависимости от wezterm; связка с mux — в
-- wezterm.lua.
--
-- Запускалка открывается в своём окне WezTerm и одна: вкладка помечена
-- заголовком M.title, повторное нажатие переключает на неё. Закрыл запускалку
-- (q) — процесс вышел, окно закрылось, следующее нажатие откроет новое.

local file_links = require('file_links')

local M = {}

M.title = 'Запускалка'

-- Команду окна задаёт local.lua: function(root, windows) -> argv | nil.
-- Без неё запускалка выключена.
M.command = nil

-- Основной каталог проекта по каталогу панели: корень из local.lua
-- (file_links.repo_split) — из worktree под .claude/worktrees это тоже основной
-- каталог. Панель вне проекта или без известного каталога — nil.
function M.repo_root(cwd)
  if cwd == nil then
    return nil
  end
  return file_links.repo_root((cwd:gsub('\\', '/')))
end

local function shell_quote(s)
  return "'" .. s:gsub("'", [['\'']]) .. "'"
end

-- Команду окна задаёт local.lua. nil — запускалка не настроена.
function M.argv(root, windows)
  if M.command == nil then
    return nil
  end
  return M.command(root, windows)
end

-- Вкладка запускалки среди окон mux (объекты с :tabs(), вкладки — с :get_title()):
-- вкладка и её окно либо nil.
function M.find_tab(mux_windows)
  for _, window in ipairs(mux_windows) do
    for _, tab in ipairs(window:tabs()) do
      if tab:get_title() == M.title then
        return tab, window
      end
    end
  end
  return nil
end

return M
