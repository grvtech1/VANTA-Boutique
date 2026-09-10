# =============================================================================
# IAM instance-profile for the master: scoped S3 write for scheduled etcd backups.
# The backup script on the master (systemd timer) uploads snapshots to S3; the AWS
# CLI picks up temporary credentials from IMDS via this role — no static keys on disk.
# Scoped to PutObject under the etcd-snapshots/ prefix only (least privilege).
# =============================================================================

resource "aws_iam_role" "etcd_backup" {
  name = "${var.project_name}-etcd-backup"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = { Name = "${var.project_name}-etcd-backup" }
}

resource "aws_iam_role_policy" "etcd_backup_s3" {
  name = "etcd-backup-s3-put"
  role = aws_iam_role.etcd_backup.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject"]
      Resource = "arn:aws:s3:::gaurav-devops-tfstate/etcd-snapshots/*"
    }]
  })
}

resource "aws_iam_instance_profile" "etcd_backup" {
  name = "${var.project_name}-etcd-backup"
  role = aws_iam_role.etcd_backup.name
}
