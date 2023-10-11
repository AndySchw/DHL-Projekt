import boto3
import json
import os
from botocore.exceptions import ClientError
from boto3.dynamodb.conditions import Attr


# AWS services clients
sqs = boto3.client('sqs')
dynamodb = boto3.resource('dynamodb')
ses = boto3.client('ses')

# Your resources ARNs or names
QUEUE_URL = os.environ['QUEUE_URL']
FAHRER_TABLE_NAME = 'Fahrer'
BESTELLUNGEN_TABLE_NAME = 'OrderDB'

def lambda_handler(event, context):
    # 3. LAMBDA fragt Queue an
    messages = sqs.receive_message(
        QueueUrl=QUEUE_URL,
        MaxNumberOfMessages=1,
        WaitTimeSeconds=20  # adjust this as needed
    )
    if 'Messages' not in messages:
        print("No messages in the queue")
        return {"statusCode": 200, "body": "No messages"}

    message_body = json.loads(messages['Messages'][0]['Body'])
    receipt_handle = messages['Messages'][0]['ReceiptHandle']
    
    # Extract necessary data
    package_id = message_body.get('packageID')
    restrictions = message_body.get('restrictions')
    
    # 4. Anfrage an DynamoDB (Table Fahrer) ob ein Fahrer verfügbar ist
    fahrer_table = dynamodb.Table(FAHRER_TABLE_NAME)
    bestellungen_table = dynamodb.Table(BESTELLUNGEN_TABLE_NAME)

    # Assuming that your table has a 'status' attribute and a primary key 'fahrerID'
    available_fahrer = fahrer_table.scan(
        FilterExpression=Attr('status').eq('frei')
    )['Items']
    
    if not available_fahrer:
        print("No available drivers")
        return {"statusCode": 200, "body": "No available drivers"}
    
    chosen_fahrer = available_fahrer[0]  # select the first available driver
    
    # 5. LAMBDA passt DynamoDB (Table Fahrer) den Status des gewählten Fahrers an ( nicht belegt)
    fahrer_table.update_item(
        Key={'fahrerID': chosen_fahrer['fahrerID']},
        UpdateExpression='SET status = :status, current_package = :package_id',
        ExpressionAttributeValues={
            ':status': 'belegt',
            ':package_id': package_id
        }
    )


    bestellungen_table.update_item(
        Key={'packageID': package_id},
        UpdateExpression='SET lieferstatus = :lieferstatus',
        ExpressionAttributeValues={
            ':lieferstatus': 'zugewiesen',  # or whatever status you'd like to set
        }
    )


    # 6. LAMBDA Infos an SES weiterreichen um EMAIL zu versenden Fahrer_Email, Paket_ID, DynamoDB Table ITEM Werte in formatierte Variante
    EMAIL_TEXT = f"""
    Hallo {chosen_fahrer['name']}#{chosen_fahrer['fahrerID']},
    dein Paket hat die ID {package_id}#.
    Das Paket soll an Adresse 123.
    Weitere Infos {restrictions} !!!!!!!
    """

    try:
        ses.send_email(
            Source='andy.emich@docc.techstarter.de',
            Destination={
                'ToAddresses': [chosen_fahrer['email']],
            },
            Message={
                'Subject': {'Data': 'Neues Paket'},
                'Body': {'Text': {'Data': EMAIL_TEXT}},
            }
        )
        print(f"Email sent to {chosen_fahrer['email']}")
    except ClientError as e:
        print(f"Error sending email: {str(e)}")
    
    return {"statusCode": 200, "body": "Processed successfully"}
