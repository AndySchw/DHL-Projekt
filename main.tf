

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


####################### HTTP API Gateway und die Lambda dafür ########################

# # Erstellt eine Lambda-Funktion mit der Ressource "aws_lambda_function"
# resource "aws_lambda_function" "example" {
#   function_name = "example_lambda"  # Der Name der Lambda-Funktion
#   handler       = "apilambda.lambda_handler"  # Der Handler der Lambda-Funktion
#   runtime       = "python3.9"  # Die Laufzeitumgebung für die Lambda-Funktion

#   filename = "./api/apilambda.zip"  # Der Pfad zur ZIP-Datei, die den Code der Lambda-Funktion enthält

#   role          = aws_iam_role.lambda_exec_role.arn  # Die IAM-Rolle, die der Lambda-Funktion zugewiesen wird
# }

# Erstellt eine API Gateway mit der Ressource "aws_apigatewayv2_api"
resource "aws_apigatewayv2_api" "apigate" {
  name          = "API-Gateway-Input"  # Der Name der API Gateway
  protocol_type = "HTTP" # Der Protokolltyp der API Gateway
  cors_configuration {
    allow_origins = ["http://*"]
    allow_methods = ["POST", "GET", "DELETE", "*"]
    allow_headers = ["content-type"]
    max_age = 300
  }
}

# Erstellt eine Route für die API Gateway mit der Ressource "aws_apigatewayv2_route"
resource "aws_apigatewayv2_route" "apirout" {
  api_id    = aws_apigatewayv2_api.apigate.id  # Die ID der API Gateway, zu der die Route gehört
  route_key = "ANY /datain"  # Der Schlüssel der Route (Methode und Pfad)
  target    = "integrations/${aws_apigatewayv2_integration.apiint.id}"  # Das Ziel der Route (in diesem Fall eine Integration)
}

# Erstellt eine Integration zwischen der API Gateway und der Lambda-Funktion mit der Ressource "aws_apigatewayv2_integration"
resource "aws_apigatewayv2_integration" "apiint" {
  api_id           = aws_apigatewayv2_api.apigate.id  # Die ID der API Gateway, zu der die Integration gehört
  integration_type = "AWS_PROXY"  # Der Typ der Integration

  connection_type      = "INTERNET"  # Der Verbindungstyp der Integration
  description          = "Lambda integration"  # Die Beschreibung der Integration
  integration_method   = "POST"  # Die Methode, die für die Integration verwendet wird
  integration_uri      = aws_lambda_function.orderput.invoke_arn  # Die URI, die aufgerufen wird, wenn die Integration ausgelöst wird
}

# Erstellt eine Stufe für die API Gateway mit der Ressource "aws_apigatewayv2_stage"
resource "aws_apigatewayv2_stage" "apistage" {
  api_id      = aws_apigatewayv2_api.apigate.id  # Die ID der API Gateway, zu der die Stufe gehört
  name        = "$default"  # Der Name der Stufe
  auto_deploy = true  # Gibt an, ob Änderungen an dieser Stufe automatisch bereitgestellt werden sollen
}

# Erstellung eines HTTP API-Gateway mit Lambda integration: in eu-central-1 Lamda-Funktion?...., Version 2.0 und API-Name: API-Gateway-Input, 
# und einer Routen konfiguration: Methode: post, Ressourcenpfad:?, Integrationsziel:? (Lambda für die API), Stufen konfiguration: Stufenname: $default,

# Erstellt eine Berechtigung für die Lambda-Funktion
resource "aws_lambda_permission" "apigw" {
  # Eindeutige ID für die Berechtigungserklärung
  statement_id  = "AllowExecutionFromAPIGateway"
  
  # Die Aktion, die die API Gateway auf die Lambda-Funktion ausführen darf
  action        = "lambda:InvokeFunction"
  
  # Der Name der Lambda-Funktion, auf die sich die Berechtigung bezieht
  function_name = aws_lambda_function.orderput.function_name
  
  # Der AWS-Service (in diesem Fall API Gateway), der die Berechtigung erhält
  principal     = "apigateway.amazonaws.com"

  # Die ARN der API Gateway, die die Berechtigung erhält, um die Lambda-Funktion auszulösen
  source_arn = "${aws_apigatewayv2_api.apigate.execution_arn}/*/*"
}

