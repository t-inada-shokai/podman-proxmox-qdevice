FROM docker.io/library/debian:12-slim

# corosync-qnetdに加えて、一時的な接続用のopenssh-serverをインストール
RUN apt-get update \
 && apt-get install -y --no-install-recommends corosync-qnetd openssh-server \
 && rm -rf /var/lib/apt/lists/* /etc/corosync/qnetd/nssdb

# SSH用のランタイムディレクトリを作成
RUN mkdir -p /var/run/sshd

# root ユーザーの仮パスワードを設定 (pvecmのssh-copy-id一時認証用)
RUN echo 'root:rootless_qdevice_pass' | chpasswd

COPY entrypoint.sh /entrypoint.sh
RUN chmod 0755 /entrypoint.sh

EXPOSE 5403 2222
ENTRYPOINT ["/entrypoint.sh"]
