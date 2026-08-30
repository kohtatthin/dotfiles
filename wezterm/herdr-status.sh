#!/bin/bash
# herdr-status.sh — Mac版 Herdr Cockpit（⑤ペイン用）
# Windows の herdr-status.ps1 と同等。エージェント状態の一覧に加えて、
# ワークスペースの切り替えメニューとして動く（数字キーで focus を移す）。
# 用法: herdr-status.sh [--once]
#   1..9 : その番号のワークスペースへ切り替え（フォーカス中は * 表示）
#   r    : 即時更新   q : 終了
# キー入力が無ければ3秒ごとに自動更新する。

# ---------- PATH の再構成 ----------
# Dock/Finder から起動した WezTerm の子プロセスは PATH が /usr/bin:/bin:/usr/sbin:/sbin だけになる。
# さらに非対話ログインシェルは ~/.zshrc を読まないため codex(.npm-global) や grok(.grok) も落ちる。
# 対話 zsh と同じ並びをここで明示して、herdr も各AI CLI も必ず解決できるようにする（2026-08-30）。
for _d in "$HOME/.local/bin" "$HOME/.npm-global/bin" "$HOME/.grok/bin" \
          "$HOME/.bun/bin" "$HOME/.cargo/bin" \
          /opt/homebrew/bin /opt/homebrew/sbin /usr/local/bin; do
  case ":$PATH:" in
    *":$_d:"*) ;;
    *) [ -d "$_d" ] && PATH="$_d:$PATH" ;;
  esac
done
export PATH
unset _d

if ! command -v herdr >/dev/null 2>&1; then
  echo "Error: herdr が PATH 上に見つからない (PATH=$PATH)" >&2
  exit 1
fi

ONCE=false
for arg in "$@"; do
  case "$arg" in --once) ONCE=true ;; esac
done

FOCUS_SH="$HOME/dotfiles/wezterm/herdr-focus.sh"

# ANSI色
C_CYAN='\033[36m'
C_BCYAN='\033[96;1m'
C_DCYAN='\033[36;2m'
C_YELLOW='\033[33m'
C_RED='\033[31m'
C_GREEN='\033[32m'
C_GRAY='\033[90m'
C_RESET='\033[0m'

color_for_status() {
  case "$1" in
    working) echo "$C_YELLOW" ;;
    blocked) echo "$C_RED" ;;
    done)    echo "$C_GREEN" ;;
    idle)    echo "$C_GRAY" ;;
    *)       echo "$C_RESET" ;;
  esac
}

draw() {
  if ! herdr status server 2>/dev/null | grep -q 'running'; then
    printf '\033[2J\033[H'
    printf "${C_CYAN}HERDR AI COCKPIT${C_RESET}\n"
    printf "${C_RED}サーバー未起動 — 待機中...${C_RESET}\n"
    return
  fi

  local ws_json agent_json
  ws_json=$(herdr workspace list 2>/dev/null)
  agent_json=$(herdr agent list 2>/dev/null)

  printf '\033[2J\033[H'
  printf "${C_CYAN}HERDR AI COCKPIT${C_RESET}\n"
  printf "${C_GRAY}更新 $(date +%H:%M:%S)${C_RESET}\n\n"

  # ワークスペースは番号順。フォーカス中は明るいシアン＋* で示す。
  echo "$ws_json" \
    | jq -r '[.result.workspaces[]] | sort_by(.number) | .[] | "\(.number)\t\(.workspace_id)\t\(.focused)\t\(.label)"' 2>/dev/null \
    | while IFS=$'\t' read -r num ws_id focused label; do
        local pane_json agent_count
        if [ "$focused" = "true" ]; then
          printf "${C_BCYAN}[%s] %s *${C_RESET}\n" "$num" "$label"
        else
          printf "${C_DCYAN}[%s] %s${C_RESET}\n" "$num" "$label"
        fi

        pane_json=$(herdr pane list --workspace "$ws_id" 2>/dev/null)
        agent_count=$(echo "$agent_json" | jq --arg wid "$ws_id" '[.result.agents[] | select(.workspace_id==$wid)] | length' 2>/dev/null)
        if [ "${agent_count:-0}" -eq 0 ]; then
          printf "  ${C_GRAY}（待機スロット）${C_RESET}\n"
          continue
        fi

        # 表示順は pane_id 順（Windows 版の Sort-Object pane_id と合わせる）
        echo "$agent_json" \
          | jq -r --arg wid "$ws_id" '[.result.agents[] | select(.workspace_id==$wid)] | sort_by(.pane_id) | .[] | "\(.pane_id)\t\(.agent_status)\t\(.name // .agent)"' 2>/dev/null \
          | while IFS=$'\t' read -r pane_id status agent_name; do
              local pane_label display_name color
              pane_label=$(echo "$pane_json" | jq -r --arg pid "$pane_id" '.result.panes[] | select(.pane_id==$pid) | .label // empty' 2>/dev/null)
              display_name="${pane_label:-$agent_name}"
              color=$(color_for_status "$status")
              printf "  ${color}%s  %s${C_RESET}\n" "$display_name" "$status"
            done
      done

  printf "\n${C_GRAY}1/2/3: ワークスペース切替（Ctrl+Shift+1/2/3 も可）${C_RESET}\n"
  printf "${C_GRAY}r: 更新  q: 終了${C_RESET}\n"
  printf "${C_GRAY}Ctrl+Shift+H: Herdrを別窓 / F9: ランチャー${C_RESET}\n"
}

while true; do
  draw
  [ "$ONCE" = true ] && break

  # 端末が無い（パイプ等）ときはキー待ちをせず、単純に待つ
  if [ ! -t 0 ]; then
    sleep 3
    continue
  fi

  # 最大3秒キー入力を待つ。タイムアウトしたら再描画するだけ。
  if read -rsn1 -t 3 key; then
    case "$key" in
      [1-9]) bash "$FOCUS_SH" "$key" ;;
      q|Q)   printf '\033[2J\033[H'; break ;;
      *)     ;;   # r を含め、それ以外は即時再描画
    esac
  fi
done
