data "azurerm_client_config" "client_config" {}

resource "azuread_user" "ad_user" {
  user_principal_name = "DevOps@${var.primary_domain}"
  display_name        = "DevOps"
  mail_nickname       = "DevOps"
  password            = var.user_password
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-devops"
  location = var.location
}

resource "azurerm_role_assignment" "rg_rbac" {
  role_definition_name = "Owner"
  scope                = azurerm_resource_group.rg.id
  principal_id         = azuread_user.ad_user.object_id
}

resource "azuread_application" "ad_application" {
  display_name = "DevOpsSP"
  owners       = [azuread_user.ad_user.object_id]
}

resource "azuread_service_principal" "sp" {
  application_id               = azuread_application.ad_application.application_id
  app_role_assignment_required = true
  owners                       = [azuread_user.ad_user.object_id]
}

resource "azurerm_role_assignment" "sp_rbac" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Owner"
  principal_id         = azuread_service_principal.sp.object_id
}

resource "azurerm_container_registry" "acr" {
  name                   = "acr${var.unique_string}"
  resource_group_name    = azurerm_resource_group.rg.name
  location               = azurerm_resource_group.rg.location
  sku                    = "Standard"
  admin_enabled          = true
  anonymous_pull_enabled = true
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks${var.unique_string}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  dns_prefix          = "aks"

  default_node_pool {
    name                = "default"
    enable_auto_scaling = true
    max_count           = 3
    min_count           = 1
    vm_size             = var.vm_sku
  }

  oms_agent {
    log_analytics_workspace_id = var.shared_log_analytics_workspace_id
  }

  identity {
    type = "SystemAssigned"
  }

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "1m"
  }

  service_mesh_profile {
    mode = "Istio"
  }

  workload_autoscaler_profile {
    keda_enabled = true
  }

  lifecycle {
    ignore_changes = [
      monitor_metrics
    ]
  }
}

resource "azurerm_role_assignment" "acr_rbac_aks" {
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.acr.id
  principal_id                     = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  skip_service_principal_aad_check = true
}

# use local provisioner to enable istio ingress gateway on each AKS cluster
resource "null_resource" "local_provisioner" {

  provisioner "local-exec" {
    command = "az aks mesh enable-ingress-gateway --resource-group ${azurerm_resource_group.rg.name} --name ${azurerm_kubernetes_cluster.aks.name} --ingress-gateway-type external"
  }

  depends_on = [
    azurerm_kubernetes_cluster.aks,
  ]
}

# use local provisioner to enable istio ingress gateway on each AKS cluster
resource "null_resource" "local_provisioner2" {

  provisioner "local-exec" {
    command = "az aks mesh enable-ingress-gateway --resource-group ${azurerm_resource_group.rg.name} --name ${azurerm_kubernetes_cluster.aks.name} --egress-gateway-type external"
  }

  depends_on = [
    azurerm_kubernetes_cluster.aks,
  ]
}


resource "azurerm_user_assigned_identity" "uami" {
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  name                = "aks-devops-identity"
}

resource "azurerm_federated_identity_credential" "fi_cred" {
  name                = "aks-devops-federated-default"
  resource_group_name = azurerm_resource_group.rg.name
  issuer              = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.uami.id
  subject             = "system:serviceaccount:default:azure-voting-app-serviceaccount"
  audience = [
    "api://AzureADTokenExchange"
  ]
}

resource "azurerm_key_vault" "kv" {
  name                       = "akvuser${var.unique_string}"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  tenant_id                  = data.azurerm_client_config.client_config.tenant_id
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  sku_name                   = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.client_config.tenant_id
    object_id = data.azurerm_client_config.client_config.object_id

    certificate_permissions = [
      "Backup",
      "Create",
      "Delete",
      "DeleteIssuers",
      "Get",
      "GetIssuers",
      "Import",
      "List",
      "ListIssuers",
      "ManageContacts",
      "ManageIssuers",
      "Purge",
      "Recover",
      "Restore",
      "SetIssuers",
      "Update"
    ]

    key_permissions = [
      "Backup",
      "Create",
      "Decrypt",
      "Delete",
      "Encrypt",
      "Get",
      "Import",
      "List",
      "Purge",
      "Recover",
      "Restore",
      "Sign",
      "UnwrapKey",
      "Update",
      "Verify",
      "WrapKey",
      "Release",
      "Rotate",
      "GetRotationPolicy",
      "SetRotationPolicy"
    ]

    secret_permissions = [
      "Backup",
      "Delete",
      "Get",
      "List",
      "Purge",
      "Recover",
      "Restore",
      "Set"
    ]

    storage_permissions = [
      "Backup",
      "Delete",
      "DeleteSAS",
      "Get",
      "GetSAS",
      "List",
      "ListSAS",
      "Purge",
      "Recover",
      "RegenerateKey",
      "Restore",
      "Set",
      "SetSAS",
      "Update"
    ]
  }

  access_policy {
    tenant_id = data.azurerm_client_config.client_config.tenant_id
    object_id = azuread_user.ad_user.object_id

    certificate_permissions = [
      "Backup",
      "Create",
      "Delete",
      "DeleteIssuers",
      "Get",
      "GetIssuers",
      "Import",
      "List",
      "ListIssuers",
      "ManageContacts",
      "ManageIssuers",
      "Purge",
      "Recover",
      "Restore",
      "SetIssuers",
      "Update"
    ]

    key_permissions = [
      "Backup",
      "Create",
      "Decrypt",
      "Delete",
      "Encrypt",
      "Get",
      "Import",
      "List",
      "Purge",
      "Recover",
      "Restore",
      "Sign",
      "UnwrapKey",
      "Update",
      "Verify",
      "WrapKey",
      "Release",
      "Rotate",
      "GetRotationPolicy",
      "SetRotationPolicy"
    ]

    secret_permissions = [
      "Backup",
      "Delete",
      "Get",
      "List",
      "Purge",
      "Recover",
      "Restore",
      "Set"
    ]

    storage_permissions = [
      "Backup",
      "Delete",
      "DeleteSAS",
      "Get",
      "GetSAS",
      "List",
      "ListSAS",
      "Purge",
      "Recover",
      "RegenerateKey",
      "Restore",
      "Set",
      "SetSAS",
      "Update"
    ]
  }

  access_policy {
    tenant_id = data.azurerm_client_config.client_config.tenant_id
    object_id = azurerm_user_assigned_identity.uami.principal_id

    key_permissions = [
      "Get",
    ]

    secret_permissions = [
      "Get",
    ]

    certificate_permissions = [
      "Get"
    ]
  }
}

resource "azurerm_key_vault_secret" "user_secret" {
  name         = "secret-password"
  value        = var.user_password
  key_vault_id = azurerm_key_vault.kv.id
}

resource "azurerm_role_assignment" "amg_rbac_user" {
  scope                = var.managed_grafana_resource_id
  role_definition_name = "Grafana Admin"
  principal_id         = azuread_user.ad_user.object_id
}

resource "azurerm_role_assignment" "amg_rbac_useridentity" {
  scope                = var.managed_grafana_resource_id
  role_definition_name = "Grafana Admin"
  principal_id         = azurerm_user_assigned_identity.uami.principal_id
}

resource "azurerm_role_assignment" "mcrg_rbac_user" {
  role_definition_name = "Owner"
  scope                = azurerm_kubernetes_cluster.aks.node_resource_group_id
  principal_id         = azuread_user.ad_user.object_id
}

resource "azurerm_role_assignment" "sharedrg_rbac_user" {
  role_definition_name = "Owner"
  scope                = var.shared_resource_group_id
  principal_id         = azuread_user.ad_user.object_id
}
