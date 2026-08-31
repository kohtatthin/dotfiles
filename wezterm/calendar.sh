#!/bin/bash
# calendar.sh — ⑥ペイン: Google Calendar アジェンダ（当日+数日）
# Windows の calendar.ps1 と同等。実体は gcal.py（~/.config/gcal/ の資格情報で primary を読む）。
# 初回だけ:  python3 ~/dotfiles/wezterm/gcal.py --auth   でブラウザ同意。
# 未認証でも枠だけは描画され「未認証です」と出る（落ちない）。

GCAL="$HOME/dotfiles/wezterm/gcal.py"

# google-auth 等は system python3 (/usr/bin/python3) 側に入っている。
# Homebrew の python3 を掴むと import に失敗するので実体を明示する。
PY=/usr/bin/python3
[ -x "$PY" ] || PY=$(command -v python3)

while true; do
  printf '\033[2J\033[H\n'
  # gcal.py は google-auth の FutureWarning を stderr に出すので捨てる
  if ! "$PY" "$GCAL" 2>/dev/null; then
    printf '\033[31m  gcal.py 実行エラー\033[0m\n'
    printf '\033[90m  python3 %s で直接確認する\033[0m\n' "$GCAL"
  fi
  printf '\n\033[90m  Refresh: 300s\033[0m\n'
  sleep 300
done
