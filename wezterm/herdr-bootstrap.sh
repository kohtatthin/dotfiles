#!/bin/bash
# herdr-bootstrap.sh — Mac版 Herdr ブートストラップ
# Windows の herdr-bootstrap.ps1 と同等。WezTerm gui-startup からバックグラウンド実行される。
# 用法: herdr-bootstrap.sh [--configure-only] [--skip-extra]

set -euo pipefail

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

CONFIGURE_ONLY=false
SKIP_EXTRA=false
for arg in "$@"; do
  case "$arg" in
    --configure-only) CONFIGURE_ONLY=true ;;
    --skip-extra)     SKIP_EXTRA=true ;;
  esac
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

# ---------- ペイン構築 ----------
# pane_id は "w3:p1" 形式。作成順に採番されるので、番号順に並べれば
# 左上→右上→左下→右下 の並びになる。
sorted_pane_ids() {
  herdr pane list --workspace "$1" 2>/dev/null \
    | jq -r '.result.panes[].pane_id' \
    | sort -t: -k2 -V
}

pane_count() {
  herdr pane list --workspace "$1" 2>/dev/null | jq '.result.panes | length'
}

# ラベルを pane_id 昇順で割り当てる。以降のエージェント起動は
# 並び順ではなくラベルで引く（Windows の Get-PaneByLabel と同じ考え方）。
apply_pane_labels() {
  local ws_id="$1"
  shift
  local i=1 pid
  for label in "$@"; do
    pid=$(sorted_pane_ids "$ws_id" | sed -n "${i}p")
    if [ -n "$pid" ]; then
      herdr pane rename "$pid" "$label" >/dev/null
    fi
    i=$((i + 1))
  done
}

# 不足分は最後のペインを下に割って埋める
fill_panes() {
  local ws_id="$1" want="$2"
  while [ "$(pane_count "$ws_id")" -lt "$want" ]; do
    herdr pane split --pane "$(sorted_pane_ids "$ws_id" | tail -1)" \
      --direction down --no-focus >/dev/null
  done
}

# Core Agents: 2x2 ＋ 右下をもう1段割って Antigravity（計5ペイン）
setup_core_panes() {
  local ws_id="$1" p1 p2 p4
  if [ "$(pane_count "$ws_id")" -eq 1 ]; then
    p1=$(sorted_pane_ids "$ws_id" | sed -n 1p)
    p2=$(herdr pane split --pane "$p1" --direction right --no-focus \
      | jq -r '.result.pane.pane_id')
    herdr pane split --pane "$p1" --direction down --no-focus >/dev/null
    p4=$(herdr pane split --pane "$p2" --direction down --no-focus \
      | jq -r '.result.pane.pane_id')
    herdr pane split --pane "$p4" --direction down --no-focus >/dev/null
  fi
  fill_panes "$ws_id" 5
  apply_pane_labels "$ws_id" \
    "Claude Personal - Commander" "Codex - Review" "Grok Build" "Claude Work" "Antigravity"
}

# Extra Agents: 2x2 の予備枠（Core と同役割の2本目を置く）
setup_extra_panes() {
  local ws_id="$1" p1 p2
  if [ "$(pane_count "$ws_id")" -eq 1 ]; then
    p1=$(sorted_pane_ids "$ws_id" | sed -n 1p)
    p2=$(herdr pane split --pane "$p1" --direction right --no-focus \
      | jq -r '.result.pane.pane_id')
    herdr pane split --pane "$p1" --direction down --no-focus >/dev/null
    herdr pane split --pane "$p2" --direction down --no-focus >/dev/null
  fi
  fill_panes "$ws_id" 4
  apply_pane_labels "$ws_id" \
    "Antigravity - Extra" "Grok - Extra" "Claude Work - Extra" "Codex - Extra"
}

# ---------- メイン ----------

start_server

CORE_WS=$(ensure_workspace "Core Agents")
setup_core_panes "$CORE_WS"

EXTRA_WS=$(ensure_workspace "Extra Agents")
setup_extra_panes "$EXTRA_WS"

LIVE_PANE_IDS=$(live_agent_pane_ids)

# --- Core Agents ---
# ① Claude Personal - Commander
start_agent_if_missing "$(pane_id_by_label "$CORE_WS" 'Claude Personal - Commander')" \
  "Claude Personal - Commander" \
  bash -c 'unset CLAUDE_CONFIG_DIR; cd ~/claude && claude'

# ② Codex - Review
start_agent_if_missing "$(pane_id_by_label "$CORE_WS" 'Codex - Review')" \
  "Codex - Review" \
  bash -c 'cd ~/claude && codex'

# ③ Grok Build
start_agent_if_missing "$(pane_id_by_label "$CORE_WS" 'Grok Build')" \
  "Grok Build" \
  bash -c 'cd ~/claude && grok'

# ④ Claude Work
start_agent_if_missing "$(pane_id_by_label "$CORE_WS" 'Claude Work')" \
  "Claude Work" \
  bash -c 'export CLAUDE_CONFIG_DIR=~/.claude-work; cd ~/claude && claude --model opus'

# ⑤ Antigravity
start_agent_if_missing "$(pane_id_by_label "$CORE_WS" 'Antigravity')" \
  "Antigravity" \
  bash -c 'cd ~/claude && agy'

# --- Extra Agents（Core と同役割の予備枠。--skip-extra で丸ごと省略できる）---
if [ "$SKIP_EXTRA" = false ]; then
  start_agent_if_missing "$(pane_id_by_label "$EXTRA_WS" 'Antigravity - Extra')" \
    "Antigravity - Extra" \
    bash -c 'cd ~/claude && agy'

  start_agent_if_missing "$(pane_id_by_label "$EXTRA_WS" 'Grok - Extra')" \
    "Grok - Extra" \
    bash -c 'cd ~/claude && grok'

  start_agent_if_missing "$(pane_id_by_label "$EXTRA_WS" 'Claude Work - Extra')" \
    "Claude Work - Extra" \
    bash -c 'export CLAUDE_CONFIG_DIR=~/.claude-work; cd ~/claude && claude --model opus'

  start_agent_if_missing "$(pane_id_by_label "$EXTRA_WS" 'Codex - Extra')" \
    "Codex - Extra" \
    bash -c 'cd ~/claude && codex'
fi

herdr workspace focus "$CORE_WS" >/dev/null 2>&1 || true

if [ "$CONFIGURE_ONLY" = false ]; then
  exec herdr
fi
