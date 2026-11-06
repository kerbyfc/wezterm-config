-- tab_layout.lua — вкладки ретро-панели растянуты на всю ширину окна.
--
-- Одна вкладка занимает всю строку. Несколько — делят ширину пропорционально
-- длине подписи «N: заголовок» (заголовок — до 48 символов); не влезают —
-- ужимаются в той же пропорции.
--
-- format-tab-title вызывается на каждую перерисовку панели по разу на вкладку,
-- поэтому в нём нет обращений к окну и mux: он читает ширину панели из кэша,
-- а раскладку считает один раз на набор (ширина, подписи). Кэш ширины
-- обновляют update-status (раз в status_update_interval) и window-resized.
-- Пока ширина окна неизвестна (первая секунда после старта или перезагрузки
-- конфига) — штатный заголовок.
--
-- Как WezTerm раскладывает ретро-панель (wezterm-gui/src/tabbar.rs):
--   1. Первый проход: format-tab-title с max_width = tab_max_width; если сумма
--      длин больше `ширина − (вкладок − 1) − длина кнопки (+)`, каждая вкладка
--      обрезается до равной доли. Длина (+) вычитается, даже когда кнопка
--      скрыта, поэтому её текст — пустая строка.
--   2. Второй проход: format-tab-title с max_width = длина из первого прохода;
--      результат обрезается только до tab_max_width.
-- Поэтому в первом проходе отдаём ширины на `ширина − (вкладок − 1)`, а во
-- втором — на полную ширину: вкладки закрывают всю строку. Цена — у вкладок
-- кроме последней крайняя правая клетка не подсвечивается при наведении.
-- Остаток окна меньше клетки WezTerm красит фоном панели — он равен цвету
-- активной вкладки, чтобы одна вкладка выглядела сплошной.

local wezterm = require('wezterm')

local M = {}

local bar_cells = {} -- window_id -> ширина панели в клетках
local TAB_MAX_WIDTH = 10000
local TITLE_MAX = 48 -- длиннее — обрезается с «…»; ширина вкладки по обрезанному
local layout_key, layout_full, layout_first = nil, nil, nil

local function remember_width(window, pane)
  local ok, cells = pcall(function()
    local size = pane:get_dimensions()
    if size.cols == 0 then return nil end
    local cell_width = size.pixel_width / size.cols
    return math.floor(window:get_dimensions().pixel_width / cell_width)
  end)
  if ok and cells ~= nil then bar_cells[window:window_id()] = cells end
end

local function label_of(tab)
  local title = tab.tab_title
  if title == nil or title == '' then title = tab.active_pane.title end
  if wezterm.column_width(title) > TITLE_MAX then
    title = wezterm.truncate_right(title, TITLE_MAX - 1) .. '…'
  end
  return tostring(tab.tab_index + 1) .. ': ' .. title
end

-- Сумма ширин = total, доли пропорциональны весам, остаток от округления
-- раздаётся по наибольшим дробным частям.
local function distribute(weights, total)
  local sum = 0
  for _, w in ipairs(weights) do sum = sum + w end
  local widths, rests, used = {}, {}, 0
  for i, w in ipairs(weights) do
    local exact = total * w / sum
    widths[i] = math.max(1, math.floor(exact))
    rests[i] = { i = i, frac = exact - math.floor(exact) }
    used = used + widths[i]
  end
  table.sort(rests, function(a, b)
    if a.frac ~= b.frac then return a.frac > b.frac end
    return a.i < b.i
  end)
  local k = 1
  while used < total do
    local i = rests[k].i
    widths[i] = widths[i] + 1
    used = used + 1
    k = k % #rests + 1
  end
  return widths
end

local function fit(label, width)
  local inner = width - 2
  if inner < 1 then return string.rep(' ', width) end
  local len = wezterm.column_width(label)
  if len > inner then
    label = wezterm.truncate_right(label, inner - 1) .. '…'
    len = wezterm.column_width(label)
  end
  return ' ' .. label .. string.rep(' ', width - len - 1)
end

function M.format(tab, tabs, max_width)
  local cells = bar_cells[tab.window_id]
  if cells == nil then return nil end

  local labels = {}
  for i, t in ipairs(tabs) do labels[i] = label_of(t) end
  local key = cells .. '\0' .. table.concat(labels, '\0')

  if key ~= layout_key then
    if cells < 2 * #tabs then return nil end
    local weights = {}
    for i, label in ipairs(labels) do weights[i] = wezterm.column_width(label) + 2 end
    local widths = distribute(weights, cells)
    layout_full, layout_first = {}, {}
    for i, label in ipairs(labels) do
      layout_full[i] = fit(label, widths[i])
      -- первый проход: на клетку короче у всех, кроме последней
      layout_first[i] = string.rep(' ', i < #tabs and widths[i] - 1 or widths[i])
    end
    layout_key = key
  end
  local i = tab.tab_index + 1
  if max_width == TAB_MAX_WIDTH then return layout_first[i] end
  return layout_full[i]
end

function M.apply(config)
  config.use_fancy_tab_bar = false
  config.show_new_tab_button_in_tab_bar = false
  config.tab_bar_style = config.tab_bar_style or {}
  config.tab_bar_style.new_tab = '' -- длина (+) вычитается из ширины и у скрытой
  config.tab_bar_style.new_tab_hover = ''
  config.tab_max_width = TAB_MAX_WIDTH -- признак первого прохода, см. выше
  config.colors = config.colors or {}
  config.colors.tab_bar = config.colors.tab_bar or {}
  local active = config.colors.tab_bar.active_tab
  config.colors.tab_bar.background = active and active.bg_color or '#000000'
  wezterm.on('format-tab-title', function(tab, tabs, _, _, _, max_width)
    return M.format(tab, tabs, max_width)
  end)
  wezterm.on('update-status', remember_width)
  wezterm.on('window-resized', remember_width)
end

return M
