variable "yc_cloud_id" {
  description = "Cloud ID"
}

variable "yc_folder_id" {
  description = "Cloud folder ID"
  type        = string
}

variable "yc_token" {
  type        = string
}


variable "pg" {
  type = object({
    username = string
    password  = string
  })
}

variable "account_pool_size" {
  type = number
  default = 1000
  description = "How many accounts to insert"
}

variable "net_zone" {
  type  = string
  default = "ru-central1-d"
}
