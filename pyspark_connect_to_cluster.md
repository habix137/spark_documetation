# Connect to a Spark Cluster from PySpark (Everything You Need)

This guide is a **practical checklist + copy/paste commands** to run **PySpark** jobs on a remote Spark cluster.

It covers the most common cluster setups:
- **YARN (Hadoop)** — most common in on-prem data platforms
- **Spark Standalone**
- **Kubernetes**
- **Spark Connect** (newer “remote session” style)

> **Best practice:** Run PySpark from an **edge/gateway node inside the same network** as the cluster.  
> Running from a laptop is possible, but requires more networking + config files.

---

## 1) What you need (checklist)

### A) Client machine requirements (where you run PySpark)
You need:

1. **Java (JDK/JRE)**  
   - Spark requires Java.  
   - Typically Java 8/11/17 depending on your Spark version (cluster should dictate).

2. **Python**
   - Install Python 3.x.
   - **Your local Python version should be compatible with the cluster Spark version**.

3. **Spark client distribution (matching the cluster)**
   - You must use a Spark client that matches (or is compatible with) the cluster Spark version.
   - Usually you install Spark on the client machine or use the one already installed on the edge node.

4. **Network access to the cluster**
   - Depends on cluster type:
     - **YARN:** access to ResourceManager + NodeManagers + HDFS
     - **Standalone:** access to Spark master + worker nodes
     - **K8s:** access to Kubernetes API and container registry
   - If the cluster is internal-only, use a VPN or run from an edge node.

5. **Cluster configuration files** (critical for YARN/HDFS)
   - For Hadoop/YARN clusters you typically need:
     - `core-site.xml`
     - `hdfs-site.xml`
     - `yarn-site.xml`
     - `mapred-site.xml` (often optional but useful)
   - Sometimes also:
     - `hive-site.xml` (if using Hive Metastore / Iceberg HMS catalog)
     - `krb5.conf` (if Kerberos-enabled)

6. **Authentication**
   - Unsecured cluster: none.
   - Kerberos-secured: you need a Kerberos principal + keytab or password (`kinit`).

---

## 2) Quick “am I ready?” checks

### Java
```bash
java -version
```

### Python
```bash
python3 --version
```

### Spark client
```bash
spark-submit --version
pyspark --version
```

### Hadoop configs present (YARN/HDFS only)
```bash
ls -la $HADOOP_CONF_DIR
# should include core-site.xml, hdfs-site.xml, yarn-site.xml
```

### HDFS connectivity (YARN/HDFS only)
```bash
hdfs dfs -ls /
```

### Kerberos (only if secure)
```bash
klist
# if empty:
kinit <your_principal>
```

---

## 3) The recommended way: use `spark-submit` (works everywhere)

Even if you write PySpark code, the **cleanest** way to run it on a cluster is:

✅ `spark-submit your_job.py --master ... --deploy-mode ...`

This avoids many “driver can’t reach cluster” issues.

---

## 4) YARN cluster (most common)

### 4.1 Required configs for YARN
Set the Hadoop config directory:

```bash
export HADOOP_CONF_DIR=/etc/hadoop/conf
# or your cluster's config path
```

If Spark is installed separately and needs Hadoop configs:
```bash
export YARN_CONF_DIR="$HADOOP_CONF_DIR"
```

### 4.2 Submit a PySpark job to YARN (client deploy mode)
**Client mode** means the **driver** runs on your current machine (edge node recommended).

```bash
spark-submit \
  --master yarn \
  --deploy-mode client \
  --name pyspark-test \
  --conf spark.executor.instances=4 \
  --conf spark.executor.cores=2 \
  --conf spark.executor.memory=4g \
  --conf spark.driver.memory=2g \
  your_job.py
```

### 4.3 Submit a job to YARN (cluster deploy mode)
**Cluster mode** means the **driver** runs inside the cluster (more “remote-friendly”).

```bash
spark-submit \
  --master yarn \
  --deploy-mode cluster \
  --name pyspark-test \
  --conf spark.executor.instances=4 \
  --conf spark.executor.cores=2 \
  --conf spark.executor.memory=4g \
  --conf spark.driver.memory=2g \
  your_job.py
```

### 4.4 Run interactive PySpark shell on YARN
```bash
pyspark --master yarn --deploy-mode client
```

### 4.5 Typical YARN extras you may need

**Choose YARN queue**
```bash
--conf spark.yarn.queue=default
```

**Distribute a Python environment to executors** (if cluster nodes don’t have your needed libs)
- Option 1: Use conda/venv archive with `--archives` (advanced)
- Option 2: Package pure-python deps with `--py-files`
```bash
--py-files deps.zip
```

**Access HDFS from Spark**
Just use `hdfs:///...` paths:
```python
df = spark.read.parquet("hdfs:///warehouse/mytable")
```

---

## 5) Spark Standalone cluster (spark://...)

### 5.1 What you need
- Spark client installed locally
- Network access to Spark Master (default port often 7077)

### 5.2 Submit
```bash
spark-submit \
  --master spark://MASTER_HOST:7077 \
  --deploy-mode client \
  --conf spark.executor.memory=4g \
  --conf spark.executor.cores=2 \
  your_job.py
```

### 5.3 Interactive
```bash
pyspark --master spark://MASTER_HOST:7077
```

> If your laptop is outside the cluster network, use VPN or run from a gateway node.

---

## 6) Kubernetes (Spark on K8s)

K8s needs more setup (images, service accounts, etc.). Minimal items:
- `kubectl` configured to reach the cluster
- A container image with Spark + Python dependencies
- Spark configured with the Kubernetes API server

Example shape:
```bash
spark-submit \
  --master k8s://https://<K8S_API_SERVER> \
  --deploy-mode cluster \
  --name pyspark-k8s-test \
  --conf spark.kubernetes.container.image=<your_image> \
  --conf spark.kubernetes.namespace=<ns> \
  your_job.py
```

---

## 7) Spark Connect (remote PySpark sessions)

If your cluster supports **Spark Connect** (Spark 3.4+ typically), you can create a remote SparkSession from Python without classic driver/executor networking.

Example:
```python
from pyspark.sql import SparkSession

spark = SparkSession.builder.remote("sc://SPARK_CONNECT_HOST:15002").getOrCreate()
df = spark.range(10)
df.show()
```

To use this you need:
- A running Spark Connect server endpoint
- Your PySpark client version compatible with that server

---

## 8) Minimal PySpark test job (copy/paste)

Create a file `your_job.py`:

```python
from pyspark.sql import SparkSession

spark = SparkSession.builder.appName("pyspark-connect-test").getOrCreate()

df = spark.range(0, 10_000_000).withColumnRenamed("id", "n")
print("Count:", df.count())

spark.stop()
```

Run it with one of the submit commands above.

---

## 9) If you insist on “pure Python” without spark-submit (not recommended)

You *can* create a session in code:

### For Standalone
```python
from pyspark.sql import SparkSession

spark = (
  SparkSession.builder
    .appName("standalone-test")
    .master("spark://MASTER_HOST:7077")
    .getOrCreate()
)
```

### For YARN
For YARN, it’s better to rely on `spark-submit --master yarn ...`  
If you set `.master("yarn")` in code, you still need the same environment/configs and it’s more fragile.

---

## 10) Common problems & fixes

### Problem: `JAVA_HOME is not set`
Fix:
```bash
export JAVA_HOME=/path/to/java
export PATH="$JAVA_HOME/bin:$PATH"
```

### Problem: YARN “cannot find ResourceManager” / “NoSuchMethodError” / config issues
Fix: ensure correct Hadoop configs
```bash
export HADOOP_CONF_DIR=/etc/hadoop/conf
```
Also ensure Spark was built for your Hadoop version or uses compatible Hadoop client jars.

### Problem: In YARN client mode, executors can’t talk to driver
Fix:
- Prefer **--deploy-mode cluster**
- Or run driver on an **edge node** in same network
- Or set driver host/bind explicitly (advanced):
```bash
--conf spark.driver.host=<reachable_ip> \
--conf spark.driver.bindAddress=0.0.0.0
```

### Problem: Python library missing on executors
Fix:
- Install dependency on all nodes **or**
- Ship deps with `--py-files` / `--archives` / build a custom environment

### Problem: Kerberos auth failures
Fix:
```bash
kinit <principal>
# or configure keytab usage in spark-submit
```

---

## 11) Practical “what should I do?” (recommended path)

If your cluster uses **YARN/HDFS** (common):
1. SSH into a **gateway/edge node** that already has Spark/Hadoop configs.
2. Run:
   ```bash
   pyspark --master yarn --deploy-mode client
   ```
3. For real jobs, use `spark-submit --master yarn --deploy-mode cluster`.

---

## Appendix: Environment variables you’ll commonly set

```bash
export SPARK_HOME=/opt/spark
export PATH="$SPARK_HOME/bin:$PATH"

export HADOOP_CONF_DIR=/etc/hadoop/conf
export YARN_CONF_DIR="$HADOOP_CONF_DIR"

export PYSPARK_PYTHON=python3
export PYSPARK_DRIVER_PYTHON=python3
```

---

If you tell me your cluster type (**YARN / standalone / k8s**) and whether it’s **Kerberos-secured**, I can tailor the exact minimal command set for your setup.
