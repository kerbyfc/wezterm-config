-- keybindings.lua — привязки клавиш терминала: Cmd+N (macOS) / Ctrl+N (Windows)
-- — новая вкладка, Cmd/Ctrl+Shift+N — новое окно, Cmd/Ctrl+G — навигатор
-- вкладок. Какой модификатор, решает wezterm.lua (SUPER на macOS, CTRL на
-- Windows) и передаёт снаружи — как открывающему модификатору ссылок и
-- привязке запускалки. Здесь только объявление действий, логики нет;
-- проверка, что привязки попали в config.keys, — smoke.lua.

local wezterm = require('wezterm')
local act = wezterm.action

local M = {}

-- Вкладка наследует домен текущей панели (SpawnTab 'CurrentPaneDomain');
-- окно — домен по умолчанию: в этой версии WezTerm SpawnWindow не принимает
-- аргументов, а документированное его использование — как есть. Cmd+T (по
-- умолчанию — новая вкладка) освобождён: навигатор на Cmd+G, вкладка — на
-- Cmd+N, как новое окно в браузерах — на Cmd+Shift+N.
function M.keys(open_mods)
  return {
    {
      key = 'n',
      mods = open_mods,
      action = wezterm.action_callback(function(window, pane)
        window:perform_action(wezterm.action.SpawnCommandInNewTab {}, pane)
      end),
    },
    { key = 'n', mods = open_mods .. '|SHIFT', action = act.SpawnWindow },
    { key = 'g', mods = open_mods, action = act.ShowTabNavigator },
  }
end

return M
