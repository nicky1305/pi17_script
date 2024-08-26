import paho.mqtt.client as mqtt
import subprocess
import logging
import time

# Setup logging
logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)

# MQTT broker details
brokerHost = '62ec6dd8f0ff40b9ac95cf29d316d06e.s1.eu.hivemq.cloud'
brokerPort = 8883
brokerUsername = 'annguyen'
brokerPassword = 'Khanhan666'
publishTopic = 'mqtt/executescript'
statustopic = 'mqtt/status'

# Define the callback function for when a message is received
def on_message(client, userdata, message):
    msg = message.payload.decode('utf-8')
    logger.info(f"Received message: {msg} on topic: {message.topic}")

    try:
        # Execute the corresponding script based on the message
        if msg == "ping_domain":
            subprocess.run(["script/pingdomain1.sh"], check=True)
        elif msg == "iptv":
            subprocess.run(["script/iptv.sh"], check=True)
        elif msg == "speedtest":
            subprocess.run(["script/speedtest.sh"], check=True)
        elif msg == "fulltest":
            subprocess.run(["script/fulltest.sh"], check=True)
    except subprocess.CalledProcessError as e:
        logger.error(f"Error executing script: {e}")

# Define the callback function for when the client connects to the broker
def on_connect(client, userdata, flags, rc):
    logger.info(f"Connected with result code {rc}")
    client.subscribe(publishTopic)

# Define the callback function for when the client encounters an error
def on_log(client, userdata, level, buf):
    logger.debug(f"Log: {buf}")

# Define the publish  ON Status to Broker
def on_status(client, statustopic):
    client.publish(topic, "ON")
    logger.info("Send ON Topic successfully")
    time.sleep(5)

# Create a new MQTT client instance
client = mqtt.Client()

# Set username and password for the broker
client.username_pw_set(brokerUsername, brokerPassword)

# Set the TLS/SSL settings (required for port 8883)
client.tls_set() 

# Set callback functions
client.on_message = on_message
client.on_connect = on_connect
client.on_log = on_log
client.on_status = on_status

try:
    # Connect to the MQTT broker
    client.connect(brokerHost, brokerPort)
except Exception as e:
    logger.error(f"Failed to connect to broker: {e}")
    exit(1)

# Start the MQTT client loop
try:
    client.loop_forever()
except KeyboardInterrupt:
    logger.info("Interrupted by user, stopping...")
except Exception as e:
    logger.error(f"Error in loop: {e}")
finally:
    client.disconnect()
