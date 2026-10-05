#!/bin/bash
docker cp chat_client.py container-a:/root/chat_client.py
docker exec -it container-a python3 /root/chat_client.py
