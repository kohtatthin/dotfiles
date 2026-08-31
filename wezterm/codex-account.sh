#!/bin/bash
# codex-account.sh — Mac版 Codex アカウント切替ランチャー
# Windows の codex-account.ps1 と同等。CODEX_HOME を口座ごとに分離して起動する。
# 用法: codex-account.sh <work|personal> [--check-only] [-- codex に渡す引数...]
#
# work     : 会社アカウント（tamura.k@t-sss.co.jp）  CODEX_HOME=~/.codex-work
# personal : 個人アカウント（densontamra@gmail.com） CODEX_HOME=~/.codex
#            個人側はデスクトップアプリと履歴・resume 状態を共有する。会社側は隔離する。

set -euo pipefail

ACCOUNT="${1:-}"
shift || true

CHECK_ONLY=false
CODEX_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --check-only) CHECK_ONLY=true ;;
    --) shift; CODEX_ARGS+=("$@"); break ;;
    *) CODEX_ARGS+=("$1") ;;
  esac
  shift
done

case "$ACCOUNT" in
  work)
    ACCOUNT_LABEL='WORK'
    ACCOUNT_EMAIL='tamura.k@t-sss.co.jp'
    ACCOUNT_HOME="$HOME/.codex-work"
    ;;
  personal)
    ACCOUNT_LABEL='PERSONAL'
    ACCOUNT_EMAIL='densontamra@gmail.com'
    ACCOUNT_HOME="$HOME/.codex"
    ;;
  *)
    echo "用法: codex-account.sh <work|personal> [--check-only] [-- codex への引数...]" >&2
    exit 2
    ;;
esac

# Codex は login 前に CODEX_HOME を検証し、無いディレクトリを作らない。
# 選んだ側だけを先に作る。
mkdir -p "$ACCOUNT_HOME"

export CODEX_HOME="$ACCOUNT_HOME"
CRED_OVERRIDE='cli_auth_credentials_store="file"'

# Codex Desktop から起動された CLI は親タスクの権限プロファイルを継承し、
# approval_policy=never / sandbox=read-only でローカル読み取りまで拒否することがある。
# 隔離起動の間だけ入れ子セッションの目印を外す。
unset CODEX_APP_TOOLS_PIPE_PATH CODEX_CI CODEX_INTERNAL_ORIGINATOR_OVERRIDE \
      CODEX_SESSION_ID CODEX_THREAD_ID 2>/dev/null || true

# auth.json の id_token(JWT) から email クレームを取り出す
codex_auth_email() {
  local auth_path="$ACCOUNT_HOME/auth.json"
  [ -f "$auth_path" ] || return 0
  python3 - "$auth_path" <<'PYEOF' 2>/dev/null || true
import base64, json, sys

try:
    with open(sys.argv[1], encoding='utf-8') as f:
        auth = json.load(f)
except Exception:
    sys.exit(0)

token = (auth.get('tokens') or {}).get('id_token') or auth.get('id_token')
if not token:
    sys.exit(0)

parts = token.split('.')
if len(parts) < 2:
    sys.exit(0)

payload = parts[1].replace('-', '+').replace('_', '/')
payload += '=' * (-len(payload) % 4)
try:
    claims = json.loads(base64.b64decode(payload).decode('utf-8'))
except Exception:
    sys.exit(0)

email = claims.get('email')
if email:
    print(email)
PYEOF
}

print_header() {
  local color="$1"
  printf '\n%s\n' "$(printf '=%.0s' $(seq 1 68))"
  printf ' CODEX %s: %s\n' "$ACCOUNT_LABEL" "$ACCOUNT_EMAIL"
  printf ' CODEX_HOME: %s\n' "$ACCOUNT_HOME"
  printf '%s\n\n' "$(printf '=%.0s' $(seq 1 68))"
}

ACTUAL_EMAIL="$(codex_auth_email)"

if [ "$CHECK_ONLY" = true ]; then
  if [ "$ACTUAL_EMAIL" = "$ACCOUNT_EMAIL" ]; then
    print_header green
    exit 0
  fi
  if [ -n "$ACTUAL_EMAIL" ]; then
    echo "Account mismatch: expected $ACCOUNT_EMAIL, found $ACTUAL_EMAIL" >&2
  else
    echo "No file-based login found for $ACCOUNT_EMAIL in $ACCOUNT_HOME" >&2
  fi
  exit 1
fi

if [ "$ACTUAL_EMAIL" != "$ACCOUNT_EMAIL" ]; then
  print_header yellow
  if [ -n "$ACTUAL_EMAIL" ]; then
    echo "警告: この隔離プロファイルに別アカウントが入っている: $ACTUAL_EMAIL" >&2
  else
    echo "警告: この隔離プロファイルはまだログインしていない。" >&2
  fi

  if [ "$ACCOUNT" = 'work' ]; then LOGIN_LABEL='browser'; else LOGIN_LABEL='device-code'; fi
  echo "$LOGIN_LABEL ログインを開始する。上に表示したアカウントを選ぶこと。"
  echo 'デスクトップアプリと個人ログインは変更されない。'
  read -r -p "続行する？ [Y/n] " answer
  case "$answer" in
    n|N|no|NO) exit 0 ;;
  esac

  if [ -n "$ACTUAL_EMAIL" ]; then
    codex logout -c "$CRED_OVERRIDE"
  fi

  if [ "$ACCOUNT" = 'work' ]; then
    echo 'ブラウザが個人でサインイン済みなら、ブラウザ側で会社アカウントを選ぶこと。'
    codex login -c "$CRED_OVERRIDE"
  else
    if ! codex login --device-auth -c "$CRED_OVERRIDE"; then
      echo 'device-code ログインに失敗、または無効。' >&2
      read -r -p '通常のブラウザログインを試す？ [Y/n] ' fallback
      case "$fallback" in
        n|N|no|NO) exit 1 ;;
      esac
      codex login -c "$CRED_OVERRIDE"
    fi
  fi

  ACTUAL_EMAIL="$(codex_auth_email)"
  if [ "$ACTUAL_EMAIL" != "$ACCOUNT_EMAIL" ]; then
    echo "ログイン却下: expected $ACCOUNT_EMAIL, found ${ACTUAL_EMAIL:-unknown account}" >&2
    exit 1
  fi
fi

print_header cyan
# macOS 既定の bash 3.2 では set -u 下の空配列展開が unbound variable になるため退避する
exec codex -c "$CRED_OVERRIDE" ${CODEX_ARGS[@]+"${CODEX_ARGS[@]}"}
