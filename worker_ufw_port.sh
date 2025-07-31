#!/bin/bash
# SPARK WORKER FIREWALL RULES
# Balanced security + functionality

if [ -z "$1" ]; then
  echo "❌ Usage: $0 <MASTER_IP>"
  exit 1
fi

MASTER_IP=$1
echo "🔹 Configuring Spark Worker firewall (Master: $MASTER_IP)..."

# Required
sudo ufw allow 8081/tcp comment "Spark Worker UI"
sudo ufw allow from $MASTER_IP to any port 7077/tcp comment "Spark Master Connection"

# Spark Service Ports (safer than ephemeral range)
sudo ufw allow 7337/tcp comment "Spark Shuffle Service"
sudo ufw allow 10000/tcp comment "Spark BlockManager"

# Verify
echo "✅ Worker Rules:"
sudo ufw status numbered | grep -E '8081|7077|7337|10000'

echo "📌 Note: Adjust ports if using custom spark.{shuffle,blockManager}.port"
