# Least-privilege identity for the az-sub-orienteering sweep.
#
# Creates an Entra ID application + service principal, a custom read-only role
# definition, and the handful of built-in role assignments that cover the calls
# a custom role cannot express (data-plane reads, Cost Management).
#
# Self-contained: `terraform init && terraform apply` with only
# `subscription_id` set produces a principal that can run the full suite.
#
# Set assignment_scope = "management_group" to grant the same read-only rights
# across every subscription under a management group instead of one. Nothing
# widens by accident: the scope is one variable, and the actions do not change.
#
# Every action string below was verified against
# `az provider operation show --namespace <ns>` on 2026-09-17. Azure matches
# action strings case-insensitively, so the casing here is cosmetic.

terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}

provider "azuread" {}

# ---------------------------------------------------------------------------
# Inputs
# ---------------------------------------------------------------------------

variable "subscription_id" {
  description = "Subscription the azurerm provider authenticates against, and the default grant scope. Always required, even in management_group mode, because the provider needs an anchor."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.subscription_id))
    error_message = "subscription_id must be a GUID."
  }
}

variable "assignment_scope" {
  description = <<-EOT
    Where the role is defined and assigned.

    "subscription"     — one subscription, the least-privilege default.
    "management_group" — every subscription under management_group_id, including
                         ones added later. Grants nothing outside the tenant:
                         subscriptions in other tenants are unreachable from a
                         management group in this one.
  EOT
  type        = string
  default     = "subscription"

  validation {
    condition     = contains(["subscription", "management_group"], var.assignment_scope)
    error_message = "assignment_scope must be \"subscription\" or \"management_group\"."
  }
}

variable "name_prefix" {
  description = "Prefix for the application, service principal and role definition. Role definition names must be unique within the tenant."
  type        = string
  default     = "az-sub-orienteering"
}

variable "management_group_id" {
  description = <<-EOT
    Management group ID, not its display name. The tenant root group's ID is the
    tenant GUID.

    In subscription mode this only grants hierarchy read, and empty disables it:
    the inventory module's hierarchy section is then blank rather than failing.
    In management_group mode it is the grant scope and is required.
  EOT
  type        = string
  default     = ""

  validation {
    condition     = var.assignment_scope != "management_group" || var.management_group_id != ""
    error_message = "management_group_id is required when assignment_scope is \"management_group\"."
  }
}

variable "grant_cost_management_reader" {
  description = "Assign Cost Management Reader. Required by the cost module and the billing report."
  type        = bool
  default     = true
}

variable "grant_storage_blob_data_reader" {
  description = "Assign Storage Blob Data Reader. Required by the storage module, which lists containers with --auth-mode login."
  type        = bool
  default     = true
}

variable "grant_key_vault_reader" {
  description = "Assign Key Vault Reader. Covers object listing on RBAC-enabled vaults only."
  type        = bool
  default     = true
}

variable "access_policy_vault_ids" {
  description = <<-EOT
    Resource IDs of vaults with enableRbacAuthorization = false. Azure RBAC grants
    no data-plane access on these at any level, including Owner, so each needs an
    entry in its own access policy list. Leave empty and the sweep reports a dash
    for object counts, which is honest but less useful.
  EOT
  type        = list(string)
  default     = []
}

variable "credential_lifetime" {
  description = "Lifetime of the generated client secret. A discovery engagement should outlive neither its credential nor its scope."
  type        = string
  default     = "2160h"
}

variable "tags" {
  description = "Tags applied to nothing directly, but recorded on the application for provenance."
  type        = map(string)
  default = {
    purpose = "az-sub-orienteering discovery sweep"
  }
}

data "azurerm_client_config" "current" {}

data "azurerm_subscription" "target" {
  subscription_id = var.subscription_id
}

locals {
  management_group_scope = var.management_group_id == "" ? "" : "/providers/Microsoft.Management/managementGroups/${var.management_group_id}"

  tenant_wide = var.assignment_scope == "management_group"

  # Every role definition and assignment hangs off this one value.
  grant_scope = local.tenant_wide ? local.management_group_scope : data.azurerm_subscription.target.id
}

# ---------------------------------------------------------------------------
# Principal
# ---------------------------------------------------------------------------

resource "azuread_application" "sweep" {
  display_name     = var.name_prefix
  description      = "Read-only discovery sweep of ${local.grant_scope}. No write, no key retrieval, no secret values."
  owners           = [data.azurerm_client_config.current.object_id]
  sign_in_audience = "AzureADMyOrg"

  tags = [for k, v in var.tags : "${k}=${v}"]
}

resource "azuread_service_principal" "sweep" {
  client_id                    = azuread_application.sweep.client_id
  app_role_assignment_required = false
  owners                       = [data.azurerm_client_config.current.object_id]

  description = "Runs az-sub-orienteering. Holds the Discovery Sweep Reader role and nothing else."
  notes       = "Validate by running the full sweep as this principal and inspecting raw/**/*.json.err, not the exit code."
}

resource "time_rotating" "credential" {
  rotation_rfc3339 = timeadd(timestamp(), var.credential_lifetime)

  lifecycle {
    ignore_changes = [rotation_rfc3339]
  }
}

resource "azuread_service_principal_password" "sweep" {
  service_principal_id = azuread_service_principal.sweep.id
  end_date             = time_rotating.credential.rotation_rfc3339

  rotate_when_changed = {
    rotation = time_rotating.credential.id
  }
}

# ---------------------------------------------------------------------------
# Custom role
# ---------------------------------------------------------------------------

resource "azurerm_role_definition" "sweep" {
  name        = "${var.name_prefix}-discovery-sweep-reader"
  scope       = local.grant_scope
  description = "Read-only discovery of an Azure estate. No data-plane access, no key retrieval, no writes."

  permissions {
    actions = [
      # Inventory: subscription, groups, resources, tags, locks, providers.
      "Microsoft.Resources/subscriptions/read",
      "Microsoft.Resources/subscriptions/resourceGroups/read",
      "Microsoft.Resources/subscriptions/resources/read",
      "Microsoft.Resources/subscriptions/providers/read",
      "Microsoft.Resources/providers/read",
      "Microsoft.Resources/tags/read",
      "Microsoft.Authorization/locks/read",

      # Management group hierarchy. getEntities is evaluated above the
      # subscription, so this action alone does not satisfy it: the
      # Management Group Reader assignment below is what makes it work.
      "Microsoft.Management/managementGroups/read",
      "Microsoft.Management/getEntities/action",

      # Identity.
      "Microsoft.Authorization/roleAssignments/read",
      "Microsoft.Authorization/roleDefinitions/read",
      "Microsoft.ManagedIdentity/userAssignedIdentities/read",

      # Governance. `az policy state list` hits policyStates/queryResults/read
      # and `summarize` hits an action, so policyStates/read alone reads nothing.
      "Microsoft.Authorization/policyAssignments/read",
      "Microsoft.Authorization/policyExemptions/read",
      "Microsoft.PolicyInsights/*/read",
      "Microsoft.PolicyInsights/policyStates/queryResults/action",
      "Microsoft.PolicyInsights/policyStates/summarize/action",

      # Resource Graph, used by the exposure and network modules.
      "Microsoft.ResourceGraph/resources/read",

      # Cost. An action, not a read: a role built only from */read misses it.
      "Microsoft.CostManagement/query/action",

      "Microsoft.Advisor/recommendations/read",
      "Microsoft.Security/*/read",
      "Microsoft.Insights/*/read",
      "Microsoft.OperationalInsights/workspaces/read",

      "Microsoft.Network/*/read",
      "Microsoft.Compute/*/read",
      "Microsoft.ContainerService/managedClusters/read",
      "Microsoft.ContainerRegistry/registries/read",
      "Microsoft.App/*/read",
      "Microsoft.Web/sites/read",
      "Microsoft.Web/serverfarms/read",

      "Microsoft.Storage/storageAccounts/read",
      "Microsoft.Sql/*/read",
      "Microsoft.DBforPostgreSQL/*/read",
      "Microsoft.DBforMySQL/*/read",
      "Microsoft.DocumentDB/databaseAccounts/read",
      "Microsoft.Cache/redis/read",

      "Microsoft.KeyVault/vaults/read",
      "Microsoft.ServiceBus/*/read",
      "Microsoft.EventHub/*/read",
      "Microsoft.EventGrid/*/read",

      "Microsoft.CognitiveServices/accounts/read",
      "Microsoft.CognitiveServices/accounts/deployments/read",
      "Microsoft.MachineLearningServices/workspaces/read",
      "Microsoft.Search/searchServices/read",

      "Microsoft.Cdn/profiles/read",
      "Microsoft.ApiManagement/service/read",

      "Microsoft.RecoveryServices/vaults/read",
      "Microsoft.RecoveryServices/vaults/backupProtectedItems/read",

      "Microsoft.SqlVirtualMachine/sqlVirtualMachines/read",
      "Microsoft.SqlVirtualMachine/sqlVirtualMachineGroups/read",
    ]

    # listKeys hands over every byte in the account, and the wildcard reads
    # above would otherwise pull it in with the rest of the provider.
    not_actions = [
      "Microsoft.Storage/storageAccounts/listKeys/action",
      "Microsoft.Storage/storageAccounts/listAccountSas/action",
      "Microsoft.Storage/storageAccounts/listServiceSas/action",
    ]

    # The suite reports object names and counts, never values. Data-plane read
    # comes from the built-in assignments below, where it can be revoked on its
    # own without touching the role.
    data_actions     = []
    not_data_actions = []
  }

  assignable_scopes = [local.grant_scope]
}

# ---------------------------------------------------------------------------
# Assignments
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "sweep" {
  scope              = local.grant_scope
  role_definition_id = azurerm_role_definition.sweep.role_definition_resource_id
  principal_id       = azuread_service_principal.sweep.object_id
  principal_type     = "ServicePrincipal"
  description        = "az-sub-orienteering discovery sweep"
}

resource "azurerm_role_assignment" "cost_management_reader" {
  count = var.grant_cost_management_reader ? 1 : 0

  scope                = local.grant_scope
  role_definition_name = "Cost Management Reader"
  principal_id         = azuread_service_principal.sweep.object_id
  principal_type       = "ServicePrincipal"
  description          = "cost module and billing report"
}

resource "azurerm_role_assignment" "storage_blob_data_reader" {
  count = var.grant_storage_blob_data_reader ? 1 : 0

  scope                = local.grant_scope
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azuread_service_principal.sweep.object_id
  principal_type       = "ServicePrincipal"
  description          = "container listing via --auth-mode login, so no account key is ever needed"
}

resource "azurerm_role_assignment" "key_vault_reader" {
  count = var.grant_key_vault_reader ? 1 : 0

  scope                = local.grant_scope
  role_definition_name = "Key Vault Reader"
  principal_id         = azuread_service_principal.sweep.object_id
  principal_type       = "ServicePrincipal"
  description          = "vault object names and counts on RBAC-enabled vaults"
}

# Redundant in management_group mode, where the custom role already carries
# getEntities at a scope that can satisfy it.
resource "azurerm_role_assignment" "management_group_reader" {
  count = !local.tenant_wide && var.management_group_id != "" ? 1 : 0

  scope                = local.management_group_scope
  role_definition_name = "Management Group Reader"
  principal_id         = azuread_service_principal.sweep.object_id
  principal_type       = "ServicePrincipal"
  description          = "getEntities, for the inventory hierarchy section"
}

# List only. Get would let the principal read secret values, which the suite
# never does and should never be able to do.
resource "azurerm_key_vault_access_policy" "sweep" {
  for_each = toset(var.access_policy_vault_ids)

  key_vault_id = each.value
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azuread_service_principal.sweep.object_id

  secret_permissions      = ["List"]
  key_permissions         = ["List"]
  certificate_permissions = ["List"]
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "client_id" {
  description = "Application (client) ID of the sweep principal."
  value       = azuread_application.sweep.client_id
}

output "object_id" {
  description = "Service principal object ID. Use this when adding vault access policies by hand."
  value       = azuread_service_principal.sweep.object_id
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "client_secret" {
  description = "Client secret. Move it into the engagement secret store; do not commit it."
  value       = azuread_service_principal_password.sweep.value
  sensitive   = true
}

output "credential_expires" {
  value = azuread_service_principal_password.sweep.end_date
}

output "role_definition_id" {
  value = azurerm_role_definition.sweep.role_definition_resource_id
}

output "grant_scope" {
  description = "Scope the role is defined and assigned at. Everything the principal can read sits under this."
  value       = local.grant_scope
}

output "sweep_subscriptions_command" {
  description = "In management_group mode the sweep still runs one subscription at a time; this enumerates what the principal can now see."
  value       = <<-EOT
    az account list --all --refresh \
      --query "[?tenantId=='${data.azurerm_client_config.current.tenant_id}' && state=='Enabled'].id" \
      --output tsv
  EOT
}

output "login_command" {
  description = "Sign in as the sweep principal. Read the secret with `terraform output -raw client_secret`."
  value       = <<-EOT
    export AZ_SWEEP_CLIENT_ID=${azuread_application.sweep.client_id}
    export AZ_SWEEP_TENANT_ID=${data.azurerm_client_config.current.tenant_id}
    export AZ_SWEEP_SUBSCRIPTION_ID=${var.subscription_id}
    export AZ_SWEEP_SECRET="$(terraform output -raw client_secret)"

    az login --service-principal \
      --username "$${AZ_SWEEP_CLIENT_ID}" \
      --password "$${AZ_SWEEP_SECRET}" \
      --tenant "$${AZ_SWEEP_TENANT_ID}"

    az account set --subscription "$${AZ_SWEEP_SUBSCRIPTION_ID}"
  EOT
}
