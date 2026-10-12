# podman-proxmox-qdevice

Proxmox VE (PVE) の2ノードクラスタ用クォーラム（定足数）ノード（QDevice / `corosync-qnetd`）を、Raspberry Pi などの軽量な Linux 環境において **Rootless Podman (一般ユーザー権限) コンテナ** で安全かつ簡単に運用するためのリポジトリです。

Proxmox 標準の自動セットアップコマンド (`pvecm qdevice setup`) を、Rootless コンテナ環境に対して「必要な一瞬だけポートを開けて一発貫通」させるための**オンデマンド認証待ち受け（10分自動消滅タイマー）ロジック**を実装しています。

## 特徴
- **Rootless 完全安全運用**: ホストの root 権限を一切使わず、一般ユーザー権限だけで `qnetd` を運用できます。
- **10分限定の認証待ち受け**: セットアップを行う「10分間」だけコンテナ内に SSHD (Port 2222) を立ち上げ、時間が来ると自動でプロセスをキルしてポートを閉鎖するため、固定パスワードのままでも極めて堅牢です。
- **ホストネットワーク対応**: `network_mode: host` を採用し、クラスタノードの送信元 IP を正しく認識させます。

## ディレクトリ構成
```text
.
├── Containerfile         # Debian 12 ベースの qnetd + sshd イメージ定義
├── entrypoint.sh         # コンテナ起動時にNSSDB初期化とSSHD準備（通常はSSHD未起動）
├── docker-compose.yaml   # Podman Compose 用の設定ファイル
├── start-auth-wait.sh    # 認証待ち受け状態を開始するスクリプト（10分タイマー付き）
├── bootstrap-host.sh     # ホスト側の前提条件チェックスクリプト
├── lib.sh                # バックアップ共有スクリプト
├── backup-nssdb.sh       # NSSDBをageで暗号化してGitにバックアップするスクリプト
├── restore-nssdb.sh      # age暗号化からボリュームへNSSDBを復元するスクリプト
└── backup/               # 暗号化されたバックアップデータの格納先
```

## 使い方

### 1. QDevice 側（Raspberry Pi など）での準備

1. 本リポジトリを一般ユーザーのホームディレクトリにクローンし、コンテナを起動します。
   ```bash
   git clone https://github.com/t-inada-shokai/podman-proxmox-qdevice.git
   cd podman-proxmox-qdevice
   podman compose up -d --build
   ```
   *(※この通常稼働状態では、セキュリティのためポート2222(SSHD)は完全に閉じています)*

2. **【セットアップ開始直前】** 以下のスクリプトを実行し、10分間だけ「認証待ち受け状態」にします。
   ```bash
   chmod +x start-auth-wait.sh
   ./start-auth-wait.sh
   ```

---

### 2. Proxmox VE (PVE) 側での設定

1. PVE ノード（作業を行う1台）の `/root/.ssh/config` に以下を追記し、自動ルーティングを仕込みます。
   *(※ `192.168.2.203` は実際の QDevice ホストの IP に書き換えてください)*
   ```text
   Host 192.168.2.203
       Port 2222
       User root
   ```

2. PVE から一度手動で SSH 接続し、ホストキーを承諾します（パスワード: `rootless_qdevice_pass`）。
   ```bash
   ssh root@192.168.2.203
   exit
   ```

3. 自動セットアップコマンドを実行してクラスタに紐付けます。過去に手動構築などを試して古い証明書のゴミが PVE 側に残っているケースが多いため、`-f` オプションを付与して実行します。
   ```bash
   pvecm qdevice setup 192.168.2.203 -f
   ```
   PVE内部のスクリプトが自動でコンテナと通信し、証明書の発行や配置が全自動で完了します。

---

### 3. 後片付けとバックアップ

10分経過すると、**QDevice側のタイマープロセスが自動的にコンテナ内の SSHD をキル（ポート2222を閉鎖）** するため、手動での閉鎖コマンドは不要です。

セットアップ完了後、今回新しく署名された証明書データを安全にGitリポジトリ（age暗号化）に同期するため、ラズパイ側で以下を実行してください。
```bash
./backup-nssdb.sh --commit && git push
```

## ライセンス
[MIT License](LICENSE)
