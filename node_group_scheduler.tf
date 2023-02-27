resource "aws_autoscaling_schedule" "eks_stop" {
  depends_on = [
    module.self_managed_node_group,
    module.eks_managed_node_group
  ]
  for_each = { for k, v in module.self_managed_node_group : k=>v if var.enable_schedule }
  scheduled_action_name  = "self-managed-nodegroup-${var.cluster_name}-stop"
  min_size               = 0
  max_size               = 0
  desired_capacity       = 0
  autoscaling_group_name = each.value.autoscaling_group_name
  recurrence             = var.schedule_cron_stop
}

resource "aws_autoscaling_schedule" "eks_start" { 
  depends_on = [
    module.self_managed_node_group,
    module.eks_managed_node_group
  ]
  for_each = { for k, v in module.self_managed_node_group : k=>v if var.enable_schedule }
  scheduled_action_name  = "self-managed-nodegroup-${var.cluster_name}-start"
  min_size               = try(each.value.autoscaling_group_min_size,var.self_managed_node_group_defaults.min_size, 0)
  max_size               = try(each.value.autoscaling_group_max_size,var.self_managed_node_group_defaults.max_size, 3)
  desired_capacity       = try(each.value.autoscaling_group_desired_capacity,var.self_managed_node_group_defaults.desired_size, 1)
  autoscaling_group_name = each.value.autoscaling_group_name
  recurrence             = var.schedule_cron_start
}