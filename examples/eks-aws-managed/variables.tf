variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "eks-managed-cluster"
}

variable "cluster_instance_type" {
  description = "Type of Ec2 Instance for node group"
  type = string
  default = "t3a.medium"
}

variable "ebs_volume_size" {
  description = "Volume Ec2 Instance"
  type = number
  default = "50"
}

variable "vpc_id" {
  description = "ID of the VPC where the cluster and its nodes will be provisioned"
  type        = string
  default     = "vpc-0803d89825ac7428d"
}

variable "subnet_ids" {
  description = "A list of subnet IDs where the nodes/node groups will be provisioned."
  type        = list(string)
  default     = ["subnet-08738b09b2b645723", "subnet-068b2ef2bf59bad62", "subnet-05b5c288fbbb4cfab"]
}

variable "aws_region" {
  type        = string
  description = "AWS region where secrets are stored."
  default = "us-east-1"
}

