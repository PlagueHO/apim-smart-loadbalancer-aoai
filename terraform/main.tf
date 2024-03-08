# Variables
variable "base_resource_name" {
  type = string
  description = "The string to prefix to all resources"
  default = "demo-smartaoai"
}

variable "resource_group_name" {
  type = string
  description = "Name of the resource group to deploy the Smart Azure OpenAI to"
  default = "demo-smartaoai-rg"
}

variable "location_code" {
  type = string
  description = "The Azure region to deploy the resources to"
  default = "eastus"
}

locals {
  smartaoai_service_11_name = format("%s-11-aoai", var.base_resource_name)
  smartaoai_service_12_name = format("%s-12-aoai", var.base_resource_name)
  smartaoai_service_21_name = format("%s-21-aoai", var.base_resource_name)
}

# Create resource group
resource "azurerm_resource_group" "smartaoai-resource-group" {
  name     = var.resource_group_name
  location = var.location_code
}

# Create Application Inisghts for use with APIM
resource "azurerm_application_insights" "smartaoai-app-insights" {
  name                = format("%s-ai", var.base_resource_name)
  location            = azurerm_resource_group.smartaoai-resource-group.location
  resource_group_name = azurerm_resource_group.smartaoai-resource-group.name
  application_type    = "web"
}

# Azure API Management
resource "azurerm_api_management" "smartaoai-apim" {
  name                = format("%s-apim", var.base_resource_name)
  location            = azurerm_resource_group.smartaoai-resource-group.location
  resource_group_name = azurerm_resource_group.smartaoai-resource-group.name
  publisher_email     = "test@contoso.com"
  publisher_name      = "Contoso Ltd."
  sku_name            = "Developer_1"
  identity {
    type = "SystemAssigned"
  }
}

# Create AOAI Priority 1 group
# AOAI service 1-1
resource "azurerm_cognitive_account" "smartaoai-service-11" {
  name                = local.smartaoai_service_11_name
  location            = var.location_code
  resource_group_name = azurerm_resource_group.smartaoai-resource-group.name
  kind                = "OpenAI"
  sku_name = "S0"
  custom_subdomain_name = local.smartaoai_service_11_name
}

resource "azurerm_cognitive_deployment" "gpt-35-turbo-11" {
  name                 = "gpt-35-turbo"
  cognitive_account_id = azurerm_cognitive_account.smartaoai-service-11.id
  model {
    format  = "OpenAI"
    name    = "gpt-35-turbo"
    version = "0613"
  }

  scale {
    type = "Standard"
    capacity = 120
  }
}

# AOAI service 1-2
resource "azurerm_cognitive_account" "smartaoai-service-12" {
  name                = local.smartaoai_service_12_name
  location            = "eastus2"
  resource_group_name = azurerm_resource_group.smartaoai-resource-group.name
  kind                = "OpenAI"
  sku_name = "S0"
  custom_subdomain_name = local.smartaoai_service_12_name
}

resource "azurerm_cognitive_deployment" "gpt-35-turbo-12" {
  name                 = "gpt-35-turbo"
  cognitive_account_id = azurerm_cognitive_account.smartaoai-service-12.id
  model {
    format  = "OpenAI"
    name    = "gpt-35-turbo"
    version = "0613"
  }

  scale {
    type = "Standard"
    capacity = 120
  }
}

# Create AOAI Priority 2 group
# AOAI service 2-1
resource "azurerm_cognitive_account" "smartaoai-service-21" {
  name                = local.smartaoai_service_21_name
  location            = "canadaeast"
  resource_group_name = azurerm_resource_group.smartaoai-resource-group.name
  kind                = "OpenAI"
  sku_name = "S0"
  custom_subdomain_name = local.smartaoai_service_21_name
}

resource "azurerm_cognitive_deployment" "gpt-35-turbo-21" {
  name                 = "gpt-35-turbo"
  cognitive_account_id = azurerm_cognitive_account.smartaoai-service-21.id
  model {
    format  = "OpenAI"
    name    = "gpt-35-turbo"
    version = "0613"
  }

  scale {
    type = "Standard"
    capacity = 120
  }
}

# Give Azure APIM access to the all AOAI services
resource "azurerm_role_assignment" "aoai11" {
  scope                = azurerm_cognitive_account.smartaoai-service-11.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_api_management.smartaoai-apim.identity[0].principal_id
}

resource "azurerm_role_assignment" "aoai12" {
  scope                = azurerm_cognitive_account.smartaoai-service-12.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_api_management.smartaoai-apim.identity[0].principal_id
}

resource "azurerm_role_assignment" "aoai21" {
  scope                = azurerm_cognitive_account.smartaoai-service-21.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_api_management.smartaoai-apim.identity[0].principal_id
}

# Create API in APIM
resource "azurerm_api_management_api" "smart-api" {
  name                = "aoai-smart-api"
  resource_group_name = azurerm_resource_group.smartaoai-resource-group.name
  api_management_name = azurerm_api_management.smartaoai-apim.name
  revision            = "1"
  display_name        = "aoai-smart-api"
  path                = "smart-api/openai"
  protocols           = ["https"]

  import {
    content_format = "openapi"
    content_value  = file("${path.module}/inference-2023-12-01-preview.json")
  }

  subscription_key_parameter_names {
    header = "api-key"
    query = "subscription-key"
  }
}

# Create APIM Logger
resource "azurerm_api_management_logger" "smartaoai-apim-logger" {
  name                = "apimlogger"
  api_management_name = azurerm_api_management.smartaoai-apim.name
  resource_group_name = azurerm_resource_group.smartaoai-resource-group.name

  application_insights {
    instrumentation_key = azurerm_application_insights.smartaoai-app-insights.instrumentation_key
  }
}

# Create APIM Diagnostic
resource "azurerm_api_management_api_diagnostic" "apim-diag" {
  identifier               = "applicationinsights"
  resource_group_name      = azurerm_resource_group.smartaoai-resource-group.name
  api_management_name      = azurerm_api_management.smartaoai-apim.name
  api_name                 = azurerm_api_management_api.smart-api.name
  api_management_logger_id = azurerm_api_management_logger.smartaoai-apim-logger.id

  sampling_percentage       = 5.0
  always_log_errors         = true
  log_client_ip             = true
  verbosity                 = "verbose"
  http_correlation_protocol = "W3C"

  frontend_request {
    body_bytes = 32
    headers_to_log = [
      "content-type",
      "accept",
      "origin",
    ]
  }

  frontend_response {
    body_bytes = 32
    headers_to_log = [
      "content-type",
      "content-length",
      "origin",
    ]
  }

  backend_request {
    body_bytes = 32
    headers_to_log = [
      "content-type",
      "accept",
      "origin",
    ]
  }

  backend_response {
    body_bytes = 32
    headers_to_log = [
      "content-type",
      "content-length",
      "origin",
    ]
  }
}


# Edit XML to include above AOAI configuration
data "template_file" "apim-policy" {
  template = file("${path.module}/apim-policy.xml")
  vars = {
    aoai-service-name-11 = azurerm_cognitive_account.smartaoai-service-11.endpoint
    aoai-service-name-12 = azurerm_cognitive_account.smartaoai-service-12.endpoint
    aoai-service-name-21 = azurerm_cognitive_account.smartaoai-service-21.endpoint
  }
}

# Apply smart load balancing policy
resource "azurerm_api_management_api_policy" "smart-policy" {
  api_name            = azurerm_api_management_api.smart-api.name
  api_management_name = azurerm_api_management.smartaoai-apim.name
  resource_group_name = azurerm_resource_group.smartaoai-resource-group.name

  xml_content = "${data.template_file.apim-policy.rendered}"
}