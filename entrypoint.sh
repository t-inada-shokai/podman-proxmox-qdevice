#!/bin/sh
set -eu

NSSDB=/etc/corosync/qnetd/nssdb

if [ ! -d "$NSSDB" ]; then
  echo "[entrypoint] 警告: nssdb が存在しないため新規に初期化します。" >&2
  corosync-qnetd-certutil -i
fi

# 実行時ディレクトリとボリュームの権限調整
mkdir -p /var/run/corosync-qnetd
chown coroqnetd:coroqnetd /var/run/corosync-qnetd 2>/dev/null || true
chown -R coroqnetd:coroqnetd /etc/corosync/qnetd 2>/dev/null || true

# SSH用のホストキー生成と最小限の設定（オンデマンド起動用の準備のみ）
ssh-keygen -A

# 通常時はrootパスワードログインを不可にする(パスワードは start-auth-wait.sh が一時的に設定する)
passwd -l root >/dev/null 2>&1 || true

cat << 'EOF' > /etc/ssh/sshd_config
Port 2222
ListenAddress 0.0.0.0
PermitRootLogin yes
PasswordAuthentication yes
LoginGraceTime 30
MaxAuthTries 3
Subsystem sftp /usr/lib/openssh/sftp-server
EOF

# 通常時は sshd を起動せず、そのまま qnetd を実行
exec corosync-qnetd -f "$@"
