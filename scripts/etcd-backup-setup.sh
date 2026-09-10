#!/usr/bin/env bash
# Set up a scheduled etcd snapshot -> S3 on this control-plane node.
# Auth is via the node's IAM instance-profile (terraform/iam-etcd-backup.tf) read
# from IMDS — no static AWS keys on disk. Run ON the master:
#   sudo bash etcd-backup-setup.sh
set -euo pipefail

BUCKET="${BUCKET:-gaurav-devops-tfstate}"
REGION="${REGION:-ap-south-1}"
ONCALENDAR="${ONCALENDAR:-*-*-* 00/6:00:00}"   # every 6 hours

echo "== install etcd-client + awscli =="
apt-get update -qq
apt-get install -y -qq etcd-client awscli

echo "== write /usr/local/bin/etcd-backup.sh =="
cat > /usr/local/bin/etcd-backup.sh <<EOF
#!/bin/bash
set -euo pipefail
TS=\$(date +%Y%m%d-%H%M%S)
SNAP=/tmp/etcd-\$TS.db
ETCDCTL_API=3 etcdctl snapshot save "\$SNAP" \\
  --endpoints=https://127.0.0.1:2379 \\
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \\
  --cert=/etc/kubernetes/pki/etcd/server.crt \\
  --key=/etc/kubernetes/pki/etcd/server.key
aws s3 cp "\$SNAP" "s3://$BUCKET/etcd-snapshots/etcd-\$TS.db" --region $REGION
rm -f "\$SNAP"
echo "etcd backup uploaded: s3://$BUCKET/etcd-snapshots/etcd-\$TS.db"
EOF
chmod +x /usr/local/bin/etcd-backup.sh

echo "== write systemd units =="
cat > /etc/systemd/system/etcd-backup.service <<EOF
[Unit]
Description=etcd snapshot to S3
[Service]
Type=oneshot
ExecStart=/usr/local/bin/etcd-backup.sh
EOF

cat > /etc/systemd/system/etcd-backup.timer <<EOF
[Unit]
Description=Run etcd-backup on a schedule
[Timer]
OnCalendar=$ONCALENDAR
Persistent=true
[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now etcd-backup.timer

echo "== run once now (proof) =="
/usr/local/bin/etcd-backup.sh

echo "== next scheduled runs =="
systemctl list-timers etcd-backup.timer --no-pager
