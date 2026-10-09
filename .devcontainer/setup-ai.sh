#!/usr/bin/env bash
# zerocode: AI エージェント（Claude Code と Codex）をこの作業部屋に用意する。
# 作業部屋を作るときに devcontainer.json の onCreateCommand から実行される。
# 前からある作業部屋では、教材の準備コマンド（curl ... | bash）で同じものを実行する。
# 何度実行してもよく、途中で失敗しても必ず 0 で終える（作業部屋は開けるようにする）。

set -u
export PATH="$HOME/.local/bin:$PATH"

CODEX_VERSION="0.157.1"
LOG="$HOME/.zerocode-setup-ai.log"
TMP_DIR="$(mktemp -d)"
: > "$LOG"

failed=0
note() { printf '[zerocode] %s\n' "$1"; }
fail() { note "$1（くわしくは $LOG）"; failed=1; }

# 作業フォルダ（Codex に信頼させる場所）。テンプレートから作れば /workspaces/zerocode になる
workspace="${CODESPACE_VSCODE_FOLDER:-}"
if [ -z "$workspace" ] && [ -f "${BASH_SOURCE[0]:-}" ]; then
  workspace="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
if [ -z "$workspace" ]; then
  workspace="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

# 1. Claude Code（stable チャンネル）
if ! command -v claude >/dev/null 2>&1; then
  note "Claude Code を入れています"
  if curl -fsSL https://claude.ai/install.sh -o "$TMP_DIR/claude-install.sh" >>"$LOG" 2>&1 \
    && bash "$TMP_DIR/claude-install.sh" stable </dev/null >>"$LOG" 2>&1; then
    :
  else
    fail "Claude Code を入れられませんでした"
  fi
fi

# 2. Codex（版を固定する。インストーラは /dev/tty を読むので、問いを出さない設定にする）
if ! command -v codex >/dev/null 2>&1; then
  note "Codex を入れています"
  if curl -fsSL https://chatgpt.com/codex/install.sh -o "$TMP_DIR/codex-install.sh" >>"$LOG" 2>&1 \
    && CODEX_NON_INTERACTIVE=1 CODEX_RELEASE="$CODEX_VERSION" sh "$TMP_DIR/codex-install.sh" </dev/null >>"$LOG" 2>&1; then
    :
  else
    fail "Codex を入れられませんでした"
  fi
fi

# 3. 新しく開くターミナルでも使えるようにする（前からある作業部屋にも効かせる）
#    BROWSER を空にするのは、Claude Code のログインで VS Code の「開く」の窓を出さないため
#    （開いた先は localhost に戻れず失敗する。空なら、押せるアドレスだけがターミナルに出る）
for rc in "$HOME/.bashrc" "$HOME/.profile"; do
  for line in 'export PATH="$HOME/.local/bin:$PATH"' 'export CLAUDE_CODE_IDE_SKIP_AUTO_INSTALL=1' 'export BROWSER='; do
    grep -qxF "$line" "$rc" 2>/dev/null || printf '%s\n' "$line" >> "$rc"
  done
done

# 4. ホームの決まり（Claude Code と Codex で同じもの）
mkdir -p "$HOME/.claude" "$HOME/.codex/rules"
cat > "$HOME/.claude/CLAUDE.md" <<'EOF'
# この作業部屋での決まり（zerocode）

この作業部屋では、プログラミングをはじめて学ぶ人が、教材に沿って練習とチャットアプリづくりをしています。

## 話し方
- 日本語で、短く答える。専門用語を使うときは一言そえる
- ファイルを変えたら、最後に「どのファイルの、どのあたりを、何のために変えたか」を箇条書きで伝える
- 決めないといけないことがあれば、書き始める前に1つずつ質問する。質問は、短い言葉で答えられる形にする

## してよいこと・しないこと
- 頼まれていないファイルは変えない。頼まれていない機能は作らない
- git のコマンドは使わない（保存も、元に戻すのも学習者が行う）。元に戻すように頼まれたら、自分が書き替えた行をファイルの上で書き戻す
- 次のコマンドは実行しない: php artisan migrate:fresh・migrate:refresh・migrate:reset・db:wipe（学習者が送ったデータが消える）、php artisan tinker、php artisan serve（学習者が別のターミナルで動かしている）、php artisan optimize・config:cache・route:cache・view:cache（あとで書き替えた設定が効かなくなる）、npm・npx・nvm・composer require
- php artisan migrate:rollback は、何が消えるかを説明して、学習者の返事を待ってから実行する
- ファイルを消すときは、消す理由を先に伝える
- シーダーは php artisan db:seed --class=名前 の形で、1回だけ実行する。確かめるために実行し直さない
- .env の中身を画面に出さない・変えない。パスワードやメールアドレスを書かない
- ログインのパッケージ（Breeze・Jetstream など）、WebSocket、外部のサービス、Laravel Boost は入れない

## practice フォルダの中のファイルだけに当てはめること（chat-app には当てはめない）
- HTML は1枚のファイルに書く。div・header・main は使わない。CSS は同じファイルの head の style に書き、色は英語の色名で書く。JavaScript は使わない
- PHP は、文字を単引用符で書き、改行は echo "\n"; で入れる。最後の ?> は書かない
- PHP のファイルを作ったら実行はせず、実行するコマンドを1行だけ伝える（実行は学習者がする）
EOF
cp "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md"

# 5. Claude Code の設定
cat > "$HOME/.claude/settings.json" <<'EOF'
{
  "language": "japanese",
  "theme": "light",
  "autoUpdatesChannel": "stable",
  "autoMemoryEnabled": false,
  "disableClaudeAiConnectors": true,
  "permissions": {
    "defaultMode": "acceptEdits",
    "disableBypassPermissionsMode": "disable",
    "disableAutoMode": "disable",
    "ask": [
      "Bash(rm *)",
      "Bash(rmdir *)",
      "Bash(php artisan migrate:rollback *)"
    ],
    "deny": [
      "Bash(php artisan migrate:fresh *)",
      "Bash(php artisan migrate:refresh *)",
      "Bash(php artisan migrate:reset *)",
      "Bash(php artisan db:wipe *)",
      "Bash(php artisan tinker *)",
      "Bash(php artisan serve *)",
      "Bash(php artisan optimize *)",
      "Bash(php artisan config:cache *)",
      "Bash(php artisan route:cache *)",
      "Bash(php artisan view:cache *)",
      "Bash(git commit *)",
      "Bash(git push *)",
      "Bash(git checkout *)",
      "Bash(git restore *)",
      "Bash(git reset *)",
      "Bash(git stash *)",
      "Bash(git clean *)",
      "Bash(npm *)",
      "Bash(npx *)",
      "Bash(nvm *)",
      "Bash(composer require *)",
      "Read(**/.env)",
      "Edit(**/.env)"
    ]
  }
}
EOF

# Claude Code の初回の案内（色・ログイン方法）とフォルダの信頼の問いを済ませておく。
# ログインは claude auth login で行う（起動画面からのログインは、ブラウザ版の作業部屋では終わらない）。
# このファイルはインストーラが作り、ログインの情報も持つので、中身は残して印だけを足す
[ -s "$HOME/.claude.json" ] || echo '{}' > "$HOME/.claude.json"
if jq --arg ws "$workspace" '.hasCompletedOnboarding = true
    | .fullscreenUpsellSeenCount = 3
    | .projects[$ws].hasTrustDialogAccepted = true
    | .projects[$ws + "/chat-app"].hasTrustDialogAccepted = true' \
    "$HOME/.claude.json" > "$TMP_DIR/claude.json" 2>>"$LOG"; then
  cat "$TMP_DIR/claude.json" > "$HOME/.claude.json"
else
  fail "Claude Code の初回の設定を書けませんでした"
fi

# 6. Codex の設定（作業フォルダと、その下の chat-app を信頼する）
#    Codespaces のコンテナではサンドボックスが使えない（ユーザー名前空間を作れない）ので、
#    作業部屋そのものを囲いにする。確認は approval_policy と rules で出す
cat > "$HOME/.codex/config.toml" <<EOF
sandbox_mode = "danger-full-access"
approval_policy = "on-request"
check_for_update_on_startup = false

[notice]
hide_full_access_warning = true

[projects."$workspace"]
trust_level = "trusted"

[projects."$workspace/chat-app"]
trust_level = "trusted"
EOF

cat > "$HOME/.codex/rules/zerocode.rules" <<'EOF'
prefix_rule(pattern = ["php", "artisan", "migrate:fresh"], decision = "forbidden", justification = "学習者が送ったデータが消えるため。新しいマイグレーションを足して php artisan migrate を使う")
prefix_rule(pattern = ["php", "artisan", "migrate:refresh"], decision = "forbidden", justification = "学習者が送ったデータが消えるため")
prefix_rule(pattern = ["php", "artisan", "migrate:reset"], decision = "forbidden", justification = "学習者が送ったデータが消えるため")
prefix_rule(pattern = ["php", "artisan", "db:wipe"], decision = "forbidden", justification = "学習者が送ったデータが消えるため")
prefix_rule(pattern = ["php", "artisan", "serve"], decision = "forbidden", justification = "サーバーは学習者が別のターミナルで動かしている")
prefix_rule(pattern = ["php", "artisan", "tinker"], decision = "forbidden", justification = "対話の画面で止まるため")
prefix_rule(pattern = ["php", "artisan", "optimize"], decision = "forbidden", justification = "あとで書き替えた設定が効かなくなる")
prefix_rule(pattern = ["php", "artisan", "config:cache"], decision = "forbidden", justification = "あとで書き替えた設定が効かなくなる")
prefix_rule(pattern = ["php", "artisan", "route:cache"], decision = "forbidden", justification = "あとで書き替えた住所が効かなくなる")
prefix_rule(pattern = ["php", "artisan", "view:cache"], decision = "forbidden", justification = "あとで書き替えた画面が効かなくなる")
prefix_rule(pattern = ["git", "commit"], decision = "forbidden", justification = "保存は学習者が行う")
prefix_rule(pattern = ["git", "push"], decision = "forbidden", justification = "保存は学習者が行う")
prefix_rule(pattern = ["git", "checkout"], decision = "forbidden", justification = "学習者がまだ記録していない行まで戻るため")
prefix_rule(pattern = ["git", "restore"], decision = "forbidden", justification = "学習者がまだ記録していない行まで戻るため")
prefix_rule(pattern = ["git", "reset"], decision = "forbidden", justification = "学習者がまだ記録していない行まで戻るため")
prefix_rule(pattern = ["git", "stash"], decision = "forbidden", justification = "学習者がまだ記録していない行まで戻るため")
prefix_rule(pattern = ["git", "clean"], decision = "forbidden", justification = "学習者のファイルが消えるため")
prefix_rule(pattern = ["npm"], decision = "forbidden", justification = "この教材は npm を使わない")
prefix_rule(pattern = ["npx"], decision = "forbidden", justification = "この教材は npm を使わない")
prefix_rule(pattern = ["nvm"], decision = "forbidden", justification = "この教材は Node を使わない")
prefix_rule(pattern = ["composer", "require"], decision = "forbidden", justification = "パッケージは足さない")
prefix_rule(pattern = ["php", "artisan"], decision = "prompt", justification = "学習者がコマンドを読んでから実行する")
prefix_rule(pattern = ["rm"], decision = "prompt", justification = "消す前に学習者が確かめる")
prefix_rule(pattern = ["git"], decision = "prompt", justification = "git は学習者が扱う")
EOF

# 7. Codex がルールを読めるか
if command -v codex >/dev/null 2>&1; then
  if ! codex execpolicy check --rules "$HOME/.codex/rules/zerocode.rules" php artisan migrate:fresh >>"$LOG" 2>&1; then
    fail "Codex のルールを読めませんでした"
  fi
fi

rm -rf "$TMP_DIR"
printf 'setup-ai: %s 秒\n' "$SECONDS" >>"$LOG"
if [ "$failed" -eq 0 ]; then
  echo "AI の準備ができました。source ~/.bashrc を実行してから使ってください"
else
  echo "AI の準備が終わりませんでした。少し待ってから、同じコマンドをもう一度実行してください"
fi
exit 0
