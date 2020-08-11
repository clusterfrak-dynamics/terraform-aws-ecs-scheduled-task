locals {
  ecs_sfn_iam_name = "${var.name}-ecs-sfn"
  enabled_ecs_sfn  = var.enabled && var.create_ecs_sfn_role ? 1 : 0
}

data "aws_iam_policy_document" "ecs_sfn_state_machine_assume_role_policy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"

      identifiers = [
        "states.amazonaws.com",
      ]
    }
  }
}

data "aws_iam_policy_document" "ecs_sfn_state_machine_policy" {
  statement {
    effect = "Allow"
    actions = [
      "sns:Publish"
    ]
    resources = [
      var.create_sns_topic ? join("", aws_sns_topic.ecs_cfn_sns_topic.*.arn) : var.sns_topic_arn
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "iam:PassRole"
    ]
    resources = [
      var.create_ecs_task_role ? join("", aws_iam_role.ecs_task_role.*.arn) : var.ecs_task_role_arn,
      var.create_ecs_task_execution_role ? join("", aws_iam_role.ecs_task_execution.*.arn) : var.ecs_task_execution_role_arn
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "ecs:RunTask"
    ]
    resources = [
      aws_ecs_task_definition.default[0].arn
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "ecs:StopTask",
      "ecs:DescribeTasks"
    ]
    resources = [
      "*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "events:PutTargets",
      "events:PutRule",
      "events:DescribeRule"
    ]
    resources = [
      "arn:aws:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:rule/StepFunctionsGetEventsForECSTaskRule"
    ]
  }
}

resource "aws_iam_role" "ecs_sfn_state_machine" {
  count              = local.enabled_ecs_sfn
  name               = local.ecs_sfn_iam_name
  assume_role_policy = data.aws_iam_policy_document.ecs_sfn_state_machine_assume_role_policy.json
}

resource "aws_iam_policy" "ecs_sfn_state_machine" {
  count  = local.enabled_ecs_sfn
  name   = local.ecs_sfn_iam_name
  policy = data.aws_iam_policy_document.ecs_sfn_state_machine_policy.json
}

resource "aws_iam_role_policy_attachment" "ecs_sfn_state_machine" {
  count      = local.enabled_ecs_sfn
  role       = aws_iam_role.ecs_sfn_state_machine[0].name
  policy_arn = aws_iam_policy.ecs_sfn_state_machine[0].arn
}

resource "aws_sfn_state_machine" "ecs_sfn_state_machine" {
  count    = var.enabled ? 1 : 0
  name     = var.name
  role_arn = var.create_ecs_sfn_role ? aws_iam_role.ecs_sfn_state_machine[0].arn : var.ecs_sfn_role_arn

  definition = <<EOF
{
  "Comment": "An example of the Amazon States Language for notification on an AWS Fargate task completion",
  "StartAt": "Run Fargate Task",
  "TimeoutSeconds": 3600,
  "States": {
    "Run Fargate Task": {
      "Type": "Task",
      "Resource": "arn:aws:states:::ecs:runTask.sync",
      "Parameters": {
        "LaunchType": "FARGATE",
        "Cluster": "${var.cluster_arn}",
        "TaskDefinition": "${aws_ecs_task_definition.default[0].arn}",
        "PlatformVersion": "1.4.0",
        "NetworkConfiguration": {
          "AwsvpcConfiguration": {
            "Subnets": ${jsonencode(var.subnets)},
            "SecurityGroups": ${jsonencode(local.security_groups)},
            "AssignPublicIp": "DISABLED"
          }
        }
      },
      "Next": "Notify Success",
      "Catch": [
          {
            "ErrorEquals": [ "States.ALL" ],
            "Next": "Notify Failure"
          }
      ]
    },
    "Notify Success": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sns:publish",
      "Parameters": {
        "Message": "AWS Fargate Task started by Step Functions succeeded",
        "TopicArn": "${var.create_sns_topic ? join("", aws_sns_topic.ecs_cfn_sns_topic.*.arn) : var.sns_topic_arn}"
      },
      "End": true
    },
    "Notify Failure": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sns:publish",
      "Parameters": {
        "Message": "AWS Fargate Task started by Step Functions failed",
        "TopicArn": "${var.create_sns_topic ? join("", aws_sns_topic.ecs_cfn_sns_topic.*.arn) : var.sns_topic_arn}"
      },
      "End": true
    }
  }
}
EOF
}
