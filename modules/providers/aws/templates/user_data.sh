#!/bin/bash
set -e

ROOT_DEV=$(df / --output=source | tail -1)

# ---------- handle XFS on non-LVM root ----------
if [[ "$ROOT_DEV" == /dev/nvme* ]] || [[ "$ROOT_DEV" == /dev/xvd* ]] || [[ "$ROOT_DEV" == /dev/sd* ]]; then
  BASE_DEV=$(echo "$ROOT_DEV" | sed 's/[0-9]*$//')
  PART_NUM=$(echo "$ROOT_DEV" | grep -oP '\d+$' || echo "")

  if [ -n "$PART_NUM" ] && command -v growpart &>/dev/null; then
    echo "Expanding partition $PART_NUM on $BASE_DEV"
    growpart "$BASE_DEV" "$PART_NUM" || true
  fi

  case "$(blkid -o value -s TYPE "$ROOT_DEV" 2>/dev/null)" in
    xfs)  echo "Growing XFS filesystem on /"; xfs_growfs / || true ;;
    ext4) echo "Resizing ext4 filesystem on $ROOT_DEV"; resize2fs "$ROOT_DEV" || true ;;
  esac
fi

# ---------- handle LVM root (e.g. /dev/mapper/rl-root) ----------
if [[ "$ROOT_DEV" == /dev/mapper/* ]]; then
  echo "Detected LVM root ($ROOT_DEV), running LVM resize"
  pvresize $(pvdisplay -C -o "PV Name" --noheadings 2>/dev/null | head -1) 2>/dev/null || true
  lvextend -l +100%FREE "$ROOT_DEV" 2>/dev/null || true

  case "$(blkid -o value -s TYPE "$ROOT_DEV" 2>/dev/null)" in
    xfs)  echo "Growing XFS filesystem on /"; xfs_growfs / || true ;;
    ext4) echo "Resizing ext4 filesystem on $ROOT_DEV"; resize2fs "$ROOT_DEV" || true ;;
  esac
fi

echo "Root filesystem: $(df -h / | tail -1)"
