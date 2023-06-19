##############################################################################
# Resource Group
##############################################################################

module "resource_group" {
  source  = "terraform-ibm-modules/resource-group/ibm"
  version = "1.0.5"
  # if an existing resource group is not set (null) create a new one using prefix
  resource_group_name          = var.resource_group == null ? "${var.prefix}-resource-group" : null
  existing_resource_group_name = var.resource_group
}

##############################################################################
# Key Protect Instance + Key (used to encrypt bucket)
##############################################################################

module "key_protect" {
  source                    = "terraform-ibm-modules/key-protect-all-inclusive/ibm"
  version                   = "4.2.0"
  resource_group_id         = module.resource_group.resource_group_id
  region                    = var.region
  resource_tags             = var.resource_tags
  key_map                   = { "observability" = ["observability-key"] }
  key_protect_instance_name = "${var.prefix}-kp"
}

##############################################################################
# COS instance + bucket (used for logdna + AT archiving)
##############################################################################

locals {
  bucket_name     = "${var.prefix}-observability-archive-bucket"
  archive_api_key = var.archive_api_key == null ? var.ibmcloud_api_key : var.archive_api_key
}

module "cos" {
  source                     = "terraform-ibm-modules/cos/ibm"
  version                    = "6.6.0"
  resource_group_id          = module.resource_group.resource_group_id
  region                     = var.region
  cos_instance_name          = "${var.prefix}-cos"
  cos_tags                   = var.resource_tags
  bucket_name                = local.bucket_name
  existing_kms_instance_guid = module.key_protect.key_protect_guid
  create_hmac_key            = false
  retention_enabled          = false
  activity_tracker_crn       = module.observability_instance_creation.activity_tracker_crn
  sysdig_crn                 = module.observability_instance_creation.sysdig_crn
  kms_key_crn                = module.key_protect.keys["observability.observability-key"].crn
}

module "observability_instance_creation" {
  source = "../../"
  providers = {
    logdna.at = logdna.at
    logdna.ld = logdna.ld
  }
  resource_group_id                 = module.resource_group.resource_group_id
  region                            = var.region
  logdna_instance_name              = var.prefix
  sysdig_instance_name              = var.prefix
  activity_tracker_instance_name    = var.prefix
  enable_platform_metrics           = false
  enable_platform_logs              = false
  logdna_plan                       = "7-day"
  sysdig_plan                       = "graduated-tier"
  activity_tracker_plan             = "7-day"
  logdna_tags                       = var.resource_tags
  sysdig_tags                       = var.resource_tags
  activity_tracker_tags             = var.resource_tags
  logdna_manager_key_tags           = var.resource_tags
  sysdig_manager_key_tags           = var.resource_tags
  activity_tracker_manager_key_tags = var.resource_tags
  logdna_access_tags                = var.access_tags
  sysdig_access_tags                = var.access_tags
  activity_tracker_access_tags      = var.access_tags
  enable_archive                    = true
  ibmcloud_api_key                  = local.archive_api_key
  logdna_cos_instance_id            = module.cos.cos_instance_id
  logdna_cos_bucket_name            = local.bucket_name
  logdna_cos_bucket_endpoint        = module.cos.s3_endpoint_public
  at_cos_bucket_name                = local.bucket_name
  at_cos_instance_id                = module.cos.cos_instance_id
  at_cos_bucket_endpoint            = module.cos.s3_endpoint_private
}
