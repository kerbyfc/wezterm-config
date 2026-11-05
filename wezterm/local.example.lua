return {
  -- Корень проекта для ссылок на заметки Obsidian, worktree и запускалки.
  -- Без него обычные пути и URL открываются, а проектные ссылки выключены.
  project_root = 'C:/Users/you/Projects/your-project',
  vault = 'obsidian',
  obsidian_tree = 'scripts/obsidian-tree.sh',
  -- Схема ссылок статусной строки: agent или своя, если проект пока шлёт другую.
  agent_scheme = 'agent',
  launcher_title = 'Запускалка',
  -- Команда окна запускалки; nil или отсутствие поля — запускалка выключена.
  launcher_command = function(root, windows)
    if windows then
      return { 'cmd.exe', '/c', (root:gsub('/', '\\')) .. '\\scripts\\launch.cmd' }
    end
    return { '/bin/zsh', '-l', '-i', '-c', "exec '" .. root .. "/scripts/launch.sh'" }
  end,
  -- Полный путь к CLI Zed на Windows (ZED_CLI_WINDOWS); не задан — файл с
  -- позицией откроется уведомлением, а не редактором.
  windows_cli = nil,
}
