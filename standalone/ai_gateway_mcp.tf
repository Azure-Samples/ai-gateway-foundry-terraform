resource "azapi_resource" "ai_gateway_microsoft_learn_mcp" {
  type                      = "Microsoft.ApiManagement/aigateways/workspaces/toolServers@2026-11-01"
  name                      = "microsoft-learn"
  parent_id                 = "${azapi_resource.ai_gateway.id}/workspaces/default"
  schema_validation_enabled = false

  body = {
    properties = {
      toolServerType = "mcp"
      displayName    = "Microsoft Learn"
      description    = "Search Microsoft documentation and code samples."
      blockList      = []
      policies = [
        {
          type       = "requestRateLimit"
          count      = 20
          period     = "minute"
          counterKey = ["identity"]
        }
      ]
      endpoints = [
        {
          namespace = "microsoft-learn"
          kind      = "mcp"
          mode      = "failOpen"
          mcp = {
            endpoint = {
              url = "https://learn.microsoft.com/api/mcp"
            }
            transport = "streamableHttp"
          }
        }
      ]
    }
  }
}