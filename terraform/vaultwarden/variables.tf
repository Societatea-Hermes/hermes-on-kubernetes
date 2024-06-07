variable "domain" {
  description = "The domain name for the Vaultwarden instance."
  type        = string
}

variable "subdomain" {
  description = "The subdomain for the Vaultwarden instance."
  type        = string
}

variable "email" {
  description = "The Hermes admin email."
  type        = string
}

variable "cloudflare_api_key" {
  description = "The Cloudflare API key."
  type        = string
}

variable "backup_folder" {
  description = "The Google Drive folder id where backups are stored."
  type        = string
}

variable "service_account_json" {
  description = "The service account json for the Google Drive API."
  type        = string
}