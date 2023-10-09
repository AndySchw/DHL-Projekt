import json
import boto3
import os

sqs = boto3.client('sqs')
queue_url = os.environ['QUEUE_URL']

def lambda_handler(event, context):
    message_body = {
        'key1': 'value1',
        'key2': 'value2',
    }
    
    try:
        sqs.send_message(
            QueueUrl=queue_url,
            MessageBody=json.dumps(message_body),
            MessageGroupId='packageID',  # Replace with an appropriate value for your use case
        )
    except Exception as e:
        print(f"Error sending message to SQS: {str(e)}")
    
    return {"statusCode": 200, "body": "Processed records"}
