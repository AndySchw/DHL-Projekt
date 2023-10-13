

terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}


############################# - Lambda - ##################################

resource "aws_lambda_function" "get_driver" {
  function_name = "getdriverlambda"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.lambda_handler" 
  runtime       = "python3.9"  

  environment {
    variables = {
      QUEUE_URL = aws_sqs_queue.sqs_verteiler.url
    }
  }
  
  filename = "./getdriver/index.zip"

  
}

resource "aws_lambda_event_source_mapping" "dynamodb_event_source" {
  event_source_arn = aws_dynamodb_table.OrderDB.stream_arn
  function_name = aws_lambda_function.get_driver.arn
  starting_position          = "LATEST"
  
  
  filter_criteria {
    filter {
      pattern = jsonencode({
        eventName = ["INSERT"],
        eventSource = ["aws:dynamodb"]
      })
    }
  }
}

resource "aws_lambda_event_source_mapping" "sqs_event_source" {
  event_source_arn = aws_sqs_queue.sqs_verteiler.arn
  function_name    = aws_lambda_function.fahrer_lambda.function_name
  batch_size       = 1  # Adjust based on your use case
}

resource "aws_lambda_function" "orderput" {
  function_name = "orderlambda"
  role          = aws_iam_role.lambda_role.arn
  handler       = "orderlambda.lambda_handler" 
  runtime       = "python3.9"  

  filename = "./python/orderlambda.zip"

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.OrderDB.name
    }
  }
}


resource "aws_lambda_function" "fahrer_lambda" {
  function_name = "fahrer_lambda"
  role          = aws_iam_role.lambda_role.arn
  handler       = "filter.lambda_handler" 
  runtime       = "python3.9"  
  timeout = 25
  

  filename = "./filter/filter.zip"

  environment {
    variables = {
      QUEUE_URL         = aws_sqs_queue.sqs_verteiler.url
      FAHRER_TABLE_NAME = aws_dynamodb_table.Fahrer.name
      # Weitere Umgebungsvariablen hier hinzufügen, wenn nötig
    }
  }
}



############################ CloudWatch ############################

resource "aws_cloudwatch_log_group" "cloudtrail_log" {
  name              = "/aws/cloudtrail/logs"
  retention_in_days = 14
}



############################ DynamoDB ############################

resource "aws_dynamodb_table" "OrderDB" {
  name           = "Orders"
  hash_key = "packageID"
  read_capacity = 1
  write_capacity = 1

  #stream aktivieren
  stream_view_type = "NEW_IMAGE"
  stream_enabled   = true

  attribute {
    name = "packageID"
    type = "S"
  }
}

resource "aws_dynamodb_table" "Fahrer" {
  name           = "Fahrer"
  hash_key = "fahrerID"
  read_capacity = 1
  write_capacity = 1

  #stream aktivieren
  stream_view_type = "NEW_IMAGE"
  stream_enabled   = true

  attribute {
    name = "fahrerID"
    type = "S"
  }
}

#######################-   Dynamo Fahrer füllen    -############################

variable "regions" {
  default = ["Würzburg", "Hannover", "Leipzig", "Hamburg", "Berlin"]
}

variable "paketzentrums" {
  default = ["PZ1", "PZ4", "PZ2", "PZ6", "PZ9"]
}

variable "statuses" {
  default = ["frei", "belegt"]
}

resource "random_id" "fahrer_id" {
  count = 15
  byte_length = 8
}

resource "random_string" "name" {
  count = 15
  length  = 10
  special = false
  upper   = false
}

resource "aws_dynamodb_table_item" "drivers" {
  count = 15
  depends_on = [ aws_dynamodb_table.Fahrer ]

  table_name = aws_dynamodb_table.Fahrer.name
  hash_key   = aws_dynamodb_table.Fahrer.hash_key

  item = jsonencode({
    fahrerID  = { S = random_id.fahrer_id[count.index].hex }
    name      = { S = random_string.name[count.index].result }
    region    = { S = element(var.regions, count.index % length(var.regions)) }
    pz        = { S = element(var.paketzentrums, count.index % length(var.paketzentrums)) }
    status    = { S = element(var.statuses, count.index % length(var.statuses)) }
    paketID   = { NULL = true }
    email     = { S = "andy.emich@docc.techstarter.de" }
    timestamp = { S = "${timestamp()}" }
  })
}



#######################-   SQS FIFO    -############################

resource "aws_sqs_queue" "sqs_verteiler" {
  name                      = "sqs_verteiler.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  # redrive_policy = jsonencode({
  #   deadLetterTargetArn = aws_sqs_queue.deadletter.arn
  #   maxReceiveCount     = 4
  # })
}


resource "aws_sqs_queue" "deadletter" {
  name = "deadletter.fifo"
  fifo_queue = true
  # redrive_allow_policy = jsonencode({
  #   redrivePermission = "byQueue",
  #   sourceQueueArns   = [aws_sqs_queue.sqs_verteiler.arn]
  # })
}


#################### - IAM - ################################

# Berechtigt Lambda an SQS und DynamoDB
resource "aws_iam_role" "lambda_role" {
  name = "lambda-fullaccess-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda-fullaccess-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sqs:*",
        Effect = "Allow",
        Resource = "*"
      },
      {
        Action = "dynamodb:*",
        Effect = "Allow",
        Resource = "*"
      },
      {
        Action = "ses:*",
        Effect = "Allow",
        Resource = "*"
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect = "Allow",
        Resource = "*"
      }
    ]
  })
}

