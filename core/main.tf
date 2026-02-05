data "azurerm_client_config" "current" {}

locals {
  # Common tagging for budgets/alerts
  common_tags = {
    purpose = "burp-egress"
    owner   = "YourNameHere"
  }

  core_tags = merge(local.common_tags, {
    lifecycle = "core"
  })
}

resource "azurerm_resource_group" "core" {
  name     = "${var.name_prefix}-core-rg"
  location = var.location
  tags = local.core_tags
}

resource "azurerm_key_vault" "kv" {
  name                       = "${replace(var.name_prefix, "-", "")}kv"
  location                   = azurerm_resource_group.core.location
  resource_group_name        = azurerm_resource_group.core.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  purge_protection_enabled   = true
  soft_delete_retention_days = 7
  rbac_authorization_enabled = true
  tags = local.core_tags
}

resource "azurerm_public_ip" "egress" {
  name                = "${var.name_prefix}-egress-pip"
  location            = azurerm_resource_group.core.location
  resource_group_name = azurerm_resource_group.core.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags = local.core_tags
}