# 共通関数 (backup-nssdb.sh / restore-nssdb.sh から source される)
# shellcheck shell=bash

VOLUME="${VOLUME:-qnetd-data}"
CONTAINER="${CONTAINER:-qnetd}"
# バックアップは公開リポジトリではなく、別の非公開Gitリポジトリのクローンに保存する
BACKUP_DIR="${BACKUP_DIR:-$HOME/qnetd-backup}"
BACKUP_FILE="${BACKUP_FILE:-$BACKUP_DIR/qnetd-data.tar.age}"
DIGEST_FILE="${DIGEST_FILE:-$BACKUP_DIR/qnetd-data.content.sha256}"

die() {
  echo "エラー: $*" >&2
  exit 1
}

need() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "$c コマンドが見つかりません"
  done
}

# 平文のtarを置く作業ディレクトリ。可能ならメモリ上(tmpfs)の XDG_RUNTIME_DIR を使い、
# ディスクに秘密鍵入りの平文を残さないようにする。
WORK=""
make_workdir() {
  WORK="$(mktemp -d -p "${XDG_RUNTIME_DIR:-/tmp}" qnetd-nssdb.XXXXXX)"
}

# tarの「ファイル内容だけ」のダイジェスト。
# tar自体は更新時刻や並び順で毎回変わるため、展開して相対パス順に内容をハッシュする。
content_digest() {
  local tarfile="$1" dir
  dir="$(mktemp -d -p "$WORK" digest.XXXXXX)"
  tar -xf "$tarfile" -C "$dir" --no-same-owner
  (cd "$dir" && find . -type f -print0 | sort -z | xargs -0 -r sha256sum | sha256sum | cut -d' ' -f1)
  rm -rf "$dir"
}
