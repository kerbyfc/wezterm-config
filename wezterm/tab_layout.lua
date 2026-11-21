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
--   • ширина окна, число вкладок, все заголовки, активность и тема те же —
--     возвращаются сохранённые строки, без единого вызова wezterm.column_width;
--   • сменились заголовки, активность или тема, но ширины подписей те же
--     (кадр спиннера) — распределение ширин и строки первого прохода
--     не пересчитываются, пересобираются только изменившиеся вкладки;
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
--   2. Второй проход: format-tab-title для отрисовки. До 19.11.2026 (#7526)
--      max_width был равен длине из первого прохода, теперь — tab_max_width;
--      результат обрезается только до tab_max_width.
-- Поэтому в первом проходе отдаём ширины на `ширина − (вкладок − 1)`, а во
-- втором — на полную ширину: вкладки закрывают всю строку. Цена — у вкладок
-- кроме последней крайняя правая клетка не подсвечивается при наведении.
-- Остаток окна меньше клетки WezTerm красит фоном панели — он равен цвету
-- активной вкладки, чтобы одна вкладка выглядела сплошной.

local wezterm = require('wezterm')

local M = {}

local bar_cells = {} -- window_id -> ширина панели в клетках
-- window_id -> { pass = 1|2, last = tab_index прошлого вызова }: какой проход
-- format-tab-title идёт сейчас, см. M.format.
local passes = {}
local TAB_MAX_WIDTH = 10000
local TITLE_MAX = 48 -- длиннее — обрезается с «…»; ширина вкладки по обрезанному

-- Заголовок панели плагин claude-terminal-title почти всегда начинает с глифа
-- состояния и меняет его много раз в секунду:
--   ◐ ◓ ◑ ◒ — DEFAULT_SPINNER, «работаю» (U+25D0–U+25D3, соседние код-поинты,
--             в UTF-8 — E2 97 90–93, поэтому один байт-шаблон ловит любой кадр);
--   ◍       — DEFAULT_MARKER, «need input»: спиннер встал, ждёт ввода (U+25CD).
-- Сменишь глифы в настройках плагина — поправь шаблоны здесь.
local SPINNER = '\xE2\x97[\x90-\x93]'
local MARKER = '\xE2\x97\x8D'
-- Неактивной вкладке в состоянии «работаю»/«need input» перекращается только
-- текст, активной — и фон, а текст становится чёрным: цветной текст на светлом
-- фоне активной вкладки темы (розовом у Catppuccin Frappe) не читается.
local ACTIVE_TEXT = '#000000'
-- Базовые цвета подсветки — из палитры Catppuccin Frappe; служат значениями
-- по умолчанию, когда палитра темы не нашлась (см. palette ниже).
local SPINNER_COLOR = '#7aa2f7'
local NEED_COLOR = '#ef9f76'

-- Палитра подсветки под тему: синий — ANSI blue темы (ansi[5]), оранжевый —
-- 16-й цвет расширенной палитры (у Catppuccin это peach). Чего в теме нет —
-- из базовых цветов выше. Считается один раз на имя темы; таблицы в кэше
-- раскладки сравниваются по ссылке, поэтому смена темы сама пересобирает
-- строки вкладок.
local palettes = {}
local function palette(schemes, name)
  local key = name or ''
  local p = palettes[key]
  if p ~= nil then return p end
  local scheme = schemes[key] or {}
  local spin, need = SPINNER_COLOR, NEED_COLOR
  if type(scheme.ansi) == 'table' and scheme.ansi[5] ~= nil then spin = scheme.ansi[5] end
  if type(scheme.indexed_colors) == 'table' then
    for _, color in ipairs(scheme.indexed_colors) do
      if color.index == 16 and color.color ~= nil then need = color.color break end
    end
  end
  p = { spin = spin, need = need }
  palettes[key] = p
  return p
end

-- window_id -> раскладка окна:
--   cells, n                   — ширина панели и число вкладок, для которых собрано
--   titles, short, lens        — заголовки, обрезанные до TITLE_MAX и ширины
--                                подписей «N: заголовок» в клетках
--   act                        — активность вкладок: от неё зависят цвета,
--                                поэтому в проверках наравне с titles
--   pal                        — палитра подсветки темы, palette(): от неё
--                                тоже зависят цвета, сравнивается по ссылке
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

-- Цвета вкладки по глифу состояния в её заголовке: крутится спиннер — синий,
-- маркер «need input» — оранжевый, цвета — из палитры темы pal. Неактивной
-- вкладке перекращается только текст, активной — чёрный текст на цветном
-- фоне. Без глифа — nil, остаются цвета темы из colors.tab_bar.
local function tab_colors(title, is_active, pal)
  local color
  if title:find(SPINNER) then
    color = pal.spin
  elseif title:find(MARKER) then
    color = pal.need
  else
    return
  end
  if is_active then return ACTIVE_TEXT, color end
  return color
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
-- чтобы не мерить её заново (она уже известна из раскладки). fg и bg — цвета
-- спиннера, обычно nil: хватает цветов темы из colors.tab_bar; явные
-- Foreground/Background перекрывают только себя, остальное остаётся от темы
-- (tabbar.rs парсит кастомный заголовок поверх атрибутов active/inactive_tab).
local function fit(label, width, len, fg, bg)
  local inner = width - 2
  if inner < 1 then return string.rep(' ', width) end
  if len > inner then
    label = wezterm.truncate_right(label, inner - 1) .. '…'
    len = wezterm.column_width(label)
  end
  local s = ' ' .. label .. string.rep(' ', width - len - 1)
  if fg == nil then return s end
  local items = { { Foreground = { Color = fg } } }
  if bg ~= nil then items[#items + 1] = { Background = { Color = bg } } end
  items[#items + 1] = { Text = s }
  return wezterm.format(items)
end

function M.format(tab, tabs, max_width, pal)
  local win = tab.window_id
  local n = #tabs

  -- Какой это проход. WezTerm зовёт format-tab-title двумя проходами по всем
  -- вкладкам: сначала для замера длин, затем для отрисовки. До 19.11.2026
  -- (#7526) второй проход приходил с max_width = длина из первого, и признаком
  -- служил сам max_width. Теперь оба прохода приходят с tab_max_width, поэтому
  -- проход определяется по порядку вызовов: новый проход начинается с вкладки 0
  -- (у единственной вкладки — каждый вызов). Признак по max_width оставлен,
  -- чтобы работать и на старых сборках.
  local ps = passes[win]
  if ps == nil then ps = { pass = 2 }; passes[win] = ps end
  local first_pass
  if max_width ~= TAB_MAX_WIDTH then
    ps.pass = 2
    first_pass = false
  else
    -- Новый проход начинается с вкладки 0, если прошлый вызов был последней
    -- вкладкой (у единственной вкладки это каждый вызов). n запоминается:
    -- число вкладок могло измениться между пересборками.
    if ps.last == nil or (tab.tab_index == 0 and ps.last == ps.n - 1) then
      ps.pass = ps.pass == 1 and 2 or 1
    end
    first_pass = ps.pass == 1
  end
  ps.last = tab.tab_index
  ps.n = n

  local cells = bar_cells[win]
  if cells == nil then return nil end

  local st = layout[win]

  -- Быстрый путь: ничего не изменилось — раскладка готова.
  if st ~= nil and st.cells == cells and st.n == n and st.pal == pal then
    local same = true
    for i = 1, n do
      if st.titles[i] ~= raw_title(tabs[i]) or st.act[i] ~= tabs[i].is_active then
        same = false break
      end
    end
    if same then
      local i = tab.tab_index + 1
      if first_pass then return st.first[i] end
      return st.full[i]
    end
  end

  if cells < 2 * n then return nil end

  -- Что-то изменилось. Для вкладок с прежним заголовком ширина подписи
  -- берётся из старой раскладки; column_width зовётся только для новых.
  local old = st
  st = { cells = cells, n = n, pal = pal, titles = {}, act = {}, short = {}, lens = {}, full = {} }
  local same_widths = old ~= nil and old.cells == cells and old.n == n
  local weights = {}
  for i = 1, n do
    local title = raw_title(tabs[i])
    st.titles[i] = title
    st.act[i] = tabs[i].is_active
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
    -- со сменившимся заголовком, активностью или темой.
    st.widths = old.widths
    st.first = old.first
    for i = 1, n do
      if old.pal == pal and st.titles[i] == old.titles[i] and st.act[i] == old.act[i] then
        st.full[i] = old.full[i]
      else
        st.full[i] = fit(
          tostring(i) .. ': ' .. st.short[i],
          st.widths[i],
          st.lens[i],
          tab_colors(st.titles[i], st.act[i], pal)
        )
      end
    end
  else
    local widths = distribute(weights, cells)
    st.widths = widths
    st.first = {}
    for i = 1, n do
      st.full[i] = fit(
        tostring(i) .. ': ' .. st.short[i],
        widths[i],
        st.lens[i],
        tab_colors(st.titles[i], st.act[i], pal)
      )
      -- первый проход: на клетку короче у всех, кроме последней
      st.first[i] = string.rep(' ', i < n and widths[i] - 1 or widths[i])
    end
  end
  layout[win] = st

  local i = tab.tab_index + 1
  if first_pass then return st.first[i] end
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

-- schemes — wezterm.color.get_builtin_schemes(): из неё берутся tab_bar темы
-- для colors_for и палитра подсветки по config.color_scheme.
function M.apply(config, schemes)
  config.use_fancy_tab_bar = false
  config.show_new_tab_button_in_tab_bar = false
  config.tab_bar_style = config.tab_bar_style or {}
  config.tab_bar_style.new_tab = '' -- длина (+) вычитается из ширины и у скрытой
  config.tab_bar_style.new_tab_hover = ''
  config.tab_max_width = TAB_MAX_WIDTH -- max_width первого прохода, см. выше
  config.colors = M.colors_for(config.colors, schemes[config.color_scheme or ''])
  wezterm.on('format-tab-title', function(tab, tabs, _, config, _, max_width)
    return M.format(tab, tabs, max_width, palette(schemes, config.color_scheme))
  end)
  wezterm.on('update-status', remember_width)
  wezterm.on('window-resized', remember_width)
end

return M
