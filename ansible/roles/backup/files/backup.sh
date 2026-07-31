#!/bin/bash
set -euo pipefail

BACKUP_DIR="/home/backups"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
ARCHIVE="$BACKUP_DIR/system-config-backup-$DATE.tar.gz"

mkdir -p "$BACKUP_DIR"

tar -czf "$ARCHIVE" \
  /etc/ssh/sshd_config \
  /etc/ufw/ \
  /etc/apt/apt.conf.d/20auto-upgrades \
  /var/lib/tailscale/tailscaled.state 2>/dev/null || true

if [ -f "$ARCHIVE" ]; then
  echo "Backup completed: $ARCHIVE"
  find "$BACKUP_DIR" -name "*.tar.gz" -mtime +7 -delete
else
  echo "Backup failed — archive not created" >&2
  exit 1
fi