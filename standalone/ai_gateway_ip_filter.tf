# Optional gateway-wide IP allow list for all models, aliases and MCP tool
# servers in the default workspace. Off by default.
#
# - null (default): Terraform does not touch the workspace policies.
# - []: removes the allow list that Terraform wrote earlier.
# - a list: only callers from these ranges can reach the gateway.
#
# Terraform reads the workspace policies, keeps every entry except an earlier
# ipFilter and sends the merged list in one PATCH at apply time. Deleting the
# action sends no request, so apply [] first and then go back to null.
#
# The PATCH must run after every resource in the default workspace. If you add
# one in another file, also add it to depends_on below.
locals {
  gateway_default_workspace_id = "${azapi_resource.ai_gateway.id}/workspaces/default"
  gateway_ip_filter_targets    = var.gateway_allowed_ip_ranges == null ? toset([]) : toset(["default"])
}

data "azapi_resource" "gateway_default_workspace" {
  for_each = local.gateway_ip_filter_targets
  type     = "Microsoft.ApiManagement/aigateways/workspaces@2025-09-01-preview"
  # Use the local, not a direct gateway reference, which would defer this read
  # on every gateway change. A new gateway has no id yet, so the read waits for apply.
  resource_id            = local.gateway_default_workspace_id
  response_export_values = ["properties.policies"]
}

resource "azapi_resource_action" "gateway_ip_filter" {
  for_each    = local.gateway_ip_filter_targets
  type        = "Microsoft.ApiManagement/aigateways/workspaces@2025-09-01-preview"
  resource_id = local.gateway_default_workspace_id
  method      = "PATCH"
  when        = "apply"
  body = {
    properties = {
      policies = concat(try([
        for policy in data.azapi_resource.gateway_default_workspace[each.key].output.properties.policies :
        policy if lower(try(policy.type, "")) != "ipfilter"
        ], []), length(var.gateway_allowed_ip_ranges) == 0 ? [] : [{
        type       = "ipFilter"
        action     = "Allow"
        cidrRanges = sort(distinct(var.gateway_allowed_ip_ranges))
      }])
    }
  }

  depends_on = [
    azapi_resource.ai_gateway_foundry_provider,
    azapi_resource.ai_gateway_telemetry_exporter,
    azapi_resource.ai_gateway_foundry_model,
    azapi_resource.ai_gateway_model_alias,
    azapi_resource.ai_gateway_foundry_model_mini,
    azapi_resource.ai_gateway_model_alias_mini,
    azapi_resource.ai_gateway_model_alias_gpt_latest,
    azapi_resource.ai_gateway_microsoft_learn_mcp,
  ]
}
