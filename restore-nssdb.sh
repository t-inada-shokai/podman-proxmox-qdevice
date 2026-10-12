#!/usr/bin/env bash
# backup/qnetd-data.tar.age を復号し、podman ボリュームに import する。
# age の秘密鍵はリポジトリに入れない。既定は ~/.config/age/qnetd.key (AGE_IDENTITY で変更可)。
set -euo pipefail

cd "$(dirname "$0")"
# shellcheck source=lib.sh
. ./lib.sh

IDENTITY="${AGE_IDENTITY:-$HOME/.config/age/qnetd.key}"
FORCE=0
UP=0

usage() {
  cat <<EOF
使い方: $0 [-i 秘密鍵ファイル] [-f バックアップファイル] [--force] [--up]
  -i, --identity  age の秘密鍵 (既定: $IDENTITY)
  -f, --file      復元するバックアップ (既定: $BACKUP_FILE)
  --force         同名ボリュームが既にある場合、削除して作り直す(既存の内容は失われる)
  --up            復元後に podman compose up -d --build まで実行する
環境変数: VOLUME(既定 qnetd-data)  ※復旧テスト時は別名にする
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -i | --identity) IDENTITY="${2:?-i には秘密鍵ファイルを指定してください}"; shift ;;
    -f | --file) BACKUP_FILE="${2:?-f にはバックアップファイルを指定してください}"; shift ;;
    --force) FORCE=1 ;;
    --up) UP=1 ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

need podman age tar sha256sum find sort xargs
[ -f "$BACKUP_FILE" ] || die "バックアップ $BACKUP_FILE がありません"
[ -f "$IDENTITY" ] || die "age の秘密鍵 $IDENTITY がありません (リポジトリには含まれません。別の保管場所から配置してください)"

if podman volume exists "$VOLUME"; then
  [ "$FORCE" = 1 ] || die "ボリューム $VOLUME は既に存在します。作り直すなら --force (既存の内容は失われます)"
  echo "既存ボリューム $VOLUME を削除します (使用中のコンテナも削除されます)"
  podman volume rm -f "$VOLUME"
fi

make_workdir
cleanup() {
  if [ -n "$WORK" ]; then
    rm -rf "$WORK"
  fi
}
trap cleanup EXIT

echo "復号しています: $BACKUP_FILE"
age -d -i "$IDENTITY" -o "$WORK/vol.tar" "$BACKUP_FILE"

WANT="$(cat "$DIGEST_FILE" 2>/dev/null || true)"
if [ -n "$WANT" ]; then
  GOT="$(content_digest "$WORK/vol.tar")"
  [ "$GOT" = "$WANT" ] || die "復号したデータのダイジェストが $DIGEST_FILE と一致しません。バックアップが壊れているか、対応しないファイルです"
  echo "復号データのダイジェスト: 一致"
else
  echo "警告: $DIGEST_FILE が無いため、ダイジェスト検証は行いません" >&2
fi

podman volume create "$VOLUME" >/dev/null
podman volume import "$VOLUME" "$WORK/vol.tar"

# import 後にもう一度 export して、往復で内容が変わっていないことを確認する
podman volume export "$VOLUME" -o "$WORK/check.tar"
if [ -n "$WANT" ]; then
  AFTER="$(content_digest "$WORK/check.tar")"
  [ "$AFTER" = "$WANT" ] || die "import 後のダイジェストが一致しません。ボリューム $VOLUME の内容を確認してください"
  echo "import後のダイジェスト: 一致"
fi

tar -tf "$WORK/check.tar" >"$WORK/list.txt"
echo "--- ボリューム $VOLUME の内容(先頭20件) ---"
head -n 20 "$WORK/list.txt"

if [ "$UP" = 1 ]; then
  if [ "$VOLUME" != "qnetd-data" ]; then
    echo "警告: VOLUME が qnetd-data ではないため --up はスキップします (復旧テストとみなします)" >&2
  else
    podman compose up -d --build
    echo "起動しました。確認: podman exec $CONTAINER corosync-qnetd-tool -l"
  fi
else
  echo "復元しました。起動するには: podman compose up -d --build"
fi
