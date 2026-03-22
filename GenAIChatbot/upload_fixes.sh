#!/bin/bash
VM_NAME="instance-20260120-134255"
ZONE="us-central1-a"

# Upload config.py
gcloud compute scp \
    generative-ai-chatbot/config/config.py \
    ${VM_NAME}:/tmp/config.py \
    --zone=${ZONE} && \
gcloud compute ssh ${VM_NAME} --zone=${ZONE} --command="
    sudo mv /tmp/config.py /opt/chatbot/generative-ai-chatbot/config/config.py && \
    sudo chown chatbot:chatbot /opt/chatbot/generative-ai-chatbot/config/config.py && \
    sudo chmod 644 /opt/chatbot/generative-ai-chatbot/config/config.py && \
    echo 'config.py updated!'
"

# Upload app.py
gcloud compute scp \
    generative-ai-chatbot/app.py \
    ${VM_NAME}:/tmp/app.py \
    --zone=${ZONE} && \
gcloud compute ssh ${VM_NAME} --zone=${ZONE} --command="
    sudo mv /tmp/app.py /opt/chatbot/generative-ai-chatbot/app.py && \
    sudo chown chatbot:chatbot /opt/chatbot/generative-ai-chatbot/app.py && \
    sudo chmod 644 /opt/chatbot/generative-ai-chatbot/app.py && \
    echo 'app.py updated!'
"

# Upload user_service.py
gcloud compute scp \
    generative-ai-chatbot/src/auth/user_service.py \
    ${VM_NAME}:/tmp/user_service.py \
    --zone=${ZONE} && \
gcloud compute ssh ${VM_NAME} --zone=${ZONE} --command="
    sudo mv /tmp/user_service.py /opt/chatbot/generative-ai-chatbot/src/auth/user_service.py && \
    sudo chown chatbot:chatbot /opt/chatbot/generative-ai-chatbot/src/auth/user_service.py && \
    sudo chmod 644 /opt/chatbot/generative-ai-chatbot/src/auth/user_service.py && \
    echo 'user_service.py updated!'
"

# Upload middleware.py
gcloud compute scp \
    generative-ai-chatbot/src/auth/middleware.py \
    ${VM_NAME}:/tmp/middleware.py \
    --zone=${ZONE} && \
gcloud compute ssh ${VM_NAME} --zone=${ZONE} --command="
    sudo mv /tmp/middleware.py /opt/chatbot/generative-ai-chatbot/src/auth/middleware.py && \
    sudo chown chatbot:chatbot /opt/chatbot/generative-ai-chatbot/src/auth/middleware.py && \
    sudo chmod 644 /opt/chatbot/generative-ai-chatbot/src/auth/middleware.py && \
    echo 'middleware.py updated!'
"

# Restart service after all files are uploaded
gcloud compute ssh ${VM_NAME} --zone=${ZONE} --command="
    sudo systemctl restart chatbot && \
    echo 'All files updated and service restarted!'
"

