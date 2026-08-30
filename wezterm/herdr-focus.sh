#!/bin/bash
# herdr-focus.sh — Herdr のワークスペースを番号で切り替える
# 用法: herdr-focus.sh <番号>   （番号は Herdr の workspace.number。⑤ペインの表示と同じ）
# ⑤ペインのメニューからも、WezTerm の Ctrl+Shift+1/2/3 からも呼ばれる。

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

[ -n "${1:-}" ] || exit 1
command -v herdr >/dev/null 2>&1 || exit 1

ws_id=$(herdr workspace list 2>/dev/null \
  | jq -r --argjson n "$1" '.result.workspaces[] | select(.number==$n) | .workspace_id' \
  | head -1)

[ -n "$ws_id" ] || exit 1
herdr workspace focus "$ws_id" >/dev/null 2>&1
