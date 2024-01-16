import pika
import time
import requests
import os
import signal

# Declare a global variable
currentMessage = None

def send_http_kill_request():
    global currentMessage  # Correct use of global
    if currentMessage is not None:
        try:
            counter_url = os.getenv('COUNTER_KILL_URL', 'http://localhost:8080/kill/count')
            response = requests.post(counter_url)
            print("HTTP POST kill request sent. Status code:", response.status_code)
            print("App killed while processing message:", currentMessage)
        except:
            print("HTTP POST kill request failed")
            print("App killed while processing message:", currentMessage)


def send_http_request():
    try:
        counter_url = os.getenv('COUNTER_COUNT_URL', 'http://localhost:8080/create/count')
        response = requests.post(counter_url)
        print("HTTP POST request sent. Status code:", response.status_code)
    except:
        print("HTTP POST request failed")

def sigterm_handler(signum, frame):
    print("SIGTERM signal received, sending HTTP request...")
    send_http_kill_request()
    print("Shutting down gracefully...")
    os._exit(0)  # Forcefully exit the program

def callback(ch, method, properties, body):
    print("Message received, processing...")
    global currentMessage  # Correct use of global
    currentMessage = body.decode()
    print(currentMessage)
    sleep_time = os.getenv('SLEEP_TIME', '300')
    sleep_time = int(sleep_time)
    for i in range(1, sleep_time):
        print(f"Sleeping second {i}")
        time.sleep(1)

    send_http_request()

    # Acknowledge the message after processing is complete
    ch.basic_ack(delivery_tag=method.delivery_tag)
    currentMessage = None  # Unset the global variable
    print("Waiting for message...\n")

def main():
    # Register the signal handler
    signal.signal(signal.SIGTERM, sigterm_handler)

    print("Starting consumer...")   
    rabbitmq_url = os.getenv('RABBITMQ_URL', 'amqp://default_user_hmGZFhdewq65P4dIdx7:qc98n4iGD7MYXMBVFcIO2mtB5voDuV_n@localhost:5672')
    params = pika.URLParameters(rabbitmq_url)
    params.heartbeat = 300
    connection = pika.BlockingConnection(params)
    channel = connection.channel()

    # Set prefetch count to 1 to read only one message at a time
    channel.basic_qos(prefetch_count=1)

    print("Waiting for message...\n")
    # Set auto_ack to False for manual acknowledgement
    channel.basic_consume(queue='testqueue', on_message_callback=callback, auto_ack=False)

    try:
        channel.start_consuming()
    except KeyboardInterrupt:
        print("Interrupt received, shutting down...")
        send_http_kill_request()
    except Exception as e:
        print(f"Unexpected error: {e}")
    finally:
        if channel and channel.is_open:
            channel.stop_consuming()
        if connection and connection.is_open:
            connection.close()

if __name__ == "__main__":
    main()
