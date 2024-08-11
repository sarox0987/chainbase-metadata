#!/bin/bash

# Change directory to the target directory
cd /root/chainbase-avs-contracts

# Get operator address and ECDSA password from user
read -p "Enter operator address: " OPERATOR_ADDRESS
read -p "Enter ECDSA password: " ECDSA_PASSWORD

# Create prometheus.yml
cat <<EOF > prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    operator: "$OPERATOR_ADDRESS"

remote_write:
  - url: http://testnet-metrics.chainbase.com:9090/api/v1/write
    write_relabel_configs:
      - source_labels: [job]
        regex: "chainbase-avs"
        action: keep

scrape_configs:
  - job_name: "chainbase-avs"
    metrics_path: /metrics
    static_configs:
      - targets: [
          "chainbase-node:9092"
        ]
EOF
echo "Prometheus configuration written to prometheus.yml"

# Create .env file
cat << EOF > .env
# FLINK CONFIG
FLINK_CONNECT_ADDRESS=flink-jobmanager
FLINK_JOBMANAGER_PORT=8081
NODE_PROMETHEUS_PORT=9091
PROMETHEUS_CONFIG_PATH=./prometheus.yml

# Chainbase AVS mounted locations
NODE_APP_PORT=8080
NODE_ECDSA_KEY_FILE=/app/operator_keys/ecdsa_key.json
NODE_LOG_DIR=/app/logs

# Node logs configs
NODE_LOG_LEVEL=debug
NODE_LOG_FORMAT=text

# Metrics specific configs
NODE_ENABLE_METRICS=true
NODE_METRICS_PORT=9092

# holesky smart contracts
AVS_CONTRACT_ADDRESS=0x5E78eFF26480A75E06cCdABe88Eb522D4D8e1C9d
AVS_DIR_CONTRACT_ADDRESS=0x055733000064333CaDDbC92763c58BF0192fFeBf

NODE_CHAIN_RPC=https://rpc.ankr.com/eth_holesky
NODE_CHAIN_ID=17000

NODE_ECDSA_KEY_PASSWORD=$ECDSA_PASSWORD
EOF
echo ".env file successfully created!"

# Create docker-compose.yml
cat <<EOF > docker-compose.yml

services:
  prometheus:
    image: prom/prometheus:latest
    user: root
    container_name: prometheus
    env_file:
      - .env    
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    command:
      - "--enable-feature=expand-external-labels"
      - "--config.file=/etc/prometheus/prometheus.yml"
    ports:
      - '9091:9090'

  flink-jobmanager:
    image: flink:latest
    user: root
    container_name: flink-jobmanager
    env_file:
      - .env
    command: jobmanager
    environment:
      - |
        FLINK_PROPERTIES=
        jobmanager.rpc.address: flink-jobmanager

  flink-taskmanager:
    image: flink:latest
    user: root
    env_file:
      - .env
    container_name: flink-taskmanager
    depends_on:
      - flink-jobmanager
    command: taskmanager
    environment:
      - |
        FLINK_PROPERTIES=
        jobmanager.rpc.address: flink-jobmanager
        taskmanager.numberOfTaskSlots: 4

  chainbase-node:
    image: repository.chainbase.com/network/chainbase-node:testnet-v0.1.7
    container_name: chainbase-node
    command: [
      "run"
    ]
    env_file:
      - .env
    ports:
      - '8080:8080'
      - '9092:9092'
    volumes:
      - "./chainbase.ecdsa.key.json:/app/operator_keys/ecdsa_key.json"
    depends_on:
      - prometheus
      - flink-jobmanager
      - flink-taskmanager
EOF
echo "docker-compose.yml file successfully created!"

# Run docker commands
docker-compose stop && docker container prune -f && docker-compose up -d

echo "Docker compose started"
