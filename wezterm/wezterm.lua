local wezterm = require 'wezterm'
local mux = wezterm.mux
local config = {}

-- 最大化で起動
wezterm.on('gui-startup', function(cmd)
  local tab, pane, window = mux.spawn_window(cmd or {})
  window:gui_window():maximize()
end)

config.color_scheme = 'Tokyo Night'
config.automatically_reload_config = true
config.font = wezterm.font('UDEV Gothic NF')
config.font_size = 12
config.default_prog = { 'powershell.exe' }
config.default_cwd = 'C:/claude'
config.initial_cols = 200  -- 横の文字数
config.initial_rows = 50   -- 縦の行数

-- 背景画像設定
config.background = {
  {
    source = { File = 'C:/Users/sss-0/OneDrive - トリプルエス株式会社/画像/壁紙/wallhaven-xlpv8v.jpg' },
    hsb = { brightness = 0.1 },
    opacity = 0.9,
    horizontal_align = 'Center',
    vertical_align = 'Middle',
    repeat_x = 'NoRepeat',
    repeat_y = 'NoRepeat',
  },
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
}

return config