variable "subscription_id" { type = string }

variable "location" {
  type    = string
  default = "eastus"
  #You can use a different location here. Check out ❯ az account list-locations -o table                     
}

variable "name_prefix" {
  type    = string
  default = "cnt-pxy"
}

variable "tailscale_tag" {
  type    = string
  default = "container"
}

variable "key_vault_secret_name" {
  type    = string
  default = "TS-AUTHKEY"
}

# tailnet hostname
variable "tailscale_hostname" {
  type    = string
  default = "container-proxy"
}