
import boto3
import random
import string
import time
from datetime import date

# Initialize the DynamoDB resource
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('Orders')  # Replace 'YourTableName' with your table's name
table2 = dynamodb.Table('Fahrer')

def random_string(length):
    """Generate a random string of fixed length."""
    letters = string.ascii_letters + string.digits + " "
    return ''.join(random.choice(letters) for i in range(length))

def random_phone():
    """Generate a random phone number."""
    return ''.join(random.choice(string.digits) for i in range(10))

def generate_packageID():
    """Generate a unique packageID."""
    timestamp = int(time.time() * 1000)  # Current time in milliseconds
    random_digits = ''.join(random.choice(string.digits) for i in range(4))
    return f"FP{timestamp}{random_digits}"


################### für 2. Tabelle

def generate_fahrerID():
    """Generate a unique fahrerID."""
    timestamp = int(time.time() * 1000)  # Current time in milliseconds
    random_digits = ''.join(random.choice(string.digits) for i in range(4))
    return f"FP{timestamp}{random_digits}"

        

def random_email():
    """Generate a random email address."""
    letters = string.ascii_letters
    username = ''.join(random.choice(letters) for i in range(5))
    domain = ''.join(random.choice(letters) for i in range(3))
    return f"{username}@{domain}.com"


def random_status():
    """Generate a random status."""
    return random.choice(["frei", "belegt"])

def random_region():
    """Generate a random region."""
    return random.choice(["Würzburg", "Hannover", "Leipzig", "Hamburg", "Berlin"])


def random_paketzentrum():
    """Generate a random region."""
    return random.choice(["PZ1", "PZ4", "PZ2", "PZ6", "PZ9"])





def lambda_handler(event, context):
    try:
        # Create a random item
        item = {
            "recipient_name": random_string(10),
            "recipient_address": random_string(25),
            "recipient_phone": random_phone(),
            "sender_name": random_string(10),
            "sender_address": random_string(25),
            "sender_phone": random_phone(),
            "dimensions_length": random.randint(1, 100),
            "dimensions_width": random.randint(1, 100),
            "dimensions_height": random.randint(1, 100),
            "weight": random.randint(1, 50),
            "packageID": generate_packageID(),
            "date": str(date.today()),  # Insert today's date
            "insurance_type": random.choice(["Basic", "Premium", "Gold"]),
            "insurance_value": random.randint(1, 5000),
            "restrictions": random.choice(["Sperrgut", "Zerbrechlich", "Liquid", "Flammable"]),  # Two random restrictions
            "value": random.randint(1, 1000),
            "lieferstatus": "ausstehend"
        }

        # Insert the item into the DynamoDB table
        table.put_item(Item=item)

        ###### Tabelle 2 Fahrer
        
        for _ in range(4):
            item2 = {
                "fahrerID": generate_fahrerID(),
                "name": random_string(10),
                "region": random_region(),
                "pz": random_paketzentrum(),
                "status": random_status(),
                "paketID": None,
                # "email": random_email(),
                "email": "andy.emich@docc.techstarter.de",
                "timestamp": int(time.time() * 1000)  # Current time in milliseconds
            }

            # Insert the item into the second DynamoDB table
            table2.put_item(Item=item2)
        return {
            'statusCode': 200,
            'body': f'Successfully inserted item with packageID {item["packageID"]}'
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': f'Error inserting item into DynamoDB: {str(e)}'
        }