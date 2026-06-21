#!/bin/bash
# =============================================================================
# Velero — Kubernetes Backup & Disaster Recovery
# =============================================================================
# WHY: If the cluster crashes, Velero restores all K8s objects (deployments,
#      services, secrets, PVCs) from S3 backups.
#
# PREREQUISITES:
#   1. Install velero CLI: https://velero.io/docs/v1.14/basic-install/
#   2. Create S3 bucket:
#      aws s3api create-bucket --bucket gaurav-velero-backups \
#        --region ap-south-1 \
#        --create-bucket-configuration LocationConstraint=ap-south-1
#   3. Create IAM credentials file at backup/velero-credentials
# =============================================================================
set -euo pipefail

BUCKET="gaurav-velero-backups"
REGION="ap-south-1"
KUBECONFIG="/home/gaurav/online-boutique/kubeconfig-aws"

echo "=== Installing Velero ==="
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.10.0 \
  --bucket "$BUCKET" \
  --backup-location-config region="$REGION" \
  --snapshot-location-config region="$REGION" \
  --secret-file /home/gaurav/online-boutique/backup/velero-credentials \
  --kubeconfig "$KUBECONFIG"

echo ""
echo "=== Creating Scheduled Backup (every 6 hours, retain 48h) ==="
velero schedule create boutique-backup \
  --schedule="0 */6 * * *" \
  --include-namespaces boutique \
  --ttl 48h \
  --kubeconfig "$KUBECONFIG"

echo ""
echo "=== Creating One-Time Backup Now ==="
velero backup create boutique-manual-$(date +%Y%m%d-%H%M) \
  --include-namespaces boutique \
  --kubeconfig "$KUBECONFIG"

echo ""
echo "Done! Check backups: velero backup get --kubeconfig $KUBECONFIG"
