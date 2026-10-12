#!/usr/bin/env bash
# start-auth-wait.sh
# PVEセットアップ用に、10分間だけコンテナのSSHDを起動して「認証待ち受け状態」にします
set -euo pipefail

CONTAINER_NAME="qnetd"
TIMEOUT_MINUTES=10

echo "[+] --------------------------------------------------------"
echo "[+] Proxmox クラスタ接続のための「認証待機状態」を開始します..."
echo "[+] --------------------------------------------------------"

# コンテナのバックグラウンドで SSHD (Port 2222) を起動
podman exec -d "${CONTAINER_NAME}" /usr/sbin/sshd

echo "[+] コンテナ内での SSHD (Port 2222) の立ち上げに成功しました。"
echo "[+] Proxmox（PVE）側から pvecm qdevice setup を実行してください。"
echo "[!] セキュリティのため、${TIMEOUT_MINUTES}分後にこのポートは自動閉鎖（消滅）します。"

# バックグラウンドで自動閉鎖タイマーを実行
(
    sleep "$((TIMEOUT_MINUTES * 60))"
    echo -e "\n\n[!] [タイマー通知] ${TIMEOUT_MINUTES}分が経過しました。安全のため認証待ち受け状態（ポート2222）を自動閉鎖します。"
    podman exec "${CONTAINER_NAME}" pkill sshd || true
) &

echo "[+] 10分自動閉鎖タイマーがバックグラウンドで始動しました。 (PID: $!)"
