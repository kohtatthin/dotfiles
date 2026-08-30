#!/bin/bash
# herdr-status.sh — Mac版 Herdr Cockpit（⑤ペイン用）
# Windows の herdr-status.ps1 と同等。3秒ごとにエージェント状態を表示する。
# 用法: herdr-status.sh [--once]

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

# ANSI色
C_CYAN='\033[36m'
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

while true; do
  if herdr status server 2>/dev/null | grep -q 'running'; then
    WS_JSON=$(herdr workspace list 2>/dev/null)
    AGENT_JSON=$(herdr agent list 2>/dev/null)

    printf '\033[2J\033[H'
    printf "${C_CYAN}HERDR AI COCKPIT${C_RESET}\n"
    printf "${C_GRAY}更新 $(date +%H:%M:%S)${C_RESET}\n\n"

    echo "$WS_JSON" | jq -r '.result.workspaces[].workspace_id' 2>/dev/null | while read -r ws_id; do
      ws_label=$(echo "$WS_JSON" | jq -r --arg id "$ws_id" '.result.workspaces[] | select(.workspace_id==$id) | .label')
      printf "${C_DCYAN}[%s]${C_RESET}\n" "$ws_label"

      PANE_JSON=$(herdr pane list --workspace "$ws_id" 2>/dev/null)

      agent_count=$(echo "$AGENT_JSON" | jq --arg wid "$ws_id" '[.result.agents[] | select(.workspace_id==$wid)] | length' 2>/dev/null)
      if [ "${agent_count:-0}" -eq 0 ]; then
        printf "  ${C_GRAY}（待機スロット）${C_RESET}\n"
        continue
      fi

      # 表示順は pane_id 順（Windows 版の Sort-Object pane_id と合わせる）
      echo "$AGENT_JSON" | jq -r --arg wid "$ws_id" '[.result.agents[] | select(.workspace_id==$wid)] | sort_by(.pane_id) | .[] | "\(.pane_id)\t\(.agent_status)\t\(.name // .agent)"' 2>/dev/null | while IFS=$'\t' read -r pane_id status agent_name; do
        pane_label=$(echo "$PANE_JSON" | jq -r --arg pid "$pane_id" '.result.panes[] | select(.pane_id==$pid) | .label // empty' 2>/dev/null)
        display_name="${pane_label:-$agent_name}"
        color=$(color_for_status "$status")
        printf "  ${color}%s  %s${C_RESET}\n" "$display_name" "$status"
      done
    done

    printf "\n${C_GRAY}Ctrl+Shift+H: Herdrを別窓で開く${C_RESET}\n"
    printf "${C_GRAY}F9: 各CLI ランチャー${C_RESET}\n"
  else
    printf '\033[2J\033[H'
    printf "${C_CYAN}HERDR AI COCKPIT${C_RESET}\n"
    printf "${C_RED}サーバー未起動 — 待機中...${C_RESET}\n"
  fi

  if [ "$ONCE" = true ]; then break; fi
  sleep 3
done
