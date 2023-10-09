import json
import boto3
import os

sqs = boto3.client('sqs')
queue_url = os.environ['QUEUE_URL']

def lambda_handler(event, context):
    print("Received event:", json.dumps(event))
    
    # Iterate through each record in the event
    for record in event['Records']:
        # Ensure the record type is INSERT (you might also handle MODIFY, etc.)
        if record['eventName'] == 'INSERT':
            new_image = record['dynamodb']['NewImage']
            
            # Extract the desired fields
            packageID = new_image['packageID']['S']
            restrictions = new_image['restrictions']['S']
            recipient_address = new_image['recipient_address']['S']
            recipient_name = new_image['recipient_name']['S']
            
            # Construct the message body
            message_body = {
                'packageID': packageID,
                'restrictions': restrictions,
                'recipient_address': recipient_address,
                'recipient_name': recipient_name
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
