#!/bin/bash
set -e

ROOT_DEV=$(df / --output=source | tail -1)
BASE_DEV=$(echo "$ROOT_DEV" | sed 's/[0-9]*$//')
PART_NUM=$(echo "$ROOT_DEV" | grep -oP '\d+$' || echo "")

if [ -n "$PART_NUM" ] && command -v growpart &>/dev/null; then
  growpart "$BASE_DEV" "$PART_NUM" 2>/dev/null || true
fi

case "$(blkid -o value -s TYPE "$ROOT_DEV" 2>/dev/null)" in
  xfs)  xfs_growfs / 2>/dev/null || true ;;
  ext4) resize2fs "$ROOT_DEV" 2>/dev/null || true ;;
esac
