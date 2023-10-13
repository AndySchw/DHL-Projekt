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
BESTELLUNGEN_TABLE_NAME = 'Orders'

def lambda_handler(event, context):
    # Ausdrucken des gesamten Events
    print("Received event:", json.dumps(event))
    
    # Extrahieren der Nachricht aus dem Event
    message_body_str = event['Records'][0]['body']
    message_body = json.loads(message_body_str)
    
    # Extract necessary data from the message body
    package_id = message_body.get('packageID')
    restrictions = message_body.get('restrictions')

    # Anfrage an DynamoDB (Table Fahrer) ob ein Fahrer verfügbar ist
    fahrer_table = dynamodb.Table(FAHRER_TABLE_NAME)
    bestellungen_table = dynamodb.Table(BESTELLUNGEN_TABLE_NAME)

    # Assuming your table has a 'status' attribute and a primary key 'fahrerID'
    available_fahrer = fahrer_table.scan(
        FilterExpression=Attr('status').eq('frei')
    )['Items']
    
    if not available_fahrer:
        print("No available drivers")
        return {"statusCode": 200, "body": "No available drivers"}

    chosen_fahrer = available_fahrer[0]  # select the first available driver
    
    # LAMBDA passt DynamoDB (Table Fahrer) den Status des gewählten Fahrers an (nicht belegt)
    fahrer_table.update_item(
        Key={'fahrerID': chosen_fahrer['fahrerID']},
        UpdateExpression='SET #status = :status, current_package = :package_id',
        ExpressionAttributeNames={
            '#status': 'status',
        },
        ExpressionAttributeValues={
            ':status': 'belegt',
            ':package_id': package_id
        }
    )

    bestellungen_table.update_item(
        Key={'packageID': package_id},
        UpdateExpression='SET lieferstatus = :lieferstatus',
        ExpressionAttributeValues={
            ':lieferstatus': 'zugewiesen',
        }
    )

    # LAMBDA Infos an SES weiterreichen um EMAIL zu versenden
    EMAIL_TEXT = f"""
    Hallo {chosen_fahrer['name']}#{chosen_fahrer['fahrerID']},
    dein Paket hat die ID {package_id}#.
    Das Paket soll an Adresse 123.
    Weitere Infos {restrictions} !!!!!!!
    """

    try:
        response = ses.send_email(
            Source='andy.emich@docc.techstarter.de',
            Destination={
                'ToAddresses': [chosen_fahrer['email']],
            },
            Message={
                'Subject': {'Data': 'Neues Paket'},
                'Body': {'Text': {'Data': EMAIL_TEXT}},
            }
        )
        print(f"SES response: {response}")
    except ClientError as e:
        print(f"Error sending email: {str(e)}")
    
    return {"statusCode": 200, "body": "Processed successfully"}
