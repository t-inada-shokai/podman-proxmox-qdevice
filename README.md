# podman-proxmox-qdevice

Proxmox VE (PVE) の2ノードクラスタ用クォーラム（定足数）ノード（QDevice / `corosync-qnetd`）を、Raspberry Pi などの軽量な Linux 環境において **Rootless Podman (一般ユーザー権限) コンテナ** で安全かつ簡単に運用するためのリポジトリです。

Proxmox 標準の自動セットアップコマンド (`pvecm qdevice setup`) を、Rootless コンテナ環境に対して「必要な一瞬だけポートを開けて一発貫通」させるための**オンデマンド認証待ち受け（10分自動消滅タイマー）ロジック**を実装しています。

## 特徴
- **Rootless 安全運用**: コンテナの実行にホストのroot権限は使いません（初期のホスト設定だけroot権限が必要です）。
- **10分限定の認証待ち受け**: セットアップを行う「10分間」だけコンテナ内に sshd (Port 2222) を立ち上げ、実行毎にランダムな一時パスワードを生成し、期限がくるとsshdが自動終了してrootパスワードがロックされます。
- **ホストネットワーク対応**: `network_mode: host` を採用し、クラスタノードの送信元 IP を正しく認識させます。

## ディレクトリ構成
```text
.
├── Containerfile         # Debian 13(trixie) ベースの qnetd + sshd イメージ定義
├── entrypoint.sh         # コンテナ起動時にNSSDB初期化とsshd準備（通常はsshd未起動）
├── docker-compose.yaml   # Podman Compose 用の設定ファイル
├── start-auth-wait.sh    # 認証待ち受け状態を開始するスクリプト（10分タイマー付き）
├── bootstrap-host.sh     # ホスト側の前提条件チェックスクリプト
├── lib.sh                # バックアップ共有スクリプト
├── backup-nssdb.sh       # NSSDBをageで暗号化してGitにバックアップするスクリプト
└── restore-nssdb.sh      # age暗号化からボリュームへNSSDBを復元するスクリプト
```

## 使い方

### 1. QDevice 側（Raspberry Pi など）での準備

1. 本リポジトリを一般ユーザーのホームディレクトリにクローンします。
   ```bash
   git clone https://github.com/t-inada-shokai/podman-proxmox-qdevice.git
   cd podman-proxmox-qdevice
   ```

2. 動作環境の検証をします。検証結果が表示されるので適宜対処してください。
   ```bash
   ./bootstrap-host.sh
   ```

3. コンテナを実行します。
   ```bash
   podman compose up -d --build
   ```
   *(※この通常稼働状態では、セキュリティのためポート2222(sshd)は完全に閉じています)*

4. **【セットアップ開始直前】** 以下のスクリプトを実行し、10分間だけ「認証待ち受け状態」にします。
   ```bash
   ./start-auth-wait.sh
   ```

---

### 2. Proxmox VE (PVE) 側での設定

1. PVE ノード（作業を行う1台）の `/root/.ssh/config` に以下を追記し、自動ルーティングを仕込みます。
   *(※ `192.168.xxx.xxx` は実際の QDevice ホストの IP に書き換えてください)*
   ```text
   Host 192.168.xxx.xxx
       Port 2222
       User root
   ```

2. PVE から一度手動で SSH 接続し、ホストキーを承諾します（パスワード: `start-auth-wait.sh` が表示した一時パスワード）。
   ```bash
   ssh root@192.168.xxx.xxx
   exit
   ```

3. 自動セットアップコマンドを実行してクラスタに紐付けます。過去に手動構築などを試して古い証明書のゴミが PVE 側に残っているケースが多いため、`-f` オプションを付与して実行します。
   ```bash
   pvecm qdevice setup 192.168.xxx.xxx -f
   ```
   PVE内部のスクリプトが自動でコンテナと通信し、証明書の発行や配置が全自動で完了します。

---

### 3. 後片付けとバックアップ

10分経過すると、コンテナ内のタイマーが sshd を終了（ポート2222を閉鎖）し、root パスワードをロックします。途中で閉じるには `./start-auth-wait.sh stop` を実行します。
PVE 側の `/root/.ssh/config` に追記した `Host 192.168.xxx.xxx` の記述は、セットアップ後に削除してください。

NSSDB(秘密鍵を含む)は **公開リポジトリではなく、別の非公開リポジトリ** にバックアップします。

```bash
# 初回のみ: age の鍵を作り、秘密鍵はリポジトリ外(紙やオフライン媒体)にも保管する
mkdir -p ~/.config/age
age-keygen -o ~/.config/age/qnetd.key
age-keygen -y ~/.config/age/qnetd.key > recipients.txt

# 初回のみ: 非公開リポジトリを clone しておく(既定の保存先は ~/qnetd-backup)
git clone <非公開リポジトリのURL> ~/qnetd-backup

# バックアップ
./backup-nssdb.sh --commit && git -C ~/qnetd-backup push
```

復元は `./restore-nssdb.sh --up` です(`~/.config/age/qnetd.key` が必要です)。


## ライセンス
[MIT License](LICENSE)
