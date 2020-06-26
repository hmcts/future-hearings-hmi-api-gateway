locals {
  s2sUrl = "http://rpe-service-auth-provider-${var.env}.service.core-compute-${var.env}.internal"
  # list of the thumbprints of the SSL certificates that should be accepted by the API (gateway)
  thumbprints_in_quotes = "${formatlist("&quot;%s&quot;", var.api_gateway_test_certificate_thumbprints)}"
  thumbprints_in_quotes_str = "${join(",", local.thumbprints_in_quotes)}"
  api_policy = "${replace(file("template/api-policy.xml"), "ALLOWED_CERTIFICATE_THUMBPRINTS", local.thumbprints_in_quotes_str)}"
  api_base_path = "future-hearings-api"
  dummy = "dummy"
}
data "azurerm_key_vault" "fh_hmi_key_vault" { //assuming here that the name of the key vault is fh_hmi_key_vault
  name = "fh-${var.env}" //assuming here that the name starts with 'fh'
  resource_group_name = "fh-${var.env}" //assuming here that the name of the rg starts with 'fh'
}

data "azurerm_key_vault_secret" "s2s_client_secret" {
  name = "gateway-s2s-client-secret"
  vault_uri = "${data.azurerm_key_vault.fh_hmi_key_vault.vault_uri}"
}

data "azurerm_key_vault_secret" "s2s_client_id" {
  name = "gateway-s2s-client-id"
  vault_uri = "${data.azurerm_key_vault.fh_hmi_key_vault.vault_uri}"
}

data "template_file" "policy_template" {
  template = "${file("${path.module}/template/api-policy.xml")}"

  vars {
    allowed_certificate_thumbprints = "${local.thumbprints_in_quotes_str}"
    s2s_client_id = "${data.azurerm_key_vault_secret.s2s_client_id.value}"
    s2s_client_secret = "${data.azurerm_key_vault_secret.s2s_client_secret.value}"
    s2s_base_url = "${local.s2sUrl}"
  }
}

data "template_file" "api_template" {
  template = "${file("${path.module}/template/api.json")}"
}
resource "azurerm_template_deployment" "api" {
  template_body       = "${data.template_file.api_template.rendered}"
  name                = "${var.product}-api-${var.env}"
  deployment_mode     = "Incremental"
  resource_group_name = "core-infra-${var.env}"
  count               = "${var.env != "preview" ? 1: 0}"

  parameters = {
    apiManagementServiceName  = "core-api-mgmt-${var.env}" // Needs to as per the name of out management service
    apiName                   = "${var.product}-api"
    apiProductName            = "${var.product}"
    serviceUrl                = "http://future-hearings-api-${var.env}.service.core-compute-${var.env}.internal" // assuming this is the nomenclature followed for the backend api
    apiBasePath               = "${local.api_base_path}"
    policy                    = "${data.template_file.policy_template.rendered}"
  }
}
