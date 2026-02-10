local wezterm = require 'wezterm'
local mux = wezterm.mux
local config = {}

-- OS判定
local is_windows = wezterm.target_triple:find('windows') ~= nil

-- 5ペインレイアウトで最大化起動
-- 比率 = 左1 : 中5 : 右2
-- ┌──────┬────────────────────────┬──────────┐
-- │ yazi │     Claude Code        │          │
-- │      │   (プロジェクト実行)     │ Claude   │
-- ├──────┼────────────────────────┤ (壁打ち) │
-- │lazy  │   Sangha Dashboard     │          │
-- │ git  │                        │          │
-- └──────┴────────────────────────┴──────────┘
wezterm.on('gui-startup', function(cmd)
  local tab, pane, window = mux.spawn_window(cmd or {})
  window:gui_window():maximize()

  -- 1) 右端ぶち抜き壁打ちペイン (3/10 = 0.3)
  local chat_pane = pane:split {
    direction = 'Right',
    size = 0.3,
  }

  -- 2) 残りから中央ペインを切り出し (3/4 = 0.75)
  local middle_pane = pane:split {
    direction = 'Right',
    size = 0.75,
  }

  -- 3) 左側を上下に分割（上:yazi、下:lazygit）
  local left_bottom = pane:split {
    direction = 'Bottom',
    size = 0.25,
  }

  -- 4) 中央を上下に分割（上:Claude Code、下:Sangha Dashboard）
  local middle_bottom = middle_pane:split {
    direction = 'Bottom',
    size = 0.4,
  }

  -- 各ペインでコマンド実行
  pane:send_text('yazi\n')

  if is_windows then
    left_bottom:send_text('cd $HOME\\dotfiles; lazygit\n')
    -- 中央: プロジェクトディレクトリでClaude Code（実行者）
    middle_pane:send_text('claude\n')
    middle_bottom:send_text('& "$HOME\\dotfiles\\wezterm\\sangha-dashboard.ps1"\n')
    -- 右: 壁打ち専用ディレクトリでClaude Code
    chat_pane:send_text('cd $HOME\\claude-chat; claude\n')
  else
    left_bottom:send_text('cd ~/dotfiles && lazygit\n')
    middle_pane:send_text('claude\n')
    middle_bottom:send_text('~/dotfiles/wezterm/sangha-dashboard.sh\n')
    chat_pane:send_text('cd ~/claude-chat && claude\n')
  end
end)

config.color_scheme = 'Tokyo Night'
config.automatically_reload_config = true
config.font = wezterm.font('UDEV Gothic NF')
config.font_size = 12
config.initial_cols = 200
config.initial_rows = 50

-- OS別設定
if is_windows then
  config.default_prog = { 'powershell.exe' }
  config.default_cwd = 'C:/claude'
  config.background = {
    {
      source = { File = wezterm.home_dir .. '/dotfiles/wezterm/wallpaper_win.jpg' },
      hsb = { brightness = 0.1 },
      opacity = 0.9,
      horizontal_align = 'Center',
      vertical_align = 'Middle',
      repeat_x = 'NoRepeat',
      repeat_y = 'NoRepeat',
    },
  }
else
  config.default_cwd = wezterm.home_dir .. '/claude'
  config.background = {
    {
      source = { File = wezterm.home_dir .. '/dotfiles/wezterm/wallpaper.jpg' },
      hsb = { brightness = 0.1 },
      opacity = 0.9,
      horizontal_align = 'Center',
      vertical_align = 'Middle',
      repeat_x = 'NoRepeat',
      repeat_y = 'NoRepeat',
    },
  }
end

-- ダッシュボード起動コマンド
local dashboard_cmd
if is_windows then
  dashboard_cmd = '& "$HOME\\dotfiles\\wezterm\\sangha-dashboard.ps1"\r\n'
else
  dashboard_cmd = '~/dotfiles/wezterm/sangha-dashboard.sh\r\n'
end

-- モデル指定解除
  config.set_environment_variables = {
    ANTHROPIC_MODEL = '',
  }

-- キーバインド
config.keys = {
  { key = 'd', mods = 'CTRL|SHIFT', action = wezterm.action.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = 'e', mods = 'CTRL|SHIFT', action = wezterm.action.SplitVertical { domain = 'CurrentPaneDomain' } },
  { key = 'h', mods = 'CTRL', action = wezterm.action.ActivatePaneDirection 'Left' },
  { key = 'l', mods = 'CTRL', action = wezterm.action.ActivatePaneDirection 'Right' },
  { key = 'k', mods = 'CTRL', action = wezterm.action.ActivatePaneDirection 'Up' },
  { key = 'j', mods = 'CTRL', action = wezterm.action.ActivatePaneDirection 'Down' },
  { key = 'w', mods = 'CTRL|SHIFT', action = wezterm.action.CloseCurrentPane { confirm = true } },
  -- Quick launch: lazygit (Ctrl+Shift+G)
  { key = 'g', mods = 'CTRL|SHIFT', action = wezterm.action.SendString('cd ~/dotfiles; lazygit\r\n') },
  -- Quick launch: Sangha Dashboard (Ctrl+Shift+S)
  { key = 's', mods = 'CTRL|SHIFT', action = wezterm.action.SendString(dashboard_cmd) },
}

return config
