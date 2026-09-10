#!/usr/bin/env bash
# Velero — backup & restore of the boutique namespace to S3 (objects + PV snapshots).
# Prereqs: velero CLI, an S3 bucket, and backup/velero-credentials (git-ignored; see .example).
#
#   VELERO_BUCKET=my-bucket AWS_REGION=ap-south-1 backup/velero-install.sh
set -euo pipefail
BUCKET="${VELERO_BUCKET:?set VELERO_BUCKET}"
REGION="${AWS_REGION:-ap-south-1}"
NS="${NAMESPACE:-boutique}"
CREDS="${VELERO_CREDENTIALS:-$(dirname "$0")/velero-credentials}"
[ -f "$CREDS" ] || { echo "missing $CREDS — copy velero-credentials.example and fill it in (never commit it)" >&2; exit 1; }

echo "== install velero (S3: $BUCKET, $REGION) =="
# Storage is local-path (not EBS CSI), so EBS volume snapshots don't apply — back up PV
# contents with the node-agent (file-system backup) instead. --default-volumes-to-fs-backup
# opts every pod volume into FSB without per-pod annotations.
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.10.0 \
  --bucket "$BUCKET" \
  --backup-location-config region="$REGION" \
  --use-volume-snapshots=false \
  --use-node-agent \
  --default-volumes-to-fs-backup \
  --secret-file "$CREDS"

echo; echo "== schedule: every 6h, keep 48h, namespace $NS =="
velero schedule create boutique-backup --schedule="0 */6 * * *" --include-namespaces "$NS" --ttl 48h || true

echo; echo "== one-off backup now =="
velero backup create "boutique-manual-$(date +%Y%m%d-%H%M)" --include-namespaces "$NS"
echo
echo "restore drill:  velero restore create --from-backup <name>   (see docs/RUNBOOKS.md)"
