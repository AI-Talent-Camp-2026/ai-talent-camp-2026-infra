# =============================================================================
# Terraform Backend Configuration
# =============================================================================
# Uncomment and configure if you want to store state in Yandex Object Storage
# =============================================================================

# terraform {
#   backend "s3" {
#     endpoints = {
#       s3 = "https://storage.yandexcloud.net"
#     }
#     bucket = "your-terraform-state-bucket"
#     key    = "ai-camp/dev/terraform.tfstate"
#     region = "ru-central1"
#
#     skip_region_validation      = true
#     skip_credentials_validation = true
#     skip_requesting_account_id  = true
#     skip_s3_checksum            = true
#   }
# }

# =============================================================================
# Local Backend (Default)
# =============================================================================
# By default, Terraform uses local backend.
# State file will be stored in the current directory as terraform.tfstate
# Make sure terraform.tfstate is in .gitignore!
