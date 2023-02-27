data "aws_caller_identity" "current" {}

locals {
  eks_cluster = {
    is_enable = true
    min_size                 = 3
    max_size                 = 4
    desired_size             = 3
    name                     = "eks-merging-test"
    environment_name         = "dev"
    version                  = "1.24"
    is_mixed_instance_policy = true
    vpc_id                   = "vpc-0cdbbbd4cedcea769"
    vpc_cidr                 = ["172.31.0.0/16"]
    subnet_ids               = ["subnet-0257e8262a7017948", "subnet-062a9cb5ea10455da", "subnet-06b6a7e3c22de35ca"]
    instance_type            = "t3a.medium"
    instances_distribution = {
      on_demand_base_capacity                  = 0
      on_demand_percentage_above_base_capacity = 20
      spot_allocation_strategy                 = "capacity-optimized"
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
    cluster_security_group = {
      cluster_rule_ingress = {
        description = "cluster SG"
        protocol    = "tcp"
        from_port   = 0
        to_port     = 65535
        type        = "ingress"
        cidr_blocks = ["0.0.0.0/0"]
      },
      cluster_rule_egress = {
        description = "cluster SG"
        protocol    = "tcp"
        from_port   = 0
        to_port     = 65535
        type        = "egress"
        cidr_blocks = ["0.0.0.0/0"]
      }
    }
    node_security_group = {
      node_rules_ingress = {
        description = "node SG"
        protocol    = "TCP"
        from_port   = 0
        to_port     = 65535
        type        = "ingress"
        cidr_blocks = ["0.0.0.0/0"]
      }
      node_rules_egress = {
        description = "node SG"
        protocol    = "tcp"
        from_port   = 0
        to_port     = 65535
        type        = "egress"
        cidr_blocks = ["0.0.0.0/0"]
      }
    }
    #aws eks describe-addon-version
    addons = {
      vpc-cni = {
        resolve_conflicts = "OVERWRITE"
      },
      # aws-ebs-csi-driver = {
      #   resolve_conflicts = "OVERWRITE"
      # },
      kube-proxy = {
        resolve_conflicts = "OVERWRITE"
      }
    }
    lb = {
      image = {
        repository = "public.ecr.aws/eks/aws-load-balancer-controller"
        tag        = "v2.4.6"
      }
    }
  }
}


module "eks_cluster" {
  source          = "../"
  cluster_name    = local.eks_cluster.name
  cluster_version = try(local.eks_cluster.version, "1.24")
  # count = local.eks_cluster.is_enable == true ? 1 : 0
  create_cluster_autoscaler = true
  create_node_termination_handler = true
  
  cluster_endpoint_private_access = try(local.eks_cluster.cluster_endpoint_private_access, false)
  cluster_endpoint_public_access  = try(local.eks_cluster.cluster_endpoint_public_access, true)

  vpc_id     = local.eks_cluster.vpc_id
  subnet_ids = local.eks_cluster.subnet_ids

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
  cluster_security_group_additional_rules = local.eks_cluster.cluster_security_group
  self_managed_node_groups = {
    # Default node group - as provisioned by the module defaults
    default_node_group = {
      name = local.eks_cluster.name
    }
    mixed = {
      name         = local.eks_cluster.name
      min_size     = try(local.eks_cluster.min_size, 2)
      max_size     = try(local.eks_cluster.max_size, 4)
      desired_size = try(local.eks_cluster.min_size, 2)
      tags = {
        "k8s.io/cluster-autoscaler/enabled"                   = "true"
        "k8s.io/cluster-autoscaler/${local.eks_cluster.name}" = "owned"
      }
      create_security_group          = true
      security_group_name            = local.eks_cluster.name
      security_group_use_name_prefix = true
      security_group_description     = "Self managed NodeGroup SG"
      security_group_rules           = local.eks_cluster.node_security_group

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

      block_device_mappings      = "${local.eks_cluster.block_device_mappings}"
      use_mixed_instances_policy = "${local.eks_cluster.is_mixed_instance_policy}"
      mixed_instances_policy = {
        instances_distribution = "${local.eks_cluster.instances_distribution}"
        override               = "${local.eks_cluster.override}"
      }
    }
  }
}