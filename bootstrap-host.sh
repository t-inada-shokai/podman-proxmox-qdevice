#!/usr/bin/env bash
# ホスト(ベアメタル)側の前提を確認・設定する。
# ユーザー権限でできるものは実行し、root権限が必要なものはコマンドを表示するだけにする。
# パッケージのインストールは行わない (ディストリビューションごとに異なるため)。
set -euo pipefail

USER_NAME="$(id -un)"
MISSING=0

ok() { echo "[ OK ] $*"; }
todo() { echo "[要対応] $*"; MISSING=1; }

[ "$(id -u)" -ne 0 ] || { echo "エラー: rootではなく、qnetdを動かす一般ユーザーで実行してください" >&2; exit 1; }

# 1. コマンド
for c in podman git age; do
  if command -v "$c" >/dev/null 2>&1; then ok "$c"; else todo "$c をインストールしてください"; fi
done
if podman compose version >/dev/null 2>&1; then
  ok "podman compose (compose provider)"
else
  todo "podman compose が使えません。podman-compose または docker-compose をインストールしてください"
fi

# 2. rootless 用の subuid / subgid
for f in /etc/subuid /etc/subgid; do
  if grep -q "^${USER_NAME}:" "$f" 2>/dev/null; then
    ok "$f に $USER_NAME の範囲あり"
  else
    todo "$f に $USER_NAME がありません: sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER_NAME"
  fi
done

# 3. ログアウト・再起動後もコンテナを動かし続けるための linger
if [ "$(loginctl show-user "$USER_NAME" -p Linger --value 2>/dev/null || true)" = yes ]; then
  ok "linger 有効"
elif loginctl enable-linger "$USER_NAME" 2>/dev/null; then
  ok "linger を有効にしました"
else
  todo "linger を有効にできませんでした: sudo loginctl enable-linger $USER_NAME"
fi

# 4. restart: always をホスト再起動後に効かせる user unit
if systemctl --user enable --now podman-restart.service >/dev/null 2>&1; then
  ok "podman-restart.service (user) 有効"
else
  todo "podman-restart.service (user) を有効にできませんでした: systemctl --user enable --now podman-restart.service"
fi

# 5. ファイアウォール (5403/tcp)
if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
  if firewall-cmd --query-port=5403/tcp >/dev/null 2>&1; then
    ok "firewalld: 5403/tcp 開放済み"
  else
    todo "5403/tcp を開けてください: sudo firewall-cmd --permanent --add-port=5403/tcp && sudo firewall-cmd --reload"
  fi
else
  echo "[確認] firewalld が動いていません。使用中のファイアウォール(nftables/ufw等)で 5403/tcp を許可してください。"
fi

echo
if [ "$MISSING" = 0 ]; then
  echo "ホスト準備は完了です。"
else
  echo "上の [要対応] を済ませてから、もう一度このスクリプトを実行してください。"
  exit 1
fi

# 引数に --start-ssh が指定された場合、10分限定でSSHDを起動する
if [ "${1:-}" = "--start-ssh" ]; then
    CONTAINER_NAME="qnetd"
    TIMEOUT_MINUTES=10

    echo "[+] コンテナ '${CONTAINER_NAME}' 内で SSHD (Port 2222) を一時起動します..."
    podman exec -d "${CONTAINER_NAME}" /usr/sbin/sshd

    echo "[+] SSHD が起動しました。PVE側から pvecm セットアップを実行してください。"
    echo "[!] セキュリティのため、${TIMEOUT_MINUTES}分後にポート2222(SSHD)は自動閉鎖されます。"

    (
        sleep "$((TIMEOUT_MINUTES * 60))"
        echo -e "\n[!] 10分が経過しました。安全のためSSHDを自動閉鎖します。"
        podman exec "${CONTAINER_NAME}" pkill sshd || true
    ) &
    exit 0
fi

echo "使い方: $0 [--start-ssh]"
echo "  --start-ssh  PVEセットアップ用に10分間だけコンテナのSSHDを起動します"
