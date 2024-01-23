terraform {
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "= 2.39.0"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 3.56.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }

    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

data "azurerm_client_config" "client_config" {}
data "azuread_domains" "domains" {}

resource "random_password" "rnd_pass" {
  length  = 16
  special = true
}

resource "random_string" "rnd_str" {
  length  = 4
  lower   = true
  upper   = false
  special = false
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-shared"
  location = "westeurope"
}

resource "azurerm_log_analytics_workspace" "log_workspace" {
  name                = "alogshared${random_string.rnd_str.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_dashboard_grafana" "grafana" {
  name                              = "amgshared${random_string.rnd_str.result}"
  resource_group_name               = azurerm_resource_group.rg.name
  location                          = azurerm_resource_group.rg.location
  api_key_enabled                   = true
  deterministic_outbound_ip_enabled = true
  public_network_access_enabled     = true

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_monitor_workspace" "mon_workspace" {
  name                = "amonshared${random_string.rnd_str.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
}

resource "azurerm_role_assignment" "mg_rbac_me" {
  scope                = azurerm_dashboard_grafana.grafana.id
  role_definition_name = "Grafana Admin"
  principal_id         = data.azurerm_client_config.client_config.object_id
}

resource "azurerm_role_assignment" "mon_rbac_amg" {
  scope                = azurerm_monitor_workspace.mon_workspace.id
  role_definition_name = "Monitoring Data Reader"
  principal_id         = azurerm_dashboard_grafana.grafana.identity[0].principal_id
}

resource "azurerm_role_assignment" "mon_rbac_me" {
  scope                = azurerm_monitor_workspace.mon_workspace.id
  role_definition_name = "Monitoring Data Reader"
  principal_id         = data.azurerm_client_config.client_config.object_id
}

module "aks" {
  source = "./modules/aks-demo"

  for_each = { for u in var.deployment_locations : u.location => u }

  location                          = each.value["location"]
  vm_sku                            = each.value["vm_sku"]
  user_password                     = random_password.rnd_pass.result
  primary_domain                    = data.azuread_domains.domains.domains[0].domain_name
  unique_string                     = random_string.rnd_str.result
  shared_resource_group_id          = azurerm_resource_group.rg.id
  shared_log_analytics_workspace_id = azurerm_log_analytics_workspace.log_workspace.id
  managed_grafana_resource_id       = azurerm_dashboard_grafana.grafana.id

  depends_on = [
    azurerm_resource_group.rg,
    azurerm_dashboard_grafana.grafana,
    azurerm_monitor_workspace.mon_workspace,
    azurerm_role_assignment.mg_rbac_me,
    azurerm_role_assignment.mon_rbac_amg,
    azurerm_role_assignment.mon_rbac_me,
  ]
}
