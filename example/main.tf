terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.5"
    }
  }
}

locals {
  # NOTE: remove empty tags to avoid noise in terraform plan/apply:
  tags = {
    for k, v in merge(var.environment.standard_tags, var.tags) : k => v if v != ""
  }

  log_bucket_name = var.log_bucket.name == "" ? "${var.bucket}-logs" : var.log_bucket.name

  block_public_acls       = var.acl == "public-read" ? false : true
  block_public_policy     = var.acl == "public-read" ? false : true
  ignore_public_acls      = var.acl == "public-read" ? false : true
  restrict_public_buckets = var.acl == "public-read" ? false : true
  s3_encryption = {
    rule = {
      bucket_key_enabled = true
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }
  kms_encryption = {
    rule = {
      bucket_key_enabled = null
      apply_server_side_encryption_by_default = {
        kms_master_key_id = ""
        sse_algorithm     = "aws:kms"
      }
    }
  }
  server_side_encryption_configuration = var.acl == "public-read" ? local.s3_encryption : local.kms_encryption

  // This logic is to add `/` at the end of log bucket prefix if not already present
  // Example: If prefix passed id s3-log-new
  // The logic will change it to s3-log-new/
  log_prefix = length(var.log_bucket.prefix) > 0 && substr(var.log_bucket.prefix, length(var.log_bucket.prefix) - 1, 1) != "/" ? "${var.log_bucket.prefix}/" : var.log_bucket.prefix
}

module "main_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "3.10.1"
  create_bucket                         = true
  attach_deny_insecure_transport_policy = true
  attach_policy                         = var.attach_policy
  bucket                                = var.bucket
  acl                                   = var.acl
  policy                                = var.policy
  tags                                  = merge(local.tags, { Name = var.bucket })
  force_destroy                         = !var.environment.is_controlled_stage
  website                               = var.website
  cors_rule                             = var.cors_rule
  versioning                            = var.versioning
  object_lock_configuration             = var.object_lock_configuration
  acceleration_status                   = var.acceleration_status
  logging = var.enable_logging ? {
    target_bucket = data.aws_s3_bucket.log_bucket.id
    target_prefix = local.log_prefix
  } : {}
  grant                                = var.grant
  lifecycle_rule                       = var.lifecycle_rule
  replication_configuration            = var.replication_configuration
  server_side_encryption_configuration = local.server_side_encryption_configuration
  block_public_acls                    = local.block_public_acls
  block_public_policy                  = local.block_public_policy
  ignore_public_acls                   = local.ignore_public_acls
  restrict_public_buckets              = local.restrict_public_buckets
  control_object_ownership             = true
  object_ownership                     = var.object_ownership
}

module "log_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "3.10.1"

  create_bucket                         = var.log_bucket.create
  bucket                                = local.log_bucket_name
  acl                                   = "log-delivery-write"
  force_destroy                         = !var.environment.is_controlled_stage
  attach_deny_insecure_transport_policy = true
  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        kms_master_key_id = ""
        sse_algorithm     = "AES256"
      }
    }
  }
  block_public_acls        = true
  block_public_policy      = true
  ignore_public_acls       = true
  restrict_public_buckets  = true
  control_object_ownership = true
  object_ownership         = "ObjectWriter"
  lifecycle_rule           = var.log_bucket.lifecycle_rule
}

data "aws_s3_bucket" "log_bucket" {
  bucket     = local.log_bucket_name
  depends_on = [module.log_bucket]
}
