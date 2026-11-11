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

run "defaults_unchanged" {
  command = plan

  assert {
    condition     = azapi_resource.ms_foundry.body.properties.disableLocalAuth == false
    error_message = "By default, key-based sign-in on the Foundry account must stay on."
  }
}

run "foundry_key_sign_in_off" {
  command = plan

  variables {
    foundry_disable_local_auth = true
  }

  assert {
    condition     = azapi_resource.ms_foundry.body.properties.disableLocalAuth == true
    error_message = "Setting foundry_disable_local_auth must turn off key-based sign-in on the Foundry account."
  }

  assert {
    condition     = azapi_resource.ms_foundry.body.properties.publicNetworkAccess == "Enabled"
    error_message = "Turning off key-based sign-in must not change network access."
  }
}
