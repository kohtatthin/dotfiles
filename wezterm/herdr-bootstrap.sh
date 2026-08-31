#!/bin/bash
# herdr-bootstrap.sh — Mac版 Herdr ブートストラップ
# Windows の herdr-bootstrap.ps1 と同等の構成（2026-08-31 v2再編で Windows 準拠へ統一）。
# WezTerm gui-startup からバックグラウンド実行される。
# 用法: herdr-bootstrap.sh [--configure-only] [--skip-extra] [--skip-review]
#
#   w1 CORE   : 常用4枠
#   w2 REVIEW : 会社CCによる並列レビュー専用4枠（新設）
#   w3 EXTRA  : 予備枠
#
# レビュー依頼は CORE のセッションから直接行わず、handoff / ai-delegate 経由で
# REVIEW 枠へ渡す（実装セッションに自分の成果をレビューさせない）。

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
SKIP_REVIEW=false
for arg in "$@"; do
  case "$arg" in
    --configure-only) CONFIGURE_ONLY=true ;;
    --skip-extra)     SKIP_EXTRA=true ;;
    --skip-review)    SKIP_REVIEW=true ;;
  esac
done

WORK_ROOT="$HOME/claude"
CODEX_ACCOUNT_SCRIPT="$HOME/dotfiles/wezterm/codex-account.sh"

# ワークスペースは「番号順 = この並び順」で扱う。herdr には並べ替えコマンドが無く、
# 番号は作成順で決まる。新規セッションではこの順に作られ、既存セッションでは
# 不足分が末尾に追加される（順番を正すには herdr server の作り直しが要る）。
WORKSPACE_PLAN=('Core Agents' 'Review Agents' 'Extra Agents')

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

# ---------- ワークスペース ----------

ws_labels_in_order() {
  herdr workspace list 2>/dev/null \
    | jq -r '.result.workspaces | sort_by(.number)[] | .label'
}

ws_ids_in_order() {
  herdr workspace list 2>/dev/null \
    | jq -r '.result.workspaces | sort_by(.number)[] | .workspace_id'
}

ws_id_by_label() {
  herdr workspace list 2>/dev/null \
    | jq -r --arg l "$1" '.result.workspaces[] | select(.label==$l) | .workspace_id' \
    | head -1
}

plan_contains() {
  local needle="$1" item
  for item in "${WORKSPACE_PLAN[@]}"; do
    [ "$item" = "$needle" ] && return 0
  done
  return 1
}

# 計画順にワークスペースを解決する。
#   1. 同じラベルが既にあればそれを使う
#   2. その位置に「計画外のラベル」のワークスペースがあれば採用してリネームする
#      （新規セッションの既定ワークスペースを w1 CORE として拾うため）
#   3. どちらでもなければ新規作成する（既存セッションでは末尾に付く）
resolve_workspace() {
  local index="$1" label="$2" ws_id candidate_id candidate_label

  ws_id=$(ws_id_by_label "$label")
  if [ -n "$ws_id" ]; then
    echo "$ws_id"
    return
  fi

  candidate_id=$(ws_ids_in_order | sed -n "$((index + 1))p")
  candidate_label=$(ws_labels_in_order | sed -n "$((index + 1))p")
  if [ -n "$candidate_id" ] && ! plan_contains "$candidate_label"; then
    echo "Renaming workspace: $candidate_label -> $label" >&2
    herdr workspace rename "$candidate_id" "$label" >/dev/null
    echo "$candidate_id"
    return
  fi

  echo "Creating workspace: $label" >&2
  herdr workspace create --label "$label" --cwd "$WORK_ROOT" --no-focus \
    | jq -r '.result.workspace.workspace_id'
}

# ---------- ペイン ----------
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

pane_id_by_label() {
  herdr pane list --workspace "$1" 2>/dev/null \
    | jq -r --arg l "$2" '.result.panes[] | select(.label==$l) | .pane_id' \
    | head -1
}

# 目標枚数までペインを用意する。既に足りていれば何もしない（冪等）。
init_pane_grid() {
  local ws_id="$1" want="$2" p1 p2
  if [ "$want" -eq 4 ] && [ "$(pane_count "$ws_id")" -eq 1 ]; then
    p1=$(sorted_pane_ids "$ws_id" | sed -n 1p)
    p2=$(herdr pane split --pane "$p1" --direction right --no-focus \
      | jq -r '.result.pane.pane_id')
    herdr pane split --pane "$p1" --direction down --no-focus >/dev/null
    herdr pane split --pane "$p2" --direction down --no-focus >/dev/null
  fi

  # 不足分は最後のペインを下に割って埋める
  while [ "$(pane_count "$ws_id")" -lt "$want" ]; do
    herdr pane split --pane "$(sorted_pane_ids "$ws_id" | tail -1)" \
      --direction down --no-focus >/dev/null
  done
}

# ラベルを pane_id 昇順で割り当てる。以降のエージェント起動は
# 並び順ではなくラベルで引く（herdr pane list の返却順は作成順ではない。2026-08-30の学び）。
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

# ---------- エージェント ----------

live_agent_pane_ids() {
  herdr agent list 2>/dev/null \
    | jq -r '.result.agents[].pane_id' 2>/dev/null || true
}

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

# ---------- メイン ----------

start_server

CORE_WS=$(resolve_workspace 0 'Core Agents')
REVIEW_WS=$(resolve_workspace 1 'Review Agents')
EXTRA_WS=$(resolve_workspace 2 'Extra Agents')

# CORE: Windows 準拠。会社CC / 個人Codex / 個人CC / 会社Codex の2x2。
init_pane_grid "$CORE_WS" 4
apply_pane_labels "$CORE_WS" \
  'Claude Work - Commander' 'Codex Personal - Plan/Build' \
  'Claude Personal - Utility' 'Codex Work - Luna'

# REVIEW: 4枠すべて会社アカウント。並列レビュー前提（2026-08-31 新設）。
init_pane_grid "$REVIEW_WS" 4
apply_pane_labels "$REVIEW_WS" \
  'Claude Work - Review A' 'Claude Work - Review B' \
  'Claude Work - Review C' 'Claude Work - Review D'

# EXTRA: 予備枠。Codex Extra は REVIEW の二次レビュー用に都度使う。
init_pane_grid "$EXTRA_WS" 4
apply_pane_labels "$EXTRA_WS" \
  'Grok' 'Antigravity CLI' 'Claude Work - Extra' 'Codex - Extra'

LIVE_PANE_IDS=$(live_agent_pane_ids)

# Mac のプロファイル対応は Windows と逆:
#   個人 = 既定の ~/.claude / 会社 = ~/.claude-work
CLAUDE_WORK_DIR="$HOME/.claude-work"

# --- CORE ---
start_agent_if_missing "$(pane_id_by_label "$CORE_WS" 'Claude Work - Commander')" \
  'Claude Work - Commander' \
  bash -c "export CLAUDE_CONFIG_DIR=$CLAUDE_WORK_DIR AGMSG_AGENT=commander; cd $WORK_ROOT && claude --model opus --name commander"

start_agent_if_missing "$(pane_id_by_label "$CORE_WS" 'Codex Personal - Plan/Build')" \
  'Codex Personal - Plan/Build' \
  bash -c "export AGMSG_AGENT=codex-sol; cd $WORK_ROOT && $CODEX_ACCOUNT_SCRIPT personal"

start_agent_if_missing "$(pane_id_by_label "$CORE_WS" 'Claude Personal - Utility')" \
  'Claude Personal - Utility' \
  bash -c "unset CLAUDE_CONFIG_DIR; export AGMSG_AGENT=jikko; cd $WORK_ROOT && claude --name jikko"

start_agent_if_missing "$(pane_id_by_label "$CORE_WS" 'Codex Work - Luna')" \
  'Codex Work - Luna' \
  bash -c "export AGMSG_AGENT=codex-luna; cd $WORK_ROOT && $CODEX_ACCOUNT_SCRIPT work"

# --- REVIEW（会社アカウント固定）---
if [ "$SKIP_REVIEW" = false ]; then
  for slot in A B C D; do
    name="review-$(echo "$slot" | tr 'A-Z' 'a-z')"
    start_agent_if_missing "$(pane_id_by_label "$REVIEW_WS" "Claude Work - Review $slot")" \
      "Claude Work - Review $slot" \
      bash -c "export CLAUDE_CONFIG_DIR=$CLAUDE_WORK_DIR AGMSG_AGENT=$name; cd $WORK_ROOT && claude --model opus --name $name"
  done
fi

# --- EXTRA（--skip-extra で丸ごと省略できる）---
if [ "$SKIP_EXTRA" = false ]; then
  start_agent_if_missing "$(pane_id_by_label "$EXTRA_WS" 'Grok')" \
    'Grok' \
    bash -c "cd $WORK_ROOT && grok"

  start_agent_if_missing "$(pane_id_by_label "$EXTRA_WS" 'Antigravity CLI')" \
    'Antigravity CLI' \
    bash -c "cd $WORK_ROOT && agy"

  start_agent_if_missing "$(pane_id_by_label "$EXTRA_WS" 'Claude Work - Extra')" \
    'Claude Work - Extra' \
    bash -c "export CLAUDE_CONFIG_DIR=$CLAUDE_WORK_DIR AGMSG_AGENT=claude-extra; cd $WORK_ROOT && claude --model opus --name claude-extra"

  start_agent_if_missing "$(pane_id_by_label "$EXTRA_WS" 'Codex - Extra')" \
    'Codex - Extra' \
    bash -c "export AGMSG_AGENT=codex-extra; cd $WORK_ROOT && $CODEX_ACCOUNT_SCRIPT work"
fi

herdr workspace focus "$CORE_WS" >/dev/null 2>&1 || true

if [ "$CONFIGURE_ONLY" = false ]; then
  exec herdr
fi
