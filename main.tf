terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "3.67.0"
    }
    azuread = {
      source = "hashicorp/azuread"
      version = "2.39.0"
    }

   }
backend "azurerm" {
    resource_group_name = ""
    storage_account_name = "" 
    container_name       = "" 
    key                  = ""  
  }
}
provider "azurerm" {
    subscription_id = "27797fca-63b0-46fd-87c7-0757c81e041a"
    client_id ="80673a22-4b8c-44e8-b1a1-72f9e3c2a37e"
    client_secret = "z8p8Q~a3Z8ZoISvXbmySld7MdAC1XteBuuzROcDo"
    tenant_id = "2c5efac5-c4bd-4292-a494-ff1758054b2c"
    use_msi = true
    features {
    key_vault {
      recover_soft_deleted_key_vaults = true
      purge_soft_deleted_secrets_on_destroy    = true
     // recover_soft_deleted_key_vaults = true
    }
  }
}

data "azurerm_client_config" "current" {}
resource "azurerm_key_vault" "keynewdona" {
  name                        = "keynewdona"
  location                    = azurerm_resource_group.project_rg.location
  resource_group_name         = azurerm_resource_group.project_rg.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  sku_name = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Create",
      "Get",
    ]

    secret_permissions = [
      "Set",
      "Get",
      "Delete",
      "Purge",
      "Recover",
      "List",
    ]

    storage_permissions = [
      "Get",
      "Set",
    ]
  }
}

resource "azurerm_key_vault_access_policy" "project-principalkey" {
  key_vault_id = azurerm_key_vault.keynewdona.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_windows_web_app.MyNodeJsApp.identity.0.principal_id

  secret_permissions = [
    "Get", "List",  "Set",
  ]
}
provider "azuread"{
    client_id ="80673a22-4b8c-44e8-b1a1-72f9e3c2a37e"
    client_secret = "z8p8Q~a3Z8ZoISvXbmySld7MdAC1XteBuuzROcDo"
    tenant_id = "2c5efac5-c4bd-4292-a494-ff1758054b2c"
}
data "azuread_user" "user" {
  user_principal_name  = "db9crt_bolton.ac.uk#EXT#@db9crt.onmicrosoft.com"
}
resource "azurerm_key_vault_access_policy" "user-principalkey" {
  key_vault_id = azurerm_key_vault.keynewdona.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azuread_user.user.object_id

  secret_permissions = [
    "Get", "List",  "Set"
  ]
}

resource "azurerm_resource_group" "project_rg" {
  name     = "project_rg"
  location = "UK South"
}
resource "azurerm_service_plan" "project_appplan" {
  name                = "project-appserviceplan"
  location            = azurerm_resource_group.project_rg.location
  resource_group_name = azurerm_resource_group.project_rg.name
  os_type = "Windows"
  sku_name = "S1"

}
resource "azurerm_cosmosdb_account" "projectcosmosdbacct" {
  name                = "projectcosmosdbacct"
  location = azurerm_resource_group.project_rg.location
  resource_group_name = azurerm_resource_group.project_rg.name
  offer_type = "Standard"
  enable_automatic_failover = false
  kind = "MongoDB"

   capabilities {
    name = "EnableAggregationPipeline"
  }

  capabilities {
    name = "mongoEnableDocLevelTTL"
  }

  capabilities {
    name = "MongoDBv3.4"
  }

  capabilities {
    name = "EnableMongo"
  }
  
  consistency_policy {
    consistency_level       = "Strong"
  }

  geo_location {
    location          = azurerm_resource_group.project_rg.location
    failover_priority = 0
  }
}
data "azurerm_cosmosdb_account" "projectcosmosdbacct"{
  name = azurerm_cosmosdb_account.projectcosmosdbacct.name
  resource_group_name = azurerm_resource_group.project_rg.name
}

resource "azurerm_key_vault_secret" "projectsecretnewer" {
  name         = "projectsecretnewer"
  value        = azurerm_cosmosdb_account.projectcosmosdbacct.connection_strings[0]
  key_vault_id = azurerm_key_vault.keynewdona.id
}
resource "azurerm_cosmosdb_mongo_database" "project_cosmosdb" {
  name                = "project_cosmosdb"
  resource_group_name = data.azurerm_cosmosdb_account.projectcosmosdbacct.resource_group_name
  account_name        = data.azurerm_cosmosdb_account.projectcosmosdbacct.name
  throughput          = 400
  depends_on = [ azurerm_cosmosdb_account.projectcosmosdbacct ]
}
resource "azurerm_windows_web_app" "MyNodeJsApp" {
  name                = "MyNodeJsAppproject"
  resource_group_name = azurerm_resource_group.project_rg.name
  location            = azurerm_service_plan.project_appplan.location
  service_plan_id     = azurerm_service_plan.project_appplan.id
  
  site_config {
    application_stack {
    current_stack = "node"
    node_version = "~16"
  }
  }
  
  app_settings = {
    "WEBSITE_NODE_DEFAULT_VERSION" = "~16"
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = true
    "DATABASE_NAME" = azurerm_cosmosdb_mongo_database.project_cosmosdb.name
    "DATABASE_URL" ="@Microsoft.KeyVault(SecretUri=${azurerm_key_vault.keynewdona.vault_uri}secrets/${azurerm_key_vault_secret.projectsecretnewer.name}/${azurerm_key_vault_secret.projectsecretnewer.version})"  //"@Microsoft.KeyVault(SecretUri=https://keynewdonaectdbstring.vault.azure.net/secrets/projectsecret)"//azurerm_cosmosdb_account.projectcosmosdbacct.connection_strings[0]  
  }
  identity {
    type = "SystemAssigned"
  }
      
  depends_on = [ azurerm_service_plan.project_appplan ]
}



resource "azurerm_cosmosdb_mongo_collection" "projectmongoCollection" {
  name                = "projectmongoCollection"
  resource_group_name = data.azurerm_cosmosdb_account.projectcosmosdbacct.resource_group_name
  account_name        = data.azurerm_cosmosdb_account.projectcosmosdbacct.name
  database_name       = azurerm_cosmosdb_mongo_database.project_cosmosdb.name

  default_ttl_seconds = "777"
  shard_key           = "uniqueKey"
  throughput          = 400

  index {
    keys   = ["_id"]
    unique = true
  }
}


/*resource "azurerm_app_service_source_control" "sourcecontrol" {
  app_id   = azurerm_windows_web_app.MyNodeJsApp.id
  repo_url = "https://github.com/db9crt/node-mongodb-app"
  branch   = "main"
  github_action_configuration {
    generate_workflow_file = true
    code_configuration {
      runtime_stack   = "node"
      runtime_version = "16.0.0"

    }
  }
  depends_on = [ azurerm_source_control_token.dobble_token1 ]
}*/
/*import {
   id = "/subscriptions/27797fca-63b0-46fd-87c7-0757c81e041a/resourceGroups/project_rg/providers/Microsoft.Web/sites/MyNodeJsAppproject"
   to = azurerm_source_control_token.dobble_token1
 }*/
/*  resource "azurerm_source_control_token" "dobble_token1" {
  type  = "GitHub"
  token = "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"
}*/
/*resource "azurerm_ssh_public_key" "sshkey" {
  name                = "sshkey"
  resource_group_name = "project_rg"
  location = "Uk South"
  public_key = trimspace(file("/c/Users/annie/.ssh/id_rsa.pub"))
 
}*/

