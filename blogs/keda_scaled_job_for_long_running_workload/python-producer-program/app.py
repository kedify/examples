import pika
import json
import os

def main():
    # Get the count from environment variable
    count = int(os.getenv('MESSAGE_COUNT', 1))

    rabbitmq_url = os.getenv('RABBITMQ_URL', 'amqp://default_user_hmGZFhdewq65P4dIdx7:qc98n4iGD7MYXMBVFcIO2mtB5voDuV_n@localhost:5672')
    params = pika.URLParameters(rabbitmq_url)
    connection = pika.BlockingConnection(params)
    channel = connection.channel()

    # Declare the queue
    channel.queue_declare(queue='testqueue', durable=True)

    # Declare the exchange
    channel.exchange_declare(exchange='topic_exchange', exchange_type='topic')

    # Add binding between the exchange and queue
    channel.queue_bind(exchange='topic_exchange', queue='testqueue', routing_key='orders.#')

    # Publish messages
    for order_id in range(1, count + 1):
        message = json.dumps({"order_id": str(order_id), "status": "processed"})
        channel.basic_publish(exchange='topic_exchange', routing_key='orders.processed', body=message)
        print(f"Sent {message}")

    connection.close()

if __name__ == "__main__":
    main()
