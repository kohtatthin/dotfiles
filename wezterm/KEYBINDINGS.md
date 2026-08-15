# WezTerm キーバインド & 機能ガイド

設定ファイル: `~/dotfiles/wezterm/wezterm.lua`（最終更新: 2026-08-07）

---

## 起動時レイアウト（7ペイン）

WezTerm 起動時に7ペインが自動展開される。比率 = 左2 : 中4 : 右4、上下等分（左カラムのみ3分割）。

**ペイン番号呼称（公式。会話・指示はこの番号で統一）**

```
⑦
⑥　①　②
⑤　④　③
```

### Windows

```
┌──────────┬────────────────────┬──────────────────┐
│⑦Todoist  │① 司令／壁打ち(会社) │② Codex (レビュー) │
├──────────┤                    │                  │
│⑥カレンダー│────────────────────│──────────────────│
├──────────┤④ Grok Build (xAI)  │③ 実行ワーカー(個人)│
│⑤AI使用量 │                    │                  │
└──────────┴────────────────────┴──────────────────┘
```

| ペイン | 内容 |
|--------|------|
| ⑦ | Todoist (`todoist.ps1`) |
| ⑥ | カレンダー (`calendar.ps1`) |
| ⑤ | AI使用量ライブ (`ai_usage_pane.ps1`、30秒周期) |
| ① | 司令／壁打ち（会社Claude、`C:\claude`） |
| ④ | Grok Build（xAI 実行ワーカー） |
| ② | Codex レビュー（会社アカウント） |
| ③ | 実行ワーカー（個人Claude、`C:\tamura`） |

### Mac

| ペイン | 内容 |
|--------|------|
| ⑦ | Todoist (`todoist.sh`) |
| ⑥ | カレンダー (`cal`) |
| ⑤ | lazygit (`~/dotfiles`) |
| ① | 個人Claude 司令／壁打ち |
| ④ | Grok Build（実装ワーカー） |
| ② | Codex レビュー |
| ③ | Shell（テスト・ログ・開発サーバー用） |

※ yazi / lazygit(Win) / Gemini は常駐から外し、F9 ランチャーで随時起動。

---

## ペイン操作

| キー | 機能 |
|------|------|
| `Ctrl+Shift+D` | ペインを横に分割 |
| `Ctrl+Shift+E` | ペインを縦に分割 |
| `Ctrl+Shift+W` | 現在のペインを閉じる（確認あり） |
| `Ctrl+H` / `Ctrl+L` | 左／右のペインへ移動 |
| `Ctrl+K` / `Ctrl+J` | 上／下のペインへ移動 |
| `Ctrl+Shift+Z` | ペインのズーム切替（一時最大化⇔復帰） |
| `F8` | ペイン選択（番号オーバーレイでジャンプ） |

※ `F8` で表示される番号は分割順の pane index。公式呼称①〜⑦とは一致しない。

---

## ランチャーメニュー

**`F9`**（Mac は **`Cmd+Shift+9`** も可）でアプリ選択メニューが開く。現在のペインのプロセスを停止（Ctrl+C×2）し、選んだアプリに切り替える。

- Mac で F9 が効かない場合: Mission Control 等に奪われていることが多い → **`Cmd+Shift+9`** を使うか、`fn+F9`、または システム設定 → キーボード → 「F1、F2 などのキーを標準のファンクションキーとして使用」
- Ctrl+C で終了しない TUI（yazi / lazygit 等は `q` で終了）では手動で終了してから選ぶ

### Windows

| 選択肢 | 起動コマンド |
|--------|-------------|
| Claude Code | `CLAUDE_CONFIG_DIR=~/.claude-personal claude`（個人） |
| Claude Code (会社) | `CLAUDE_CONFIG_DIR=~/.claude claude` |
| Claude Code (Clean) | `CLAUDE_CONFIG_DIR=~/.claude-clean claude --model opus --tools default ...` |
| Claude Code (会社 Clean) | `CLAUDE_CONFIG_DIR=~/.claude-work-clean claude --model opus --tools default ...` |
| Gemini CLI | `cd C:\claude; gemini` |
| Antigravity CLI | `cd C:\claude; agy`（PATHに `%LOCALAPPDATA%\agy\bin` を前置） |
| lazygit | `cd ~/dotfiles; lazygit` |
| Todoist | `todoist.ps1` |
| 📅 カレンダー | `calendar.ps1` |
| Codex CLI (会社) | `codex-account.ps1 -Account work`（`CODEX_HOME=~/.codex-work`、`tamura.k@t-sss.co.jp` を起動前検証） |
| Codex CLI (個人) | `codex-account.ps1 -Account personal`（`CODEX_HOME=~/.codex-personal`、`densontamra@gmail.com` を起動前検証） |
| 🐟 Sakana Fugu | `doppler run --project sakana-ai --config prd -- codex-fugu` |
| 🐡 Sakana Fugu Ultra | `doppler run --project sakana-ai --config prd -- codex-fugu-ultra` |
| Grok Build | `cd C:\claude; grok` |
| 🤖 LLM: Nemotron 9B (壁打ち・日本語) | `lms chat nvidia-nemotron-nano-9b-v2-japanese` |
| 🤖 LLM: Gemma 4 E4B (画像可) | `lms chat google/gemma-4-e4b` |
| 🤖 LLM: Qwen3.6 35B-A3B (コーダー) | `lms chat qwen/qwen3.6-35b-a3b` |
| 🤖 LLM: LFM2.5 2.6B (軽作業・高速) | `lms chat lfm2.5-2.6b` |
| 🛠 LLM Agent: Nemotron 9B | opencode + `lmstudio/nvidia-nemotron-nano-9b-v2-japanese` |
| 🛠 LLM Agent: Gemma 4 E4B | opencode + `lmstudio/google/gemma-4-e4b` |
| 🛠 LLM Agent: Qwen3.6 35B-A3B | opencode + `lmstudio/qwen/qwen3.6-35b-a3b` |
| 🛠 LLM Agent: LFM2.5 2.6B | opencode + `lmstudio/lfm2.5-2.6b` |
| yazi | `yazi` |
| PowerShell | 何もしない（シェルに戻る） |

※ 🤖 は `lms chat`（ファイル操作不可）。🛠 は opencode 経由でファイル読み書き可。modelKey は `lms ls` と `~/.config/opencode/opencode.json` の `provider.lmstudio.models` を揃える。

Mac は Claude 系の CONFIG_DIR 割当と Todoist スクリプトが異なる（Fugu / カレンダー / Codex個人 は Windows のみ）。

### Codexアカウント分離（Windows）

- Codexデスクトップ: 既定の `~/.codex`（個人）。WezTermからは変更しない
- WezTerm会社Codex: `~/.codex-work`
- WezTerm個人Codex / Fugu: `~/.codex-personal`
- 初回または誤アカウント時はデバイスコード認証を開始し、期待するメールアドレスと一致しない限りCodex本体を起動しない
- 認証状態だけ確認: `& $HOME\dotfiles\wezterm\codex-account.ps1 -Account work -CheckOnly`（個人は `work` を `personal` に変更）

---

## クイック起動

| キー | 機能 |
|------|------|
| `Ctrl+Shift+G` | lazygit を起動 |
| `Ctrl+Shift+S` | Todoist を起動 |
| `Alt+Enter` | Claude Code の改行用（ターミナルに渡す） |

---

## 外観の一時変更

`wezterm.lua` は書き換わらず、各メニューの「Reset to default」で即座にデフォルトへ復帰できる。壁紙切替のみ Mac では状態ファイルに保存され次回起動時も復元される（それ以外はセッション限り）。

| メニュー | Windows | macOS |
|----------|---------|-------|
| カラースキーム切替 | `Ctrl+Shift+F1` | `Cmd+Shift+T` |
| 壁紙の明るさ | `Ctrl+Shift+F2` | `Cmd+Shift+B` |
| 壁紙画像の切替 | `Ctrl+Shift+F3`（セッション限り） | `Cmd+Shift+I`（永続化） |
| プロファイル切替（テーマ+壁紙セット） | `Ctrl+Shift+F4` | `Cmd+Shift+P` |

macOS が F1〜F4 を OS 側で奪うため、Mac は Cmd 系に分岐させている。

### カラースキーム

Dark / SF・Cyberpunk / Light あわせて約30種類を切替可能（Tokyo Night, Catppuccin, Dracula, Gruvbox, Nord, SF Terminal, Neuromancer, Holo HUD, Claude Light など）。現在値は `(current)` 表示。ライトテーマ選択時は壁紙を白飛ばし＋背景不透明度を自動調整。

### プロファイル

テーマ・壁紙・明るさ・不透明度をセットで切替。

| ID | 内容 |
|----|------|
| personal | 🏠 Tokyo Night + デフォルト壁紙 |
| work | 🏢 Claude Light、壁紙なし・完全不透明 |
| work-dark | 🏢 Catppuccin Mocha + 海の壁紙 |
| sf-terminal | 🛸 SF Terminal、半透過でデスクトップが透ける |
| neuromancer | 💀 Neuromancer + サイバーパンク壁紙 |
| holo-hud | 🛰 Holo HUD、半透過（HUDが宙に浮く感じ） |

### 壁紙画像

Windows: `~/dotfiles/wezterm/wallpapers/`、Mac: `~/dotfiles/wezterm/wallpapers/mac/` 配下の `jpg/jpeg/png/gif/webp` をメニューを開くたびにスキャン。ファイルを置くだけで反映（再起動不要）。

### 壁紙の明るさ

Very Dark (0.03) 〜 Bright (0.3) の6段階 ＋ No wallpaper。

---

## ステータスライン（AI使用量、Windowsのみ）

右下に Claude（個人/会社のプラン枠使用率、ccusage 近似）と Codex（5h/週）の使用率を表示。

- 表示例: `C 個71% 社-   Cdx 5h50% wk8%`
- 仕組み: `ai_usage.ps1` が `$TEMP\wez_ai_status.txt` に書き出し、WezTerm はそれを読むだけ（UIをブロックしない）。鮮度は⑤ペインの `ai_usage_pane.ps1`（30秒周期）が保ち、古いときのみバックグラウンドで更新を起動。
- Claude 側の重い算出は `ai_usage_refresh.ps1`（ccusage）が detached で実行し `$TEMP\wez_ai_usage.json` にキャッシュ。

---

## 基本設定

| 項目 | 値 |
|------|-----|
| デフォルトカラースキーム | Tokyo Night |
| フォント | UDEV Gothic NF / 12pt |
| デフォルトシェル | PowerShell (Windows) |
| 作業ディレクトリ | `C:/claude` (Windows) / `~/claude` (Mac/Linux) |
| 壁紙の明るさ | 0.1 |
| 文字背景の不透明度 | 0.3（TUIの塗りつぶし越しに壁紙を透かすため。副作用: 色付き背景全般が薄くなる） |
| 設定の自動リロード | 有効 |
