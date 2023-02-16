resource "aws_autoscaling_schedule" "eks_stop" {
  depends_on = [
    module.self_managed_node_group
  ]
  for_each = var.enable_schedule ? toset(compact([for group in module.self_managed_node_group : group.autoscaling_group_name])) : []
  scheduled_action_name  = "self-managed-nodegroup-${var.cluster_name}-stop"
  min_size               = 0
  max_size               = 0
  desired_capacity       = 0
  autoscaling_group_name = each.value
  recurrence             = var.schedule_cron_stop
}

resource "aws_autoscaling_schedule" "eks_start" { 
  depends_on = [
    module.self_managed_node_group
  ]
  for_each = var.enable_schedule ? toset(compact([for group in module.self_managed_node_group : group.autoscaling_group_name])) : []
  scheduled_action_name  = "self-managed-nodegroup-${var.cluster_name}-start"
  min_size               = try(var.self_managed_node_group_defaults.min_size, 0)
  max_size               = try(var.self_managed_node_group_defaults.max_size, 3)
  desired_capacity       = try(var.self_managed_node_group_defaults.desired_size, 1)
  autoscaling_group_name = each.value
  recurrence             = var.schedule_cron_start
}