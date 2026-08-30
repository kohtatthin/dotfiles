#!/bin/bash
# herdr-bootstrap.sh — Mac版 Herdr ブートストラップ
# Windows の herdr-bootstrap.ps1 と同等。WezTerm gui-startup からバックグラウンド実行される。
# 用法: herdr-bootstrap.sh [--configure-only]

set -euo pipefail

CONFIGURE_ONLY=false
for arg in "$@"; do
  case "$arg" in --configure-only) CONFIGURE_ONLY=true ;; esac
done

# ---------- サーバー管理 ----------

test_server() {
  herdr status server 2>/dev/null | grep -q 'running'
}

start_server() {
  if test_server; then return; fi
  nohup herdr server >/dev/null 2>&1 &
  for _ in $(seq 1 40); do
    sleep 0.25
    if test_server; then return; fi
  done
  echo 'Error: Herdr server did not start within 10s' >&2
  exit 1
}

# ---------- JSON ヘルパー ----------

ws_id_by_label() {
  herdr workspace list 2>/dev/null \
    | jq -r --arg l "$1" '.result.workspaces[] | select(.label==$l) | .workspace_id' \
    | head -1
}

pane_id_by_label() {
  herdr pane list --workspace "$1" 2>/dev/null \
    | jq -r --arg l "$2" '.result.panes[] | select(.label==$l) | .pane_id' \
    | head -1
}

first_pane_id() {
  herdr pane list --workspace "$1" 2>/dev/null \
    | jq -r '.result.panes[0].pane_id' \
    | head -1
}

live_agent_pane_ids() {
  herdr agent list 2>/dev/null \
    | jq -r '.result.agents[].pane_id' 2>/dev/null || true
}

# ---------- エージェント起動 ----------

start_agent_if_missing() {
  local pane_id="$1" display_name="$2"
  shift 2
  if [ -z "$pane_id" ]; then
    echo "Required pane is missing: $display_name" >&2
    return 1
  fi
  if echo "$LIVE_PANE_IDS" | grep -qF "$pane_id"; then
    echo "Already running: $display_name"
    return 0
  fi
  echo "Starting: $display_name"
  herdr pane run "$pane_id" "$@"
}

# ---------- ワークスペース構築 ----------

ensure_workspace() {
  local label="$1"
  local ws_id
  ws_id=$(ws_id_by_label "$label")
  if [ -n "$ws_id" ]; then
    echo "$ws_id"
    return
  fi
  echo "Creating workspace: $label" >&2
  herdr workspace create --label "$label" --cwd "$HOME/claude" --no-focus \
    | jq -r '.result.workspace.workspace_id'
}

# 4ペインの2x2グリッドを構築（Core Agents用）
# 戻り値: pane_id を改行区切りで4つ（左上/右上/左下/右下）
setup_core_panes() {
  local ws_id="$1"
  local existing_count
  existing_count=$(herdr pane list --workspace "$ws_id" 2>/dev/null \
    | jq '.result.panes | length')

  if [ "$existing_count" -ge 4 ]; then
    herdr pane list --workspace "$ws_id" 2>/dev/null \
      | jq -r '.result.panes[].pane_id'
    return
  fi

  local p1
  p1=$(first_pane_id "$ws_id")

  # p1(左) | p2(右)
  local p2
  p2=$(herdr pane split --pane "$p1" --direction right --no-focus \
    | jq -r '.result.pane.pane_id')

  # p1(左上) / p3(左下)
  local p3
  p3=$(herdr pane split --pane "$p1" --direction down --no-focus \
    | jq -r '.result.pane.pane_id')

  # p2(右上) / p4(右下)
  local p4
  p4=$(herdr pane split --pane "$p2" --direction down --no-focus \
    | jq -r '.result.pane.pane_id')

  # ペイン名設定
  herdr pane rename "$p1" Claude Personal - Commander >/dev/null
  herdr pane rename "$p2" Codex - Review >/dev/null
  herdr pane rename "$p3" Grok Build >/dev/null
  herdr pane rename "$p4" Claude Work >/dev/null

  echo "$p1"
  echo "$p2"
  echo "$p3"
  echo "$p4"
}

# ---------- メイン ----------

start_server

CORE_WS=$(ensure_workspace "Core Agents")

PANE_IDS=$(setup_core_panes "$CORE_WS")
P_CLAUDE_CMD=$(echo "$PANE_IDS" | sed -n '1p')
P_CODEX=$(echo "$PANE_IDS" | sed -n '2p')
P_GROK=$(echo "$PANE_IDS" | sed -n '3p')
P_CLAUDE_WORK=$(echo "$PANE_IDS" | sed -n '4p')

LIVE_PANE_IDS=$(live_agent_pane_ids)

# Mac のエージェント構成（wezterm.lua の Mac レイアウトと対応）
# ① Claude Personal - Commander
start_agent_if_missing "$P_CLAUDE_CMD" "Claude Personal - Commander" \
  bash -c 'unset CLAUDE_CONFIG_DIR; cd ~/claude && claude'

# ② Codex - Review
start_agent_if_missing "$P_CODEX" "Codex - Review" \
  bash -c 'cd ~/claude && codex'

# ③ Grok Build
start_agent_if_missing "$P_GROK" "Grok Build" \
  bash -c 'cd ~/claude && grok'

# ④ Claude Work
start_agent_if_missing "$P_CLAUDE_WORK" "Claude Work" \
  bash -c 'export CLAUDE_CONFIG_DIR=~/.claude-work; cd ~/claude && claude --model opus'

herdr workspace focus "$CORE_WS" >/dev/null 2>&1 || true

if [ "$CONFIGURE_ONLY" = false ]; then
  exec herdr
fi
