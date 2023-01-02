module "secrets_manager_role" {
  count = var.create_default_irsa ? 1 : 0

  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 4.21.1"

  role_name_prefix = coalesce(var.iam_role_name, "${var.cluster_name}-sm-csi-")
  role_description = "EKS Cluster ${var.cluster_name} Secret Manager CSI Driver role"

  attach_external_secrets_policy        = true
  external_secrets_ssm_parameter_arns   = var.external_secrets_ssm_parameter_arns
  external_secrets_secrets_manager_arns = var.external_secrets_secrets_manager_arns

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = var.namespace_service_accounts
    }
  }
}
