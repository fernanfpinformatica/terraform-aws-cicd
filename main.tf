data "aws_caller_identity" "default" {}

data "aws_region" "default" {}

# Define composite variables for resources
module "label" {
  source     = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.3.1"
  namespace  = "${var.namespace}"
  name       = "${var.name}"
  stage      = "${var.stage}"
  delimiter  = "${var.delimiter}"
  attributes = "${var.attributes}"
  tags       = "${var.tags}"
}

module "kms_key" {
  source                  = "git::https://github.com/cloudposse/terraform-aws-kms-key.git?ref=master"
  namespace               = "${var.namespace}"
  stage                   = "${var.stage}"
  name                    = "codepipeline"
  description             = "KMS key for CodePipeline"
}

resource "aws_s3_bucket" "default" {
  bucket = "${module.label.id}"
  acl    = "private"
  tags   = "${module.label.tags}"
}

resource "aws_s3_bucket_policy" "default" {
  bucket = "${aws_s3_bucket.default.id}"

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Id": "list",
  "Statement": [
    {
        "Sid": "",
        "Effect": "Allow",
        "Principal": {
            "AWS": "arn:aws:iam::${var.code_commit_account_id}:root"
        },
        "Action": "s3:ListBucket",
        "Resource": "arn:aws:s3:::${aws_s3_bucket.default.id}"
    },{
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
          "AWS": "arn:aws:iam::${var.code_commit_account_id}:root"
      },
      "Action": [
          "s3:Get*",
          "s3:Put*"
      ],
      "Resource": "arn:aws:s3:::${aws_s3_bucket.default.id}/*"
    }
  ]
}
POLICY
}

resource "aws_iam_role" "default" {
  name               = "${module.label.id}"
  assume_role_policy = "${data.aws_iam_policy_document.assume.json}"
}

data "aws_iam_policy_document" "assume" {
  statement {
    sid = ""

    actions = [
      "sts:AssumeRole",
    ]

    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }

    effect = "Allow"
  }
}

resource "aws_iam_role_policy_attachment" "default" {
  role       = "${aws_iam_role.default.id}"
  policy_arn = "${aws_iam_policy.default.arn}"
}

resource "aws_iam_policy" "default" {
  name   = "${module.label.id}"
  policy = "${data.aws_iam_policy_document.default.json}"
}

data "aws_iam_policy_document" "default" {
  statement {
    sid = ""

    actions = [
      "elasticbeanstalk:*",
      "ec2:*",
      "elasticloadbalancing:*",
      "autoscaling:*",
      "cloudwatch:*",
      "s3:*",
      "sns:*",
      "cloudformation:*",
      "rds:*",
      "sqs:*",
      "ecs:*",
      "iam:PassRole",
      "logs:PutRetentionPolicy",
    ]

    resources = ["*"]
    effect    = "Allow"
  }
}

resource "aws_iam_role_policy_attachment" "s3" {
  role       = "${aws_iam_role.default.id}"
  policy_arn = "${aws_iam_policy.s3.arn}"
}

resource "aws_iam_policy" "s3" {
  name   = "${module.label.id}-s3"
  policy = "${data.aws_iam_policy_document.s3.json}"
}

data "aws_iam_policy_document" "s3" {
  statement {
    sid = ""

    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetBucketVersioning",
      "s3:PutObject",
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]

    resources = [
      "${aws_s3_bucket.default.arn}",
      "${aws_s3_bucket.default.arn}/*",
      "arn:aws:s3:::elasticbeanstalk*",
    ]

    effect = "Allow"
  }
}

resource "aws_iam_role_policy_attachment" "s3_kms" {
  role       = "${aws_iam_role.default.id}"
  policy_arn = "${aws_iam_policy.s3_kms.arn}"
}

resource "aws_iam_policy" "s3_kms" {
  name   = "${module.label.id}-s3-kms"
  policy = "${data.aws_iam_policy_document.s3_kms.json}"
}

data "aws_iam_policy_document" "s3_kms" {
  statement {
    sid = ""

    actions = [
      "kms:*"
    ]

    resources = [
      "${module.kms_key.key_arn}"
    ]

    effect = "Allow"
  }
}

resource "aws_iam_role_policy_attachment" "cross_account_code_commit" {
  role       = "${aws_iam_role.default.id}"
  policy_arn = "${aws_iam_policy.cross_account_code_commit.arn}"
}

resource "aws_iam_policy" "cross_account_code_commit" {
  name   = "${module.label.id}-code-commit"
  policy = "${data.aws_iam_policy_document.cross_account_code_commit.json}"
}

data "aws_iam_policy_document" "cross_account_code_commit" {
  statement {
    sid = ""

    actions = [
      "sts:AssumeRole"
    ]

    resources = [
      "arn:aws:iam::${var.code_commit_account_id}:role/*",
    ]

    effect = "Allow"
  }
}

resource "aws_iam_role_policy_attachment" "codebuild" {
  role       = "${aws_iam_role.default.id}"
  policy_arn = "${aws_iam_policy.codebuild.arn}"
}

resource "aws_iam_policy" "codebuild" {
  name   = "${module.label.id}-codebuild"
  policy = "${data.aws_iam_policy_document.codebuild.json}"
}

data "aws_iam_policy_document" "codebuild" {
  statement {
    sid = ""

    actions = [
      "codebuild:*",
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]

    resources = ["${module.build.project_id}"]
    effect    = "Allow"
  }
}

module "build" {
  source                = "git::https://github.com/cloudposse/terraform-aws-codebuild.git?ref=tags/0.9.0"
  namespace             = "${var.namespace}"
  name                  = "${var.name}"
  stage                 = "${var.stage}"
  build_image           = "${var.build_image}"
  build_compute_type    = "${var.build_compute_type}"
  buildspec             = "${var.buildspec}"
  delimiter             = "${var.delimiter}"
  attributes            = "${concat(var.attributes, list("build"))}"
  tags                  = "${var.tags}"
  privileged_mode       = "${var.privileged_mode}"
  aws_region            = "${signum(length(var.aws_region)) == 1 ? var.aws_region : data.aws_region.default.name}"
  aws_account_id        = "${signum(length(var.aws_account_id)) == 1 ? var.aws_account_id : data.aws_caller_identity.default.account_id}"
  image_repo_name       = "${var.image_repo_name}"
  image_tag             = "${var.image_tag}"
  environment_variables = "${var.environment_variables}"
}

resource "aws_iam_role_policy_attachment" "codebuild_s3" {
  role       = "${module.build.role_arn}"
  policy_arn = "${aws_iam_policy.s3.arn}"
}

# Only one of the `aws_codepipeline` resources below will be created:

# "source_build_deploy" will be created if `var.enabled` is set to `true` and the Elastic Beanstalk application name and environment name are specified

# This is used in two use-cases:

# 1. GitHub -> S3 -> Elastic Beanstalk (running application stack like Node, Go, Java, IIS, Python)

# 2. GitHub -> ECR (Docker image) -> Elastic Beanstalk (running Docker stack)

# "source_build" will be created if `var.enabled` is set to `true` and the Elastic Beanstalk application name or environment name are not specified

# This is used in this use-case:

# 1. GitHub -> ECR (Docker image)

resource "aws_codepipeline" "source_build_deploy" {
  # Elastic Beanstalk application name and environment name are specified
  count    = "${var.enabled && signum(length(var.app)) == 1 && signum(length(var.env)) == 1 ? 1 : 0}"
  name     = "${module.label.id}"
  role_arn = "${aws_iam_role.default.arn}"

  artifact_store {
    location = "${aws_s3_bucket.default.bucket}"
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["code"]

      role_arn = "arn:aws:iam::${var.code_commit_account_id}:role/${var.cross_account_assume_role}"

      configuration {
        RepositoryName = "${var.repo_name}"
        BranchName     = "${var.branch}"
        PollForSourceChanges = "${var.poll_source_changes}"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name     = "Build"
      category = "Build"
      owner    = "AWS"
      provider = "CodeBuild"
      version  = "1"

      input_artifacts  = ["code"]
      output_artifacts = ["package"]

      configuration {
        ProjectName = "${module.build.project_name}"
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ElasticBeanstalk"
      input_artifacts = ["package"]
      version         = "1"

      configuration {
        ApplicationName = "${var.app}"
        EnvironmentName = "${var.env}"
      }
    }
  }
}

resource "aws_codepipeline" "source_build" {
  # Elastic Beanstalk application name or environment name are not specified
  count    = "${var.enabled && (signum(length(var.app)) == 0 || signum(length(var.env)) == 0) ? 1 : 0}"
  name     = "${module.label.id}"
  role_arn = "${aws_iam_role.default.arn}"

  artifact_store {
    location = "${aws_s3_bucket.default.bucket}"
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["code"]

      role_arn = "arn:aws:iam::${var.code_commit_account_id}:role/${var.cross_account_assume_role}"

      configuration {
        RepositoryName = "${var.repo_name}"
        BranchName     = "${var.branch}"
        PollForSourceChanges = "${var.poll_source_changes}"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name     = "Build"
      category = "Build"
      owner    = "AWS"
      provider = "CodeBuild"
      version  = "1"

      input_artifacts  = ["code"]
      output_artifacts = ["package"]

      configuration {
        ProjectName = "${module.build.project_name}"
      }
    }
  }
}
