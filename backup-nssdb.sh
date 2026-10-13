#!/usr/bin/env bash
# qnetd-data ボリューム(nssdb)を export し、age で暗号化して 非公開リポジトリに保存する。
# 平文のtarは tmpfs 上(XDG_RUNTIME_DIR)にだけ置き、終了時に削除する。
set -euo pipefail

cd "$(dirname "$0")"
# shellcheck source=lib.sh
. ./lib.sh

RECIPIENTS="${RECIPIENTS:-recipients.txt}"
FORCE=0
COMMIT=0
STOP=0

usage() {
  cat <<EOF
使い方: $0 [--stop] [--commit] [--force]
  --stop    export の間だけコンテナを停止する(DBの整合性を厳密に取りたい場合)
  --commit  保存後に git add / commit まで行う(pushは行わない)
  --force   内容に変更がなくても保存し直す
環境変数: VOLUME(既定 qnetd-data) CONTAINER(既定 qnetd) RECIPIENTS(既定 recipients.txt)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --stop) STOP=1 ;;
    --commit) COMMIT=1 ;;
    --force) FORCE=1 ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

need podman age tar sha256sum find sort xargs

# 保存先が、このスクリプトのある(公開)リポジトリと同じなら中止する
SELF_TOP="$(git rev-parse --show-toplevel 2>/dev/null || true)"
BACKUP_TOP="$(git -C "$(dirname "$BACKUP_FILE")" rev-parse --show-toplevel 2>/dev/null || true)"
if [ "$COMMIT" = 1 ]; then
  [ -n "$BACKUP_TOP" ] || die "$(dirname "$BACKUP_FILE") はgitリポジトリではありません。非公開リポジトリをcloneしてください"
fi
if [ -n "$BACKUP_TOP" ] && [ "$BACKUP_TOP" = "$SELF_TOP" ]; then
  die "保存先が公開リポジトリ($SELF_TOP)と同じです。BACKUP_DIR を別の非公開リポジトリにしてください"
fi

[ -f "$RECIPIENTS" ] || die "$RECIPIENTS がありません。age の公開鍵を書いてください (README参照)"
podman volume exists "$VOLUME" || die "ボリューム $VOLUME が存在しません"

RESTART=0
make_workdir
cleanup() {
  if [ "$RESTART" = 1 ]; then
    podman start "$CONTAINER" >/dev/null || echo "警告: $CONTAINER の再起動に失敗しました。手動で起動してください" >&2
  fi
  if [ -n "$WORK" ]; then
    rm -rf "$WORK"
  fi
}
trap cleanup EXIT

if [ "$STOP" = 1 ] && [ "$(podman inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || true)" = true ]; then
  echo "コンテナ $CONTAINER を一時停止します"
  podman stop "$CONTAINER" >/dev/null
  RESTART=1
fi

podman volume export "$VOLUME" -o "$WORK/vol.tar"

# 空のボリュームや誤ったボリュームを暗号化して上書きしないための確認
tar -tf "$WORK/vol.tar" >"$WORK/list.txt"
grep -q 'nssdb' "$WORK/list.txt" || die "エクスポート内容に nssdb が含まれていません。バックアップを中止します"

NEW_DIGEST="$(content_digest "$WORK/vol.tar")"
OLD_DIGEST="$(cat "$DIGEST_FILE" 2>/dev/null || true)"

if [ "$FORCE" = 0 ] && [ -f "$BACKUP_FILE" ] && [ "$NEW_DIGEST" = "$OLD_DIGEST" ]; then
  echo "前回のバックアップから内容の変更はありません。何もしません。"
  exit 0
fi

mkdir -p "$(dirname "$BACKUP_FILE")"
age -R "$RECIPIENTS" -o "$BACKUP_FILE.tmp" "$WORK/vol.tar"
mv "$BACKUP_FILE.tmp" "$BACKUP_FILE"
echo "$NEW_DIGEST" >"$DIGEST_FILE"

echo "保存しました: $BACKUP_FILE"
echo "--- 含まれるファイル(先頭20件) ---"
head -n 20 "$WORK/list.txt"

if [ "$COMMIT" = 1 ]; then
  git -C "$BACKUP_TOP" add -- "$(realpath "$BACKUP_FILE")" "$(realpath "$DIGEST_FILE")"
  git -C "$BACKUP_TOP" commit -m "backup: qnetd-data $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "コミットしました。非公開リポジトリへ push してください: git -C $BACKUP_TOP push"
else
  echo "git add / commit / push を実行してください (--commit でコミットまで自動化できます)"
fi
