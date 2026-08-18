# macOS 設定

Mac側で使っている zsh と Git の共通設定です。秘密情報と個人情報は別ファイルに分離します。

## 配置

```sh
ln -s "$HOME/dotfiles/macos/zshrc" "$HOME/.zshrc"
ln -s "$HOME/dotfiles/macos/gitconfig" "$HOME/.gitconfig"
ln -s "$HOME/dotfiles/macos/gitignore_global" "$HOME/.gitignore_global"
```

既存ファイルがある場合は、退避してからシンボリックリンクへ切り替えます。

## ローカル専用設定

`~/.zshrc.local` にAPIキーなどを置きます。このファイルはGitへ追加しません。

```sh
export TODOIST_API_KEY="..."
```

`~/.gitconfig.local` に氏名とメールアドレスを置きます。

```gitconfig
[user]
	name = Your Name
	email = you@example.com
```
