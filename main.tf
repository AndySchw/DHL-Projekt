provider "aws" {
  region = "eu-central-1"  
}

#############################Lambda##################################

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




############################CloudWatch############################

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "getdriver_log" {
  name              = "/aws/lambda/${aws_lambda_function.orderput.function_name}"
  retention_in_days = 14
}



############################DynamoDB############################

resource "aws_dynamodb_table" "OrderDB" {
  name           = "Orders"
  hash_key = "packageID"
  read_capacity = 20
  write_capacity = 20

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
  read_capacity = 20
  write_capacity = 20

  #stream aktivieren
  stream_view_type = "NEW_IMAGE"
  stream_enabled   = true

  attribute {
    name = "fahrerID"
    type = "S"
  }
}

#######################-   SQS FIFO    -############################

resource "aws_sqs_queue" "sqs_verteiler" {
  name                      = "sqs_verteiler.fifo"
  delay_seconds             = 90
  max_message_size          = 2048
  message_retention_seconds = 86400
  receive_wait_time_seconds = 10
  fifo_queue                  = true
  content_based_deduplication = true
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.deadletter.arn
    maxReceiveCount     = 4
  })

  tags = {
    Environment = "production"
  }
}


resource "aws_sqs_queue" "deadletter" {
  name = "deadletter.fifo"
  fifo_queue = true
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue",
    sourceQueueArns   = [aws_sqs_queue.sqs_verteiler.arn]
  })
}


####################33333- IAM -################################33

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

