import boto3
import json
import string
import random
import time
from datetime import date

# Initialize the DynamoDB resource
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('Orders')  # Ersetzen Sie 'Orders' durch den Namen Ihrer Tabelle

def random_string(length):
    """Generiert einen zufälligen String der festen Länge."""
    letters = string.ascii_letters + string.digits + " "
    return ''.join(random.choice(letters) for i in range(length))

def random_phone():
    """Generiert eine zufällige Telefonnummer."""
    return ''.join(random.choice(string.digits) for i in range(10))

def generate_packageID():
    """Generiert eine eindeutige packageID."""
    timestamp = int(time.time() * 1000)  # Aktuelle Zeit in Millisekunden
    random_digits = ''.join(random.choice(string.digits) for i in range(4))
    return f"FP{timestamp}{random_digits}"

def lambda_handler(event, context):
    try:
        # Daten aus dem API-Gateway-Ereignis abrufen
        body = json.loads(event['body'])
        
        # Daten aus dem Formular in das item-Datenobjekt einfügen
        item = {
            "recipient_name": body['recipient_name'],
            "recipient_address": body['recipient_address'],
            "recipient_phone": body['recipient_phone'],
            "sender_name": body['sender_name'],
            "sender_address": body['sender_address'],
            "sender_phone": body['sender_phone'],
            "dimensions_length": int(body['dimensions_length']),
            "dimensions_width": int(body['dimensions_width']),
            "dimensions_height": int(body['dimensions_height']),
            "weight": float(body['weight']),
            "packageID": generate_packageID(),
            "date": body['date'],
            "insurance_type": body['insurance_type'],
            "insurance_value": float(body['insurance_value']),
            "restrictions": body['restrictions'],
            "value": float(body['value']),
            "lieferstatus": "ausstehend"
        }

        # Das item-Datenobjekt in einen JSON-String umwandeln
        item_json = json.dumps(item)

        # Eintrag in die DynamoDB-Tabelle einfügen
        response = table.put_item(Item=json.loads(item_json))

        return {
            'statusCode': 200,
            'body': json.dumps({'message': f'Erfolgreich Datensatz mit packageID {item["packageID"]} eingefügt'})
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': f'Fehler beim Einfügen des Datensatzes in DynamoDB: {str(e)}'})
        }
