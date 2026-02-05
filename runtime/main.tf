# --- Initializing Core ---
data "terraform_remote_state" "core" {
  backend = "local"
  config = {
    path = "../core/terraform.tfstate"
  }
}

locals {
  # Grabbing info from CORE
  core_rg_name   = data.terraform_remote_state.core.outputs.core_rg_name
  kv_id          = data.terraform_remote_state.core.outputs.key_vault_id
  kv_name        = data.terraform_remote_state.core.outputs.key_vault_name
  public_ip_id   = data.terraform_remote_state.core.outputs.public_ip_id
  egress_ip      = data.terraform_remote_state.core.outputs.egress_public_ip

  # Common tagging for budgets/alerts
  # Edit these tags as you see fit. 
  common_tags = {
    purpose = "burp-egress"
    owner   = "YourNameHere"
  }

  runtime_tags = merge(local.common_tags, {
    lifecycle = "runtime"
  })
}


# --- Resource group creation ---
resource "azurerm_resource_group" "runtime" {
  name     = "${var.name_prefix}-runtime-rg"
  location = var.location
  tags = local.runtime_tags
}

# --- Networking ---
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.name_prefix}-vnet"
  location            = azurerm_resource_group.runtime.location
  resource_group_name = azurerm_resource_group.runtime.name
  address_space       = ["10.60.0.0/16"]
  tags = local.runtime_tags
}

resource "azurerm_subnet" "aca_infra" {
  name                 = "${var.name_prefix}-aca-subnet"
  resource_group_name  = azurerm_resource_group.runtime.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.60.0.0/23"]

  delegation {
    name = "aca-delegation"
    service_delegation {
      name = "Microsoft.App/environments"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

# --- NAT Gateway (runtime cost driver) ---
resource "azurerm_nat_gateway" "nat" {
  name                = "${var.name_prefix}-nat"
  location            = azurerm_resource_group.runtime.location
  resource_group_name = azurerm_resource_group.runtime.name
  sku_name            = "Standard"

  tags = local.runtime_tags
}

resource "azurerm_nat_gateway_public_ip_association" "nat_pip" {
  nat_gateway_id       = azurerm_nat_gateway.nat.id
  public_ip_address_id = local.public_ip_id
}

resource "azurerm_subnet_nat_gateway_association" "subnet_nat" {
  subnet_id      = azurerm_subnet.aca_infra.id
  nat_gateway_id = azurerm_nat_gateway.nat.id
}

# ---------- Log Analytics ----------
resource "azurerm_log_analytics_workspace" "law" {
  name                = "${var.name_prefix}-law"
  location            = azurerm_resource_group.runtime.location
  resource_group_name = azurerm_resource_group.runtime.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags = local.runtime_tags
}

# --- Key Vault: Identity + RBAC ---
resource "azurerm_user_assigned_identity" "uai" {
  name                = "${var.name_prefix}-uai"
  location            = azurerm_resource_group.runtime.location
  resource_group_name = azurerm_resource_group.runtime.name
  tags = local.runtime_tags
}

resource "azurerm_role_assignment" "kv_secrets_user" {
  scope                = local.kv_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.uai.principal_id
}

# --- Container Apps Environment ---
resource "azurerm_container_app_environment" "env" {
  name                       = "${var.name_prefix}-env"
  location                   = azurerm_resource_group.runtime.location
  resource_group_name        = azurerm_resource_group.runtime.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  infrastructure_subnet_id = azurerm_subnet.aca_infra.id

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }

  tags = local.runtime_tags
}

# --- Container ---
resource "azapi_resource" "container_app" {
  type      = "Microsoft.App/containerApps@2024-03-01"
  name      = "${var.name_prefix}-app"
  location  = azurerm_resource_group.runtime.location
  parent_id = azurerm_resource_group.runtime.id
  tags = local.runtime_tags

  depends_on = [
    azurerm_role_assignment.kv_secrets_user,
    azurerm_container_app_environment.env
  ]

  body = {
    identity = {
      type = "UserAssigned"
      userAssignedIdentities = {
        (azurerm_user_assigned_identity.uai.id) = {}
      }
    }

    properties = {
      managedEnvironmentId = azurerm_container_app_environment.env.id

      configuration = {
        secrets = [
          {
            name        = "ts-authkey"
            keyVaultUrl = "https://${local.kv_name}.vault.azure.net/secrets/${var.key_vault_secret_name}"
            identity    = azurerm_user_assigned_identity.uai.id
          }
        ]
      }

      template = {
        containers = [
          {
            name  = "tailscale"
            image = "tailscale/tailscale:latest"
            env = [
              { name = "TS_AUTHKEY", secretRef = "ts-authkey" },
              { name = "TS_HOSTNAME", value = var.tailscale_hostname },
              { name = "TS_EXTRA_ARGS", value = "--ssh --advertise-tags=tag:${var.tailscale_tag}" },
              { name = "TS_USERSPACE", value = "true" },
              { name = "KUBERNETES_SERVICE_HOST", value = "" }
            ]
          }
        ]
        scale = {
          minReplicas = 1
          maxReplicas = 1
        }
      }
    }
  }
}
