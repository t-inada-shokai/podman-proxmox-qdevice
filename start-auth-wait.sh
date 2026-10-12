#!/usr/bin/env bash
# start-auth-wait.sh
# PVEセットアップ用に、一定時間だけコンテナのSSHDを起動する(認証待ち受け)。
#   ./start-auth-wait.sh        起動(ランダムパスワードを生成して表示)
#   ./start-auth-wait.sh stop   途中で閉じる
# 期限切れの閉鎖はコンテナ内の timeout が行うため、このスクリプトの終了や
# SSHセッション切断の影響を受けない。
set -euo pipefail

CONTAINER_NAME="${CONTAINER:-qnetd}"
TIMEOUT_MINUTES="${TIMEOUT_MINUTES:-10}"

die() { echo "[x] $*" >&2; exit 1; }

[ "$(podman inspect -f '{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null || true)" = true ] \
  || die "コンテナ ${CONTAINER_NAME} が起動していません"

case "${1:-start}" in
  stop)
    podman exec "${CONTAINER_NAME}" sh -c '
      if [ -s /run/sshd.pid ]; then kill "$(cat /run/sshd.pid)" 2>/dev/null || true; fi
      passwd -l root >/dev/null 2>&1 || true'
    echo "[+] SSHD を閉鎖し、root パスワードをロックしました。"
    exit 0
    ;;
  start) ;;
  *) die "使い方: $0 [start|stop]" ;;
esac

# 二重起動の防止
if podman exec "${CONTAINER_NAME}" sh -c '[ -s /run/sshd.pid ] && kill -0 "$(cat /run/sshd.pid)" 2>/dev/null'; then
  die "既に SSHD が起動中です。'$0 stop' で閉じてから再実行してください"
fi

# 15バイト -> base64で20文字(パディングなし)。+ と / は英字に置換
PASS="$(head -c 15 /dev/urandom | base64 | tr '+/' 'AB')"

# パスワードは標準入力で渡す(プロセス引数に出さない)
printf 'root:%s\n' "${PASS}" | podman exec -i "${CONTAINER_NAME}" chpasswd

# コンテナ内で timeout 付きで sshd を起動し、終了後にrootをロックする
podman exec -d "${CONTAINER_NAME}" sh -c \
  'timeout "$1" /usr/sbin/sshd -D; passwd -l root >/dev/null 2>&1' sh "${TIMEOUT_MINUTES}m"

echo "[+] --------------------------------------------------------"
echo "[+] 認証待ち受けを開始しました (SSHD: ポート 2222)"
echo "[+] 有効期限 : $(date -d "+${TIMEOUT_MINUTES} min" +%H:%M) まで (${TIMEOUT_MINUTES}分)"
echo "[+] 一時パスワード: ${PASS}"
echo "[+] PVE側で ssh と pvecm qdevice setup のパスワード入力にこれを使ってください。"
echo "[+] 期限が来るとsshdは自動終了し、rootパスワードはロックされます。"
echo "[+] --------------------------------------------------------"
