#!/bin/bash
# Simple backup script for important directories

BACKUP_DIR="/home/backups"
DATE=$(date +%Y-%m-%d_%H-%M-%S)

mkdir -p $BACKUP_DIR

tar -czf $BACKUP_DIR/nginx-backup-$DATE.tar.gz /etc/nginx/

find $BACKUP_DIR -name "*.tar.gz" -mtime +7 -delete

echo "Backup completed: $BACKUP_DIR/nginx-backup-$DATE.tar.gz"