# PySpark → Spark Standalone Cluster (spark://...)  
## Connect, run jobs with `spark-submit`, and an “expanded” SparkSession builder

This guide assumes you have **Spark Standalone** (no Kubernetes, no YARN), and you want to run PySpark jobs using **spark-submit** and/or create a `SparkSession` that points to:

```
spark://MASTER_HOST:7077
```

---

## 0) What you need (quick checklist)

### On the machine where you run PySpark (client / gateway / edge)
- **Java** (must be compatible with your cluster Spark version)
- **Python 3**
- **Spark client installed** (ideally same Spark version as the cluster)
- **Network access** to:
  - Spark Master: `MASTER_HOST:7077`
  - Spark UI (optional): Master UI often `8080`, app UI `4040+`
  - Worker nodes must be able to reach your **driver** (important in client mode)

### Quick checks
```bash
java -version
python3 --version
spark-submit --version
```

---

## 1) The recommended way: run PySpark with `spark-submit`

### 1.1 Minimal submit (Standalone)
```bash
spark-submit \
  --master spark://MASTER_HOST:7077 \
  your_job.py
```

### 1.2 Typical submit (resources + name)
```bash
spark-submit \
  --master spark://MASTER_HOST:7077 \
  --name standalone-test \
  --conf spark.executor.instances=4 \
  --conf spark.executor.cores=2 \
  --conf spark.executor.memory=4g \
  --conf spark.driver.memory=2g \
  your_job.py
```

### 1.3 Standalone deploy modes (client vs cluster)

- **client (default)**: driver runs on *your current machine*  
  ✅ good for interactive / debugging  
  ❗ workers must be able to reach your driver network-wise

- **cluster**: driver runs on a worker inside the cluster  
  ✅ best if your client machine is outside cluster network  
  ❗ not interactive

Example (cluster mode):
```bash
spark-submit \
  --master spark://MASTER_HOST:7077 \
  --deploy-mode cluster \
  --name standalone-test \
  --conf spark.executor.cores=2 \
  --conf spark.executor.memory=4g \
  your_job.py
```

> If you see “executors can’t connect to driver” issues in client mode, switch to **cluster mode** or fix driver networking (see section 4).

---

## 2) Minimal PySpark test job (copy/paste)

Create `your_job.py`:
```python
from pyspark.sql import SparkSession

spark = SparkSession.builder.appName("standalone-smoke-test").getOrCreate()

df = spark.range(0, 10_000_000).withColumnRenamed("id", "n")
print("Count =", df.count())

spark.stop()
```

Run:
```bash
spark-submit --master spark://MASTER_HOST:7077 your_job.py
```

---

## 3) “Expanded” SparkSession.builder for Standalone

### 3.1 Why use builder configs?
Anything you can do in `spark-submit --conf key=value` can also be set in code using:
```python
.config("key", "value")
```

**Best practice:** Use `spark-submit` for job-level settings and keep code minimal.  
But if you want a fully expanded template, here it is.

---

## 3.2 Fully expanded template (practical options people tune)

```python
from pyspark.sql import SparkSession

spark = (
    SparkSession.builder
    # ------------------------------------------------------------
    # A) Identity
    # ------------------------------------------------------------
    .appName("standalone-test")
    .master("spark://MASTER_HOST:7077")

    # ------------------------------------------------------------
    # B) Resources (Standalone)
    # ------------------------------------------------------------
    # Number of executors (often respected when dynamic allocation is OFF)
    .config("spark.executor.instances", "4")
    # CPU per executor
    .config("spark.executor.cores", "2")
    # Memory per executor
    .config("spark.executor.memory", "4g")

    # Driver resources (driver runs where you start the job in client mode)
    .config("spark.driver.memory", "2g")
    .config("spark.driver.cores", "1")

    # Optional: cap total cores the app can take (Standalone feature)
    .config("spark.cores.max", "8")

    # ------------------------------------------------------------
    # C) Driver networking (IMPORTANT if driver is not inside cluster network)
    # ------------------------------------------------------------
    # Uncomment if workers cannot reach the driver in client mode:
    # .config("spark.driver.host", "DRIVER_REACHABLE_IP")
    # .config("spark.driver.bindAddress", "0.0.0.0")

    # Optional fixed ports (useful for firewalls / port collisions)
    # .config("spark.driver.port", "38001")
    # .config("spark.blockManager.port", "38002")
    # .config("spark.ui.port", "4040")

    # ------------------------------------------------------------
    # D) Serialization & performance
    # ------------------------------------------------------------
    .config("spark.serializer", "org.apache.spark.serializer.KryoSerializer")

    # Parallelism defaults (tune based on cluster cores and workload)
    .config("spark.default.parallelism", "200")
    .config("spark.sql.shuffle.partitions", "200")

    # Spark SQL adaptive execution (generally helps)
    .config("spark.sql.adaptive.enabled", "true")
    .config("spark.sql.adaptive.coalescePartitions.enabled", "true")
    .config("spark.sql.adaptive.skewJoin.enabled", "true")

    # Broadcast join behavior
    .config("spark.sql.autoBroadcastJoinThreshold", str(64 * 1024 * 1024))  # 64MB
    .config("spark.sql.broadcastTimeout", "600")

    # ------------------------------------------------------------
    # E) Shuffle / compression
    # ------------------------------------------------------------
    .config("spark.shuffle.compress", "true")
    .config("spark.shuffle.spill.compress", "true")
    .config("spark.io.compression.codec", "lz4")  # or snappy

    # ------------------------------------------------------------
    # F) Dynamic allocation (optional)
    # ------------------------------------------------------------
    # If you want Spark to scale executors automatically:
    # .config("spark.dynamicAllocation.enabled", "true")
    # .config("spark.dynamicAllocation.minExecutors", "1")
    # .config("spark.dynamicAllocation.maxExecutors", "20")
    # .config("spark.dynamicAllocation.initialExecutors", "4")

    # ------------------------------------------------------------
    # G) Timeouts & reliability
    # ------------------------------------------------------------
    .config("spark.network.timeout", "300s")
    .config("spark.executor.heartbeatInterval", "30s")
    .config("spark.sql.files.ignoreMissingFiles", "false")
    .config("spark.sql.files.ignoreCorruptFiles", "false")

    # ------------------------------------------------------------
    # H) Logging (optional)
    # ------------------------------------------------------------
    # You normally configure logging via log4j2.properties.
    # But you can reduce console spam:
    # .config("spark.ui.showConsoleProgress", "true")

    # ------------------------------------------------------------
    # I) Extra JARs / Packages (connectors, JDBC drivers, etc.)
    # ------------------------------------------------------------
    # Prefer spark-submit --packages / --jars, but you can also do:
    # .config("spark.jars", "/path/a.jar,/path/b.jar")
    # .config("spark.jars.packages", "org.postgresql:postgresql:42.7.3")

    # ------------------------------------------------------------
    # J) Hive (ONLY if you actually have Hive Metastore configured)
    # ------------------------------------------------------------
    # If you want spark.sql to use hive catalog features:
    # .enableHiveSupport()

    .getOrCreate()
)
```

---

## 3.3 Mapping: builder configs ↔ spark-submit

Example mapping:

```bash
spark-submit \
  --master spark://MASTER_HOST:7077 \
  --conf spark.executor.instances=4 \
  --conf spark.executor.cores=2 \
  --conf spark.executor.memory=4g \
  --conf spark.driver.memory=2g \
  your_job.py
```

Equivalent inside code:

```python
SparkSession.builder \
  .master("spark://MASTER_HOST:7077") \
  .config("spark.executor.instances","4") \
  .config("spark.executor.cores","2") \
  .config("spark.executor.memory","4g") \
  .config("spark.driver.memory","2g") \
  .getOrCreate()
```

---

## 4) Common Standalone networking issue (client mode)

### Symptom
- Job starts, but executors never run tasks
- Errors like “cannot connect to driver”, “connection refused”, or driver address looks wrong

### Fix options
1) Prefer **cluster deploy mode**:
```bash
spark-submit --master spark://MASTER_HOST:7077 --deploy-mode cluster your_job.py
```

2) In **client mode**, set driver host to an address workers can reach:
```bash
spark-submit \
  --master spark://MASTER_HOST:7077 \
  --conf spark.driver.host=DRIVER_REACHABLE_IP \
  --conf spark.driver.bindAddress=0.0.0.0 \
  your_job.py
```

Or in code (same keys):
```python
.config("spark.driver.host", "DRIVER_REACHABLE_IP") \
.config("spark.driver.bindAddress", "0.0.0.0")
```

---

## 5) Useful “extras” you’ll likely need

### 5.1 Add JDBC driver (example: PostgreSQL)
Preferred:
```bash
spark-submit \
  --master spark://MASTER_HOST:7077 \
  --packages org.postgresql:postgresql:42.7.3 \
  your_job.py
```

### 5.2 Add local JARs
```bash
spark-submit \
  --master spark://MASTER_HOST:7077 \
  --jars /opt/jars/my-udf.jar,/opt/jars/driver.jar \
  your_job.py
```

### 5.3 Send Python dependencies to executors
If you have pure python modules:
```bash
zip -r deps.zip your_module_dir
spark-submit \
  --master spark://MASTER_HOST:7077 \
  --py-files deps.zip \
  your_job.py
```

---

## 6) Environment variables (often helpful)

```bash
export SPARK_HOME=/opt/spark
export PATH="$SPARK_HOME/bin:$PATH"

export PYSPARK_PYTHON=python3
export PYSPARK_DRIVER_PYTHON=python3
```

---

## 7) Quick interactive test (optional)

Interactive shell against standalone master:
```bash
pyspark --master spark://MASTER_HOST:7077
```

---

## 8) Minimal “best practice” setup summary

1) Use **spark-submit** as the standard runner  
2) Use **--deploy-mode cluster** if your client machine is not reachable by workers  
3) Only set critical configs (resources + a few SQL/shuffle defaults)  
4) Keep the Python code clean; pass settings via `spark-submit` where possible

