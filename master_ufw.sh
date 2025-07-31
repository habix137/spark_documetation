#!/bin/bash
# SPARK MASTER FIREWALL RULES (DYNAMIC PORT DETECTION)
# Reads ports from Spark configs before applying rules

echo "🔍 Detecting Spark Master ports..."

# Function to get config value from spark-defaults.conf
get_spark_config() {
    local key="$1"
    local default="$2"
    local value=$(grep -E "^${key}" ${SPARK_HOME}/conf/spark-defaults.conf 2>/dev/null | awk '{print $2}')
    echo "${value:-$default}"
}

# Get ports (with defaults)
SPARK_MASTER_UI_PORT=$(get_spark_config "spark.master.ui.port" "8080")
SPARK_MASTER_PORT=$(get_spark_config "spark.master.port" "7077")
SPARK_APP_UI_START=$(get_spark_config "spark.ui.port" "4040")
SPARK_APP_UI_END=$((SPARK_APP_UI_START + 10))

echo "🔹 Configuring firewall for:"
echo "   Master UI: ${SPARK_MASTER_UI_PORT}"
echo "   Cluster Port: ${SPARK_MASTER_PORT}"
echo "   App UI Range: ${SPARK_APP_UI_START}-${SPARK_APP_UI_END}"

# Core Services
sudo ufw allow ${SPARK_MASTER_UI_PORT}/tcp comment "Spark Master UI"
sudo ufw allow ${SPARK_MASTER_PORT}/tcp comment "Spark Master Cluster Port"

# Application UIs (dynamic range)
sudo ufw allow ${SPARK_APP_UI_START}:${SPARK_APP_UI_END}/tcp comment "Spark Application UIs"

# Optional SSH
sudo ufw allow 22/tcp comment "SSH Access" 2>/dev/null || true

# Verify
echo "✅ Applied Rules:"
sudo ufw status numbered | grep -E "${SPARK_MASTER_UI_PORT}|${SPARK_MASTER_PORT}|${SPARK_APP_UI_START}|${SPARK_APP_UI_END}|22"

echo "📌 Note: Workers need access to ${SPARK_MASTER_PORT}/tcp on this host!"
