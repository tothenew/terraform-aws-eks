locals {
  tolerations = [
    {
      key= "availability_zone",
      operator= "Exists"
      effect= "NoSchedule"
    },
    {
      key= "ec2_lifecycle",
      operator= "Exists"
      effect= "NoSchedule"
    },
    {
      key= "instance_type",
      operator= "Exists"
      effect= "NoSchedule"
    }
  ]
}

resource "helm_release" "spot_termination_handler" {
  depends_on = [var.mod_dependency, kubernetes_namespace.spot_termination_handler]
  count      = var.enabled ? 1 : 0
  name       = var.helm_chart_name
  chart      = var.helm_chart_release_name
  repository = var.helm_chart_repo
  version    = var.helm_chart_version
  namespace  = var.namespace

   dynamic "set" {
    for_each = local.tolerations
    iterator = each
    content {
      name      = "tolerations[${each.key}].key"
      value = each.value.key
    }
  }
  
  dynamic "set" {
    for_each = local.tolerations
    iterator = each
    content {
      name      = "tolerations[${each.key}].operator"
      value = each.value.operator
    }
  }

  dynamic "set" {
    for_each = local.tolerations
    iterator = each
    content {
      name      = "tolerations[${each.key}].effect"
      value = each.value.effect
    }
  }

  values = [
    yamlencode(var.settings)
  ]
}