variable "cloudflare_api_token" {
  description = "Cloudflare API Token for Terraform"
  type        = string
}

variable "db_user" {
  description = "Username for the PG database"
  type        = string
}

variable "db_password" {
  description = "Password for the PG database"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "PG database name"
  type        = string
}

variable "cluster_name" {
  default = "api-cluster"
}

variable "redis_container_name" {
  default = "redis-api"
}

variable "rds_container_name" {
  default = "rds-api"
}

variable "rds_service_name" {
  default = "rds_api_service"
}

variable "redis_service_name" {
  default = "redis_api_service"
}

variable "region" {
  description = "region name"
  type        = string
}

variable "main_domain_name" {
  description = "main domain name"
  type        = string
}

variable "frontend_subdomain" {
  description = "Frontend subdomain"
  type        = string
  default     = "frontend"
}

variable "rds_subdomain" {
  description = "RDS API subdomain"
  type        = string
  default     = "api-rds"
}

variable "redis_subdomain" {
  description = "Redis API subdomain"
  type        = string
  default     = "api-redis"
}

