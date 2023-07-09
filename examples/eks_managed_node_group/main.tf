data "aws_caller_identity" "current" {}

locals {
  eks_cluster = {
    min_size                 = 3
    max_size                 = 4
    desired_size             = 3
    name                     = var.cluster_name
    version                  = "1.24"
    is_mixed_instance_policy = true
    instance_type            = var.cluster_instance_type
    instances_distribution = {
      on_demand_base_capacity  = 0
      on_demand_percentage_above_base_capacity     = 20
      spot_allocation_strategy = "capacity-optimized"
    }
    override = [
      {
        instance_type     = "t3a.large"
        weighted_capacity = "1"
      },
      {
        instance_type     = "t3.large"
        weighted_capacity = "2"
      },
    ]
    block_device_mappings = {
      xvda = {
        device_name = "/dev/xvda"
        ebs = {
          volume_size           = var.ebs_volume_size
          volume_type           = "gp3"
          iops                  = 3000
          throughput            = 150
          encrypted             = true
          delete_on_termination = true
        }
      }
    }
    #aws eks describe-addon-version
    addons = {
      vpc-cni = {
        resolve_conflicts = "OVERWRITE"
      }
    }
  }
}

provider "kubernetes" {
  host                   = module.eks_cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_cluster.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = ["eks", "get-token", "--cluster-name", local.eks_cluster.name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks_cluster.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_cluster.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = ["eks", "get-token", "--cluster-name", local.eks_cluster.name]
    }
  }
}

module "eks_cluster" {
  #source = "git::https://github.com/tothenew/terraform-aws-eks.git"
  source = "../.."
  cluster_name    = local.eks_cluster.name
  cluster_version = try(local.eks_cluster.version, "1.24")

  cluster_endpoint_private_access = try(local.eks_cluster.cluster_endpoint_private_access, false)
  cluster_endpoint_public_access  = try(local.eks_cluster.cluster_endpoint_public_access, true)

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  #Cluster Level Addons
  cluster_addons = local.eks_cluster.addons
  eks_managed_node_groups = {
    # Default node group - as provisioned by the module defaults
    default_node_group = {
      name = local.eks_cluster.name
  }

  eks_managed_node_group_defaults = {
    instance_type                          = "${local.eks_cluster.instance_type}"
    update_launch_template_default_version = true
    iam_role_additional_policies = [
      "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    ]

  }

    mixed = {
      name = local.eks_cluster.name
      min_size     = try(local.eks_cluster.min_size, 2)
      max_size     = try(local.eks_cluster.max_size, 4)
      desired_size = try(local.eks_cluster.min_size, 2)

      pre_bootstrap_user_data = <<-EOT
        TOKEN=`curl -s  -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
        EC2_LIFE_CYCLE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN"  http://169.254.169.254/latest/meta-data/instance-life-cycle)
        INSTANCE_TYPE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN"  http://169.254.169.254/latest/meta-data/instance-type)
        AVAILABILITY_ZONE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN"  http://169.254.169.254/latest/meta-data/placement/availability-zone)
        EOT

      bootstrap_extra_args = "--kubelet-extra-args '--node-labels=node.kubernetes.io/lifecycle='\"$EC2_LIFE_CYCLE\"' --register-with-taints=instance_type='\"$INSTANCE_TYPE\"':NoSchedule,ec2_lifecycle='\"$EC2_LIFE_CYCLE\"':NoSchedule,availability_zone='\"$AVAILABILITY_ZONE\"':NoSchedule'"

      post_bootstrap_user_data = <<-EOT
        cd /tmp
        sudo yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
        sudo systemctl enable amazon-ssm-agent
        sudo systemctl start amazon-ssm-agent
        EOT

      block_device_mappings = "${local.eks_cluster.block_device_mappings}"
      use_mixed_instances_policy = "${local.eks_cluster.is_mixed_instance_policy}"
      mixed_instances_policy = {
        instances_distribution = "${local.eks_cluster.instances_distribution}"
        override = "${local.eks_cluster.override}"
      }
    }
  }
}

module "cluster_autoscaler" {
  #source = "git::https://github.com/DNXLabs/terraform-aws-eks-cluster-autoscaler.git"
  source = "../../modules/terraform-aws-eks-cluster-autoscaler"
  enabled = true
  cluster_name                     = module.eks_cluster.cluster_id
  cluster_identity_oidc_issuer     = module.eks_cluster.cluster_oidc_issuer_url
  cluster_identity_oidc_issuer_arn = module.eks_cluster.oidc_provider_arn
  aws_region                       = var.aws_region
}

module "node_termination_handler" {
  #source = "git::https://github.com/DNXLabs/terraform-aws-eks-node-termination-handler.git"
  source = "../../modules/terraform-aws-eks-node-termination-handler"
}
