locals {
  service_account_name = var.service_account_name

  secrets_store_csi_values = {
    image_repository      = var.image_repository
    image_repository_crds = var.image_repository_crds
    image_tag             = var.image_tag

    image_repository_registrar = var.image_repository_registrar
    image_tag_registrar        = var.image_tag_registrar

    image_repository_liveness = var.image_repository_liveness
    image_tag_liveness        = var.image_tag_liveness

    resources_driver    = jsonencode(var.resources_driver)
    resources_registrar = jsonencode(var.resources_registrar)
    resources_liveness  = jsonencode(var.resources_liveness)

    affinity        = jsonencode(var.affinity)
    node_selector   = jsonencode(var.node_selector)
    tolerations     = jsonencode(var.tolerations)
    pod_labels      = jsonencode(var.pod_labels)
    pod_annotations = jsonencode(var.pod_annotations)

    syncSecretEnabled    = var.syncSecretEnabled
    enableSecretRotation = var.enableSecretRotation
  }

  ascp_values = {
    image_registry   = var.ascp_image_registry
    image_repository = var.ascp_image_repository
    image_tag        = var.ascp_image_tag

    node_selector = jsonencode(var.ascp_node_selector)
    tolerations   = jsonencode(var.ascp_tolerations)
    resources     = jsonencode(var.ascp_resources)

    pod_labels      = jsonencode(var.ascp_pod_labels)
    pod_annotations = jsonencode(var.ascp_pod_annotations)

    service_account_name = local.service_account_name
    priority_class_name  = var.ascp_priority_class_name
  }
}

resource "helm_release" "release" {
  name       = var.release_name
  chart      = var.chart_name
  repository = var.chart_repository
  version    = var.chart_version
  namespace  = var.chart_namespace

  max_history = var.max_history
  timeout     = var.chart_timeout

  values = [
    templatefile("${path.module}/templates/secrets_store_csi.yaml", local.secrets_store_csi_values),
  ]
}

resource "helm_release" "ascp" {
  name       = var.ascp_release_name
  chart      = var.ascp_chart_name
  repository = var.ascp_chart_repository
  version    = var.ascp_chart_version
  namespace  = var.ascp_chart_namespace

  max_history = var.max_history
  timeout     = var.ascp_chart_timeout

  values = [
    templatefile("${path.module}/templates/ascp.yaml", local.ascp_values),
  ]
}
