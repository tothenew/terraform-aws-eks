data "aws_caller_identity" "current" {}

locals {
  eks_cluster = {
    min_size                 = 3
    max_size                 = 4
    desired_size             = 3
    name                     = "ttn-eks-self-managed-ayush-2"
    version                  = "1.24"
    is_mixed_instance_policy = true
    instance_type            = "t3a.medium"
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
          volume_size           = 50
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
  source = "../"
  cluster_name    = local.eks_cluster.name
  cluster_version = try(local.eks_cluster.version, "1.24")

  # cluster_security_group_additional_rules = {
  #   egress_nodes_ephemeral_ports_tcp = {
  #     description                = "To node 1025-65535"
  #     protocol                   = "tcp"
  #     from_port                  = 0
  #     to_port                    = 65535
  #     type                       = "ingress"
  #     source_node_security_group = true
  #     cidr_blocks = ["172.31.0.0/16","61.12.91.218/32"]
  #   }
  # }

  # node_security_group_additional_rules = {
  #   ingress_self_all = {
  #     description = "Node to node all ports/protocols"
  #     protocol    = "-1"
  #     from_port   = 0
  #     to_port     = 0
  #     type        = "ingress"
  #     cidr_blocks = ["172.31.0.0/16","61.12.91.218/32"]
  #    # self        = true
  #   }
  #   egress_all = {
  #     description      = "Node all egress"
  #     protocol         = "-1"
  #     from_port        = 0
  #     to_port          = 0
  #     type             = "egress"
  #     cidr_blocks      = ["0.0.0.0/0"]
  #     ipv6_cidr_blocks = ["::/0"]
  #   }
  # }

  cluster_endpoint_private_access = try(local.eks_cluster.cluster_endpoint_private_access, false)
  cluster_endpoint_public_access  = try(local.eks_cluster.cluster_endpoint_public_access, true)

  vpc_id     = "vpc-082272666d7f0d9ef"
  subnet_ids = ["subnet-069a7eaf5038896cf", "subnet-0ef3c7887a6f02a22", "subnet-00b925738581e59a0"]

  # Self managed node groups will not automatically create the aws-auth configmap so we need to
  create_aws_auth_configmap = true
  manage_aws_auth_configmap = true
  create                    = true

  #Cluster Level Addons
  cluster_addons = local.eks_cluster.addons

  self_managed_node_group_defaults = {
    instance_type                          = "${local.eks_cluster.instance_type}"
    update_launch_template_default_version = true
    iam_role_additional_policies = [
      "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    ]
  }

  self_managed_node_groups = {
    # Default node group - as provisioned by the module defaults
    default_node_group = {
      name = local.eks_cluster.name
    }

    mixed = {
      name = local.eks_cluster.name
      min_size     = try(local.eks_cluster.min_size, 2)
      max_size     = try(local.eks_cluster.max_size, 4)
      desired_size = try(local.eks_cluster.min_size, 2)
      # create_security_group          = true
      # security_group_name            = "self-managed-node-group-complete-example"
      # security_group_use_name_prefix = true
      # security_group_description     = "Self managed node group complete example security group"
      # security_group_rules = {
      #   phoneOut = {
      #     description = "Hello CloudFlare"
      #     protocol    = "TCP"
      #     from_port   = 0
      #     to_port     = 65535
      #     type        = "ingress"
      #     cidr_blocks = ["172.31.0.0/16","61.12.91.218/32"]
      #     source_cluster_security_group = true
      #   }
      #   phoneHome = {
      #     description                   = "Hello cluster"
      #     protocol                      = "tcp"
      #     from_port                     = 0
      #     to_port                       = 65535
      #     type                          = "egress"
      #     cidr_blocks = ["0.0.0.0/0"]
      #     source_cluster_security_group = true # bit of reflection lookup
      #   }
      # }

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
  source = "../modules/terraform-aws-eks-cluster-autoscaler"
  enabled = true
  cluster_name                     = module.eks_cluster.cluster_id
  cluster_identity_oidc_issuer     = module.eks_cluster.cluster_oidc_issuer_url
  cluster_identity_oidc_issuer_arn = module.eks_cluster.oidc_provider_arn
  aws_region                       = "us-west-2"
}

module "node_termination_handler" {
  #source = "git::https://github.com/DNXLabs/terraform-aws-eks-node-termination-handler.git"
  source = "../modules/terraform-aws-eks-node-termination-handler"
}