resource "kubernetes_service_account" "psmdb_backup" {
  metadata {
    name      = "${var.cluster_name}-backup"
    namespace = "psmdb"

    annotations = {
      "eks.amazonaws.com/role-arn" = module.backup_irsa.iam_role_arn
    }
  }
}

resource "aws_s3_bucket" "psmdb_backups" {
  bucket = "${var.cluster_name}-backups-${var.region}"
}

resource "aws_s3_bucket_versioning" "psmdb_backups" {
  bucket = aws_s3_bucket.psmdb_backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "psmdb_backups" {
  bucket                  = aws_s3_bucket.psmdb_backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

module "backup_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.48"

  role_name = "${var.cluster_name}-pbm-backup"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["psmdb:${var.cluster_name}-backup"]
    }
  }
}

resource "aws_iam_policy" "pbm_s3_access" {
  name = "${var.cluster_name}-pbm-s3-access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.psmdb_backups.arn]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts"
        ]
        Resource = ["${aws_s3_bucket.psmdb_backups.arn}/*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "pbm_s3_access" {
  role       = module.backup_irsa.iam_role_name
  policy_arn = aws_iam_policy.pbm_s3_access.arn
}

output "backup_bucket_name" {
  value = aws_s3_bucket.psmdb_backups.bucket
}

output "backup_irsa_role_arn" {
  value = module.backup_irsa.iam_role_arn
}
