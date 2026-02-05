variable "subscription_id" {
  type = string
}

variable "location" {
  type    = string
  default = "eastus"
  # You may also use any from here: `az account list-locations -o table`
}

variable "name_prefix" {
  type    = string
  default = "cnt-pxy"
}