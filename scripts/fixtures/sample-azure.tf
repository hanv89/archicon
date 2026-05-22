# Sample Terraform for scripts/iac_to_diagram.mjs (experimental).
# Exercises the azurerm icon map + two deliberately-unmapped types
# (azurerm_dns_zone, azurerm_user_assigned_identity) to show that uncovered
# types are reported, not dropped.

resource "azurerm_resource_group" "main" {
  name     = "rg-app"
  location = "westeurope"
}

resource "azurerm_virtual_network" "main" {
  name                = "vnet-app"
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_subnet" "aks" {
  name                 = "snet-aks"
  virtual_network_name = azurerm_virtual_network.main.name
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-app"
  resource_group_name = azurerm_resource_group.main.name
  default_node_pool { vnet_subnet_id = azurerm_subnet.aks.id }
}

resource "azurerm_mssql_database" "main" {
  name      = "sqldb-app"
  server_id = azurerm_mssql_server.main.id
}

resource "azurerm_mssql_server" "main" {
  name                = "sql-app"
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_redis_cache" "main" {
  name                = "redis-app"
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_key_vault" "main" {
  name                = "kv-app"
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_frontdoor" "main" {
  name = "fd-app"
  # routes traffic to the AKS-hosted app
  backend = azurerm_kubernetes_cluster.main.id
}

resource "azurerm_dns_zone" "main" {
  name                = "example.com"
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_user_assigned_identity" "main" {
  name                = "id-app"
  resource_group_name = azurerm_resource_group.main.name
}
