-- tab_layout.lua — вкладки ретро-панели растянуты на всю ширину окна.
--
-- Одна вкладка занимает всю строку. Несколько — делят ширину пропорционально
-- длине подписи «N: заголовок» (заголовок — до 48 символов); не влезают —
-- ужимаются в той же пропорции.
--
-- format-tab-title вызывается двумя проходами на каждую вкладку при каждой
-- пересборке панели (wezterm-gui/src/tabbar.rs), а пересборка происходит на
-- каждое изменение любого заголовка: плагины opencode и claude code крутят
-- спиннер в title по много раз в секунду. Кэш раскладки поэтому двухуровневый
-- и отдельный на окно:
--   • ширина окна, число вкладок и все заголовки те же — возвращаются
--     сохранённые строки, без единого вызова wezterm.column_width;
--   • сменились заголовки, но ширины подписей те же (кадр спиннера) —
--     распределение ширин и строки первого прохода не пересчитываются,
--     пересобираются только изменившиеся вкладки;
--   • изменилась хоть одна ширина подписи, число вкладок или ширина окна —
--     полный пересчёт; ширины подписей уцелевших вкладок берутся из кэша.
-- Раскладка хранится на окно, поэтому несколько окон не сбивают кэш друг
-- друга. Ширина панели читается из кэша, который обновляют update-status
-- (раз в status_update_interval) и window-resized. Пока ширина неизвестна
-- (первая секунда после старта или перезагрузки конфига) — штатный заголовок.
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

-- window_id -> раскладка окна:
--   cells, n                   — ширина панели и число вкладок, для которых собрано
--   titles, short, lens        — заголовки, обрезанные до TITLE_MAX и ширины
--                                подписей «N: заголовок» в клетках
--   widths                     — ширины вкладок, distribute(...)
--   first, full                — строки первого и второго прохода
local layout = {}

local function measure_width(window, pane)
  local size = pane:get_dimensions()
  if size.cols == 0 then return nil end
  local cell_width = size.pixel_width / size.cols
  return math.floor(window:get_dimensions().pixel_width / cell_width)
end

local function remember_width(window, pane)
  local ok, cells = pcall(measure_width, window, pane)
  if ok and cells ~= nil then bar_cells[window:window_id()] = cells end
end

-- Заголовок вкладки до обрезки: имя вкладки или заголовок активной панели.
local function raw_title(tab)
  local title = tab.tab_title
  if title == nil or title == '' then title = tab.active_pane.title end
  return title or ''
end

-- Обрезка до TITLE_MAX: усечённый заголовок и его ширина в клетках.
local function shorten(title)
  local width = wezterm.column_width(title)
  if width <= TITLE_MAX then
    return title, width
  end
  -- «…» шириной в клетку плюс обрезанный до TITLE_MAX-1 заголовок
  local short = wezterm.truncate_right(title, TITLE_MAX - 1)
  return short .. '…', wezterm.column_width(short) + 1
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

-- Строка вкладки шириной width: « подпись… ». len — ширина label в клетках,
-- чтобы не мерить её заново (она уже известна из раскладки).
local function fit(label, width, len)
  local inner = width - 2
  if inner < 1 then return string.rep(' ', width) end
  if len > inner then
    label = wezterm.truncate_right(label, inner - 1) .. '…'
    len = wezterm.column_width(label)
  end
  return ' ' .. label .. string.rep(' ', width - len - 1)
end

function M.format(tab, tabs, max_width)
  local win = tab.window_id
  local cells = bar_cells[win]
  if cells == nil then return nil end

  local st = layout[win]
  local n = #tabs

  -- Быстрый путь: ничего не изменилось — раскладка готова.
  if st ~= nil and st.cells == cells and st.n == n then
    local same = true
    for i = 1, n do
      if st.titles[i] ~= raw_title(tabs[i]) then same = false break end
    end
    if same then
      local i = tab.tab_index + 1
      if max_width == TAB_MAX_WIDTH then return st.first[i] end
      return st.full[i]
    end
  end

  if cells < 2 * n then return nil end

  -- Что-то изменилось. Для вкладок с прежним заголовком ширина подписи
  -- берётся из старой раскладки; column_width зовётся только для новых.
  local old = st
  st = { cells = cells, n = n, titles = {}, short = {}, lens = {}, full = {} }
  local same_widths = old ~= nil and old.cells == cells and old.n == n
  local weights = {}
  for i = 1, n do
    local title = raw_title(tabs[i])
    st.titles[i] = title
    local short, len
    if same_widths and old.titles[i] == title then
      short, len = old.short[i], old.lens[i]
    else
      short, len = shorten(title)
      len = #tostring(i) + 2 + len
      if same_widths and old.lens[i] ~= len then same_widths = false end
    end
    st.short[i] = short
    st.lens[i] = len
    weights[i] = len + 2
  end

  if same_widths then
    -- Ширины подписей не изменились — например, кадр спиннера в заголовке:
    -- доли и строки первого прохода те же, пересобираются только вкладки
    -- со сменившимся заголовком.
    st.widths = old.widths
    st.first = old.first
    for i = 1, n do
      if st.titles[i] == old.titles[i] then
        st.full[i] = old.full[i]
      else
        st.full[i] = fit(tostring(i) .. ': ' .. st.short[i], st.widths[i], st.lens[i])
      end
    end
  else
    local widths = distribute(weights, cells)
    st.widths = widths
    st.first = {}
    for i = 1, n do
      st.full[i] = fit(tostring(i) .. ': ' .. st.short[i], widths[i], st.lens[i])
      -- первый проход: на клетку короче у всех, кроме последней
      st.first[i] = string.rep(' ', i < n and widths[i] - 1 or widths[i])
    end
  end
  layout[win] = st

  local i = tab.tab_index + 1
  if max_width == TAB_MAX_WIDTH then return st.first[i] end
  return st.full[i]
end

-- Копия colors с цветами панели под тему scheme (таблица из
-- wezterm.color.get_builtin_schemes(), может быть nil):
--   • фон панели = цвет активной вкладки: остаток окна меньше клетки сливается
--     с вкладкой;
--   • наведение на неактивную вкладку — цвета темы без курсива (умолчание
--     WezTerm включает курсив).
-- Активная вкладка, заданная в самом colors, главнее темы. Нужна и при смене темы на лету —
-- см. выбор темы в config.lua.
function M.colors_for(colors, scheme)
  colors = colors or {}
  local theme = scheme and scheme.tab_bar or {}
  local copy, tab_bar = {}, {}
  for k, v in pairs(colors) do copy[k] = v end
  for k, v in pairs(colors.tab_bar or {}) do tab_bar[k] = v end

  local active = tab_bar.active_tab or theme.active_tab
  tab_bar.background = active and active.bg_color or '#000000'

  local hover = theme.inactive_tab_hover or { bg_color = '#1f1f1f', fg_color = '#909090' }
  tab_bar.inactive_tab_hover = { bg_color = hover.bg_color, fg_color = hover.fg_color, italic = false }

  copy.tab_bar = tab_bar
  return copy
end

-- schemes — wezterm.color.get_builtin_schemes(), чтобы найти тему config.color_scheme.
function M.apply(config, schemes)
  config.use_fancy_tab_bar = false
  config.show_new_tab_button_in_tab_bar = false
  config.tab_bar_style = config.tab_bar_style or {}
  config.tab_bar_style.new_tab = '' -- длина (+) вычитается из ширины и у скрытой
  config.tab_bar_style.new_tab_hover = ''
  config.tab_max_width = TAB_MAX_WIDTH -- признак первого прохода, см. выше
  config.colors = M.colors_for(config.colors, schemes[config.color_scheme or ''])
  wezterm.on('format-tab-title', function(tab, tabs, _, _, _, max_width)
    return M.format(tab, tabs, max_width)
  end)
  wezterm.on('update-status', remember_width)
  wezterm.on('window-resized', remember_width)
end

return M
