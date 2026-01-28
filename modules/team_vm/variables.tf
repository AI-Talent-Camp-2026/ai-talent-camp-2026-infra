variable "name" {
  description = "Base name for team resources"
  type        = string
}

variable "team_id" {
  description = "Team identifier (e.g., '01', '02')"
  type        = string
}

variable "zone" {
  description = "Yandex Cloud availability zone"
  type        = string
}

variable "platform" {
  description = "Platform ID for the VM"
  type        = string
  default     = "standard-v3"
}

variable "cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 2
}

variable "memory" {
  description = "Memory in GB"
  type        = number
  default     = 4
}

variable "disk_size" {
  description = "Boot disk size in GB"
  type        = number
  default     = 30
}

variable "preemptible" {
  description = "Whether the VM is preemptible"
  type        = bool
  default     = false
}

variable "private_subnet_id" {
  description = "ID of the private subnet"
  type        = string
}

variable "team_sg_id" {
  description = "ID of the team security group"
  type        = string
}

variable "team_user" {
  description = "Username for the team"
  type        = string
}

variable "public_keys" {
  description = "List of SSH public keys for the team user"
  type        = list(string)
}

variable "domain" {
  description = "Base domain for the camp"
  type        = string
  default     = "camp.aitalenthub.ru"
}
