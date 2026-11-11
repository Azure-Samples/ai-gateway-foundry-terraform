# Offline tests for the optional network switches.
# All three providers are mocked, so no run calls Azure or creates anything.
# The overrides give mocked resources fake, ARM-shaped IDs so that the
# providers' own ID checks pass when a run uses command = apply.
# Mock providers need Terraform 1.7 or later; these tests were run with 1.11.
mock_provider "azurerm" {}
mock_provider "azapi" {}
mock_provider "random" {}

override_resource {
  target = azurerm_resource_group.this
  values = {
    id = "/subscriptions/sub/resourceGroups/rg"
  }
}

override_resource {
  target = azurerm_user_assigned_identity.this
  values = {
    id = "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/n1"
  }
}

override_resource {
  target = azapi_resource.log_analytics_workspace
  values = {
    id = "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/n2"
  }
}

override_resource {
  target = azapi_resource.application_insights
  values = {
    id = "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Insights/components/n3"
  }
}

override_resource {
  target = azapi_resource.ms_foundry
  values = {
    id = "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.CognitiveServices/accounts/n4"
    output = {
      properties = {
        endpoint = "endpoint-placeholder"
      }
    }
  }
}

override_resource {
  target = azapi_resource.ms_foundry_project
  values = {
    id = "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.CognitiveServices/accounts/n4/projects/n5"
  }
}

override_resource {
  target = azapi_resource.ai_gateway
  values = {
    id = "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.ApiManagement/aigateways/n6"
  }
}

override_resource {
  target = azapi_resource.ai_gateway_foundry_provider
  values = {
    id = "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.ApiManagement/aigateways/n6/workspaces/default/modelProviders/n7"
  }
}

override_data {
  target = data.azapi_resource.monitoring_ingestion
  values = {
    output = {
      metrics_endpoint = "metrics-placeholder"
      logs_endpoint    = "logs-placeholder"
      traces_endpoint  = "traces-placeholder"
      dcr_id           = "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Insights/dataCollectionRules/n8"
      workspace_id     = "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/n2"
    }
  }
}

# Existing default-workspace policies, used unless a run overrides them.
override_data {
  target = data.azapi_resource.gateway_default_workspace
  values = {
    output = {
      properties = {
        policies = [
          { type = "tokenLimit", tokensPerMinute = 1000 },
          { type = "IPFILTER", action = "Allow", cidrRanges = ["old-entry"] },
        ]
      }
    }
  }
}

run "defaults_unchanged" {
  command = plan

  assert {
    condition     = length(data.azapi_resource.gateway_default_workspace) == 0 && length(azapi_resource_action.gateway_ip_filter) == 0
    error_message = "With the allow list unset, the sample must not read or change the gateway's default workspace."
  }
}

run "ip_filter_keeps_other_policies" {
  command = apply

  variables {
    gateway_allowed_ip_ranges = [
      format("%d.%d.%d.%d/%d", 203, 0, 113, 0, 24),
      format("%d.%d.%d.%d/%d", 198, 51, 100, 0, 24),
      format("%d.%d.%d.%d/%d", 203, 0, 113, 0, 24),
    ]
  }

  assert {
    condition = (
      azapi_resource_action.gateway_ip_filter["default"].resource_id == "${azapi_resource.ai_gateway.id}/workspaces/default" &&
      azapi_resource_action.gateway_ip_filter["default"].method == "PATCH" &&
      azapi_resource_action.gateway_ip_filter["default"].when == "apply"
    )
    error_message = "The allow list must PATCH this gateway's default workspace, on apply only."
  }

  assert {
    condition = jsonencode(azapi_resource_action.gateway_ip_filter["default"].body) == jsonencode({
      properties = {
        policies = [
          { type = "tokenLimit", tokensPerMinute = 1000 },
          {
            type       = "ipFilter"
            action     = "Allow"
            cidrRanges = [format("%d.%d.%d.%d/%d", 198, 51, 100, 0, 24), format("%d.%d.%d.%d/%d", 203, 0, 113, 0, 24)]
          },
        ]
      }
    })
    error_message = "The PATCH must keep other policies, replace an existing IP filter in any letter case, and send one sorted list without duplicates."
  }
}

run "ip_filter_empty_list_removes_only_filter" {
  command = apply

  variables {
    gateway_allowed_ip_ranges = []
  }

  assert {
    condition = jsonencode(azapi_resource_action.gateway_ip_filter["default"].body) == jsonencode({
      properties = { policies = [{ type = "tokenLimit", tokensPerMinute = 1000 }] }
    })
    error_message = "An empty list must remove only the IP filter and keep the other workspace policies."
  }
}

run "ip_filter_on_workspace_without_policies" {
  command = apply

  variables {
    gateway_allowed_ip_ranges = [format("%x:%x::/%d", 8193, 3512, 32)]
  }

  override_data {
    target = data.azapi_resource.gateway_default_workspace
    values = { output = { properties = {} } }
  }

  assert {
    condition = jsonencode(azapi_resource_action.gateway_ip_filter["default"].body.properties.policies) == jsonencode([
      { type = "ipFilter", action = "Allow", cidrRanges = [format("%x:%x::/%d", 8193, 3512, 32)] }
    ])
    error_message = "A workspace without policies must receive exactly the configured IP filter."
  }
}
run "reject_invalid_ipv4_range" {
  command = plan

  variables {
    gateway_allowed_ip_ranges = [format("%d.%d.%d.%d/%d", 300, 0, 113, 0, 24)]
  }

  expect_failures = [var.gateway_allowed_ip_ranges]
}

run "reject_ipv6_prefix_too_long" {
  command = plan

  variables {
    gateway_allowed_ip_ranges = [format("%x:%x::/%d", 8193, 3512, 129)]
  }

  expect_failures = [var.gateway_allowed_ip_ranges]
}

run "reject_allow_all_range" {
  command = plan

  variables {
    gateway_allowed_ip_ranges = [format("%d.%d.%d.%d/%d", 0, 0, 0, 0, 0)]
  }

  expect_failures = [var.gateway_allowed_ip_ranges]
}

run "reject_zero_padded_allow_all_range" {
  command = plan

  variables {
    gateway_allowed_ip_ranges = [format("::/%s", "00")]
  }

  expect_failures = [var.gateway_allowed_ip_ranges]
}

run "reject_leading_zero_ipv4_part" {
  command = plan

  variables {
    gateway_allowed_ip_ranges = [format("%d.%d.%s.%d/%d", 192, 0, "02", 0, 24)]
  }

  expect_failures = [var.gateway_allowed_ip_ranges]
}

run "reject_leading_zero_prefix_length" {
  command = plan

  variables {
    gateway_allowed_ip_ranges = [format("%x:%x::/%s", 8193, 3512, "032")]
  }

  expect_failures = [var.gateway_allowed_ip_ranges]
}

run "accept_zero_padded_ipv6_groups" {
  command = plan

  variables {
    gateway_allowed_ip_ranges = [format("%s:%s::/%d", "2001", "0db8", 32)]
  }

  assert {
    condition     = length(azapi_resource_action.gateway_ip_filter) == 1
    error_message = "The leading-zero rule must reject only decimal IPv4 parts and prefix lengths, not hexadecimal IPv6 groups."
  }
}