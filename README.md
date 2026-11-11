# Azure AI Gateway with Microsoft Foundry models - Terraform

Deploy a standalone Azure AI Gateway service connected with Microsoft Foundry using Terraform. Applications can use a common gateway for model routing, per-caller usage policies, Microsoft Learn MCP tools, and OpenTelemetry monitoring. The gateway authenticates to Foundry with a managed identity instead of backend API keys.

> The gateway uses `Microsoft.ApiManagement/aigateways@2025-09-01-preview`. Access, supported regions, model availability, and quota depend on your Azure subscription.

## What is deployed

| Resource | Configuration |
| --- | --- |
| Resource group | Creates a group, or uses an existing group supplied through `resource_group_name`. |
| Azure AI Gateway | Standalone gateway with a system-assigned managed identity; child resources use its service-provided `default` workspace. |
| Microsoft Foundry account | `AIServices` account with the `S0` SKU and a user-assigned managed identity. |
| Foundry project | A project in the new account, using the same user-assigned identity. |
| Model deployments | Two `GlobalStandard` OpenAI deployments, each with capacity `100`. |
| Gateway model catalog and aliases | Registers both deployments and creates the three aliases described below. |
| Microsoft Learn MCP | Registers `https://learn.microsoft.com/api/mcp` with `streamableHttp` transport and a per-identity limit of 20 requests per 60 seconds. |
| Monitoring | Log Analytics with 30-day retention, workspace-based Application Insights, and a managed-identity OpenTelemetry exporter. |
| Role assignments | Grants gateway-to-Foundry access, Foundry identity access to the gateway, and monitoring permissions. |


### Models and caller policies

The policies are defined in [ai_gateway_models.tf](./standalone/ai_gateway_models.tf); the underlying deployments are defined in [ms_foundry_models.tf](./standalone/ms_foundry_models.tf).

| Model and deployment name | Initial version | Capacity | Tokens per identity per minute | Monthly cost limit per identity | Content safety |
| --- | --- | --- | --- | --- | --- |
| `gpt-6.1-sol` | `2026-09-29` | `100` | `10000` | USD `10` | `Medium` for hate, self-harm, sexual, and violence content. |
| `gpt-5-mini` | `2025-08-07` | `100` | No token-limit policy configured. | USD `100` | No gateway content-safety policy configured. |

Both deployments use the `Microsoft.DefaultV2` responsible AI policy and `OnceNewDefaultVersionAvailable` version upgrades. Gateway policy differences do not remove the underlying model's safety controls.

The model registrations declare `/openai/v1/chat/completions` and `/openai/v1/responses` as supported endpoints. The operation must also be supported by the selected backend model.

### Aliases and routing

| Alias | Backend routing |
| --- | --- |
| `gpt-6.1-sol` | Routes directly to `gpt-6.1-sol`, priority `0`, weight `100`. |
| `gpt-5-mini` | Routes directly to `gpt-5-mini`, priority `0`, weight `100`. |
| `gpt-latest` | Prefers `gpt-6.1-sol` at priority `0`, weight `70`; fails over to `gpt-5-mini` at priority `1`, weight `30`. |

Lower priority values take precedence. Weights balance traffic only among backends with the same priority: the default `gpt-latest` configuration is **failover, not a 70:30 traffic split**. Clients select an alias in the request's model field.

## Prerequisites and costs

- An Azure subscription.
- [Terraform CLI](https://developer.hashicorp.com/terraform/install), [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli), and Git.
- [Azure Developer CLI (`azd`)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd) if using the azd deployment option below.
- A deployment identity allowed to create the resources and their role assignments, including the monitoring Data Collection Rule (DCR) role assignment. Owner, or appropriately scoped Contributor and Role Based Access Control Administrator permissions, may be required.
- The relevant resource providers registered in the subscription: `Microsoft.ApiManagement`, `Microsoft.CognitiveServices`, `Microsoft.ManagedIdentity`, `Microsoft.OperationalInsights`, and `Microsoft.Insights`.

The provider versions are pinned in [providers.tf](./standalone/providers.tf): `hashicorp/azurerm` `5.12.0`, `Azure/azapi` `2.10.0`, and `hashicorp/random` `3.9.1`.

The offline tests in `standalone/tests/` use mock providers, which need Terraform 1.7 or later. Because `terraform init` and `terraform validate` also read that folder, use Terraform 1.7 or later with this repository.


## Deploy with Azure Developer CLI

Following the [AI Gateway infrastructure-as-code quickstart](https://ai.gateway.azure.com/docs/quickstarts/iac), you can provision this infrastructure-only sample with `azd`. Run from the repository root:

```bash
git clone https://github.com/Azure-Samples/ai-gateway-foundry-terraform.git
cd ai-gateway-foundry-terraform

az login
azd auth login
azd env new dev --location swedencentral --subscription "<subscription-id>"
azd provision
```

## Deploy with Terraform

### 1. Authenticate and select a subscription

```bash
git clone https://github.com/Azure-Samples/ai-gateway-foundry-terraform.git
cd ai-gateway-foundry-terraform/standalone

az login
az account set --subscription "<subscription-id>"
export ARM_SUBSCRIPTION_ID="$(az account show --query id --output tsv)"
```

### 2. Configure the deployment

The default location is `swedencentral`. Confirm access and model availability before using it. To customize the deployment, save a `terraform.tfvars` file in `standalone/`, for example:

```hcl
domain      = "ai"
workload    = "gw"
environment = "dev"
location    = "swedencentral"
region      = "swc"

tags = {
  Project = "ai-gateway"
}
```

To use an existing resource group, also set:

```hcl
resource_group_name = "my-existing-resource-group"
```

An existing group's location overrides `location` for deployed resources. `region` is only a naming abbreviation; it does not select an Azure region. Leave `resource_group_name` empty to create a new group.

### 3. Initialize, review, and apply

Run these commands from `standalone/`:

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Review the plan before applying, especially the target subscription, region, model capacity, and role scopes.

There are no Terraform output declarations or explicit gateway runtime API-key resources in this sample. Inspect the deployed resources in the Azure portal for endpoint details. The Foundry identity receives **AI Gateway User**; other callers need their own gateway access assignment.

## Input variables

All current inputs are declared in [variables.tf](./standalone/variables.tf).

| Variable | Purpose | Default |
| --- | --- | --- |
| `domain` | Domain component of generated resource names. | `"ai"` |
| `workload` | Workload component of generated resource names. | `"gw"` |
| `environment` | Environment label; intended values are `dev`, `stg`, or `pro`. | `"dev"` |
| `location` | Resource location when creating a resource group. | `"swedencentral"` |
| `region` | Short region label used in resource names. | `"swc"` |
| `tags` | Custom resource tags, merged with the built-in tags in `locals.tf`. | `{}` |
| `resource_group_name` | Existing resource group name; empty creates a new group. | `""` |
| `foundry_disable_local_auth` | Optional; `true` turns off key-based sign-in on the Foundry account; see [Optional network and access settings](#optional-network-and-access-settings). | `false` |

Resource names combine the environment, region label, domain, workload, and a random suffix. Built-in tag values take precedence over matching custom tag keys.

## Customize routing and governance

Model capacity and versions are currently configured directly in [ms_foundry_models.tf](./standalone/ms_foundry_models.tf). Change gateway token limits, caller budgets, content-safety thresholds, and aliases in [ai_gateway_models.tf](./standalone/ai_gateway_models.tf). MCP throttling is configured in [ai_gateway_mcp.tf](./standalone/ai_gateway_mcp.tf).

For weighted load balancing instead of failover, replace the `backendModels` list of `ai_gateway_model_alias_gpt_latest` with:

```hcl
backendModels = [
  {
    resourceId = azapi_resource.ai_gateway_foundry_model.id
    priority   = 0
    weight     = 80
  },
  {
    resourceId = azapi_resource.ai_gateway_foundry_model_mini.id
    priority   = 0
    weight     = 20
  }
]
```

This puts both backends at priority `0` with an 80:20 preference. Actual distribution depends on traffic and backend availability. Review a new Terraform plan before applying any changes.

## Identity, networking, and monitoring

The gateway's system-assigned identity receives **Azure AI User** on the Foundry account. The shared Foundry account/project user-assigned identity receives **Foundry User** on the project, **AI Gateway User** on the gateway, and **Monitoring Metrics Publisher** on Application Insights. The deployment principal receives **Foundry User** and **Foundry Project Manager** on the account and project.

**Security defaults:** Managed identity is used for gateway-to-Foundry calls, but Foundry local key authentication remains enabled by default (`disableLocalAuth = false`); to turn it off, see [Require Microsoft Entra ID sign-in on the Foundry account](#require-microsoft-entra-id-sign-in-on-the-foundry-account). The Foundry account also enables public network access with a default network action of `Allow`. Review these settings before production use; this is not a private-network deployment.

Application Insights enables Azure Monitor workspace ingestion. Terraform reads its managed DCR and OTLP metrics, logs, and traces endpoints, grants the gateway **Monitoring Metrics Publisher** on that DCR, and configures the telemetry exporter. Request and response payload capture is disabled.

Operational considerations:

- **Role propagation:** New role assignments may take several minutes to become effective. A completed apply does not guarantee immediate data-plane access.
- **Monitoring readiness:** If Application Insights has not populated its ingestion endpoints or managed DCR, the configuration fails with an explicit postcondition message. Wait for Azure provisioning to complete, then run `terraform plan` and `terraform apply` again.
- **Monitoring permissions:** A DCR role-assignment authorization failure requires suitable permissions at that scope. Do not assume resource-group permissions cover a DCR in an Azure-managed resource group.
- **Model deployment failures:** Verify region availability, model access, and quota for the configured versions and capacities.

## Optional network and access settings

The settings in this section are off by default; when they are unset, the deployment is unchanged. They never create a virtual network, subnet, or DNS zone; settings that need one take the ID of an existing resource.

Set them in `standalone/terraform.tfvars`. Terraform loads that file automatically, also when azd runs Terraform in `standalone/`, and `.gitignore` keeps `*.tfvars` files out of version control.

Offline tests for these settings are in `standalone/tests/`. They mock all providers, so they never call Azure. Run `terraform init` and then `terraform test` from `standalone/`.

### Require Microsoft Entra ID sign-in on the Foundry account

`foundry_disable_local_auth` turns off key-based sign-in on the Foundry account, so callers must sign in with Microsoft Entra ID. The gateway is not affected, because it always calls Foundry with its managed identity.

| Value | Effect |
| --- | --- |
| `false` (default) | The account accepts Microsoft Entra ID tokens and account keys. |
| `true` | The account accepts Microsoft Entra ID tokens only (`disableLocalAuth = true`). |

Before enabling it, consider:

- **Key-based callers:** Apps, scripts, and tools that call the Foundry account with an account key stop working. Move them to Microsoft Entra ID first, and give them a suitable role on the account, such as **Foundry User** (previously named Azure AI User).
- **Azure Policy:** If your organization denies key-based sign-in with Azure Policy, the default deployment can be blocked. Setting this value to `true` lets the deployment comply.
- **Removal:** Set the value back to `false`, or remove the line, and apply again to turn key-based sign-in back on. As with turning it off, the change can take a while to reach the service.
- **Check after enabling:** Run the following command. It prints `true` when key-based sign-in is off.

  ```bash
  az cognitiveservices account show --name <foundry-account> --resource-group <resource-group> --query properties.disableLocalAuth
  ```

  The setting itself changes right away, but the service can keep accepting existing keys until its cached settings refresh. Microsoft's guidance says this usually takes a few minutes but can take up to several hours. To confirm that keys no longer work, send one request with an old key directly to the Foundry account, from a network that can reach it, and check that it is rejected with the error code `AuthenticationTypeDisabled`. For details, see *Disable local authentication in Foundry Tools* on Microsoft Learn.

## Clean up

For an azd deployment, run from the repository root with the same azd environment selected:

```bash
azd down
```

For a standalone Terraform deployment, run from `standalone/`, using the same subscription and Terraform state:

```bash
terraform plan -destroy -out=destroy.tfplan
terraform apply destroy.tfplan
```

Review the destruction plan carefully. A resource group created by this configuration is deleted along with its contents; do not put unrelated resources in it. An existing resource group supplied through `resource_group_name` is not managed or deleted by this configuration, but the resources created inside it are removed.

## References

- [AI Gateway capabilities](https://learn.microsoft.com/azure/api-management/genai-gateway-capabilities)
- [Microsoft Foundry documentation](https://learn.microsoft.com/azure/ai-foundry/)
- [Azure OpenAI role-based access control](https://learn.microsoft.com/azure/ai-foundry/openai/how-to/role-based-access-control)
- [Terraform on Azure](https://learn.microsoft.com/azure/developer/terraform/)
- [Azure Developer CLI Terraform support](https://learn.microsoft.com/azure/developer/azure-developer-cli/use-terraform-for-azd)
- [AzAPI provider documentation](https://registry.terraform.io/providers/Azure/azapi/latest/docs)