# PySpark `SparkSession.builder` for Spark Standalone — Full Explanation (Practical Options)

This document explains (line-by-line) a **practical “expanded”** `SparkSession.builder` template for connecting **PySpark** to a **Spark Standalone** cluster (`spark://...`).

> Scope: **Spark Standalone only** (no YARN, no Kubernetes).  
> Goal: Understand *what each config does*, when to change it, and what can go wrong.

---

## 1) The expanded template (reference)

> You can copy this and then delete what you don’t need.

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
    .config("spark.executor.instances", "4")
    .config("spark.executor.cores", "2")
    .config("spark.executor.memory", "4g")

    .config("spark.driver.memory", "2g")
    .config("spark.driver.cores", "1")

    .config("spark.cores.max", "8")

    # ------------------------------------------------------------
    # C) Driver networking
    # ------------------------------------------------------------
    # .config("spark.driver.host", "DRIVER_REACHABLE_IP")
    # .config("spark.driver.bindAddress", "0.0.0.0")
    # .config("spark.driver.port", "38001")
    # .config("spark.blockManager.port", "38002")
    # .config("spark.ui.port", "4040")

    # ------------------------------------------------------------
    # D) Serialization & performance
    # ------------------------------------------------------------
    .config("spark.serializer", "org.apache.spark.serializer.KryoSerializer")

    .config("spark.default.parallelism", "200")
    .config("spark.sql.shuffle.partitions", "200")

    .config("spark.sql.adaptive.enabled", "true")
    .config("spark.sql.adaptive.coalescePartitions.enabled", "true")
    .config("spark.sql.adaptive.skewJoin.enabled", "true")

    .config("spark.sql.autoBroadcastJoinThreshold", str(64 * 1024 * 1024))
    .config("spark.sql.broadcastTimeout", "600")

    # ------------------------------------------------------------
    # E) Shuffle / compression
    # ------------------------------------------------------------
    .config("spark.shuffle.compress", "true")
    .config("spark.shuffle.spill.compress", "true")
    .config("spark.io.compression.codec", "lz4")

    # ------------------------------------------------------------
    # F) Dynamic allocation (optional)
    # ------------------------------------------------------------
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
    # .config("spark.ui.showConsoleProgress", "true")

    # ------------------------------------------------------------
    # I) Extra JARs / Packages (connectors, JDBC drivers, etc.)
    # ------------------------------------------------------------
    # .config("spark.jars", "/path/a.jar,/path/b.jar")
    # .config("spark.jars.packages", "org.postgresql:postgresql:42.7.3")

    # ------------------------------------------------------------
    # J) Hive (optional)
    # ------------------------------------------------------------
    # .enableHiveSupport()

    .getOrCreate()
)
```

---

## 2) How this relates to `spark-submit`

Most clusters prefer you set configs via `spark-submit`:

```bash
spark-submit \
  --master spark://MASTER_HOST:7077 \
  --conf spark.executor.instances=4 \
  --conf spark.executor.cores=2 \
  --conf spark.executor.memory=4g \
  --conf spark.driver.memory=2g \
  your_job.py
```

Anything you pass with `--conf` can also be set in code with `.config(...)`.

**Best practice**
- Use `spark-submit` for runtime configs (resources, jars, packages).
- Keep code minimal (app logic + only essential Spark settings).

---

## 3) Section A — Identity

### `appName("standalone-test")`
Sets the name shown in:
- Spark Master UI
- Spark application UI
- logs and history (if enabled)

Change it to something meaningful:
- `etl-orders-iceberg`
- `benchmark-join-test`
- `daily-ingest-2026-02-12`

### `master("spark://MASTER_HOST:7077")`
Tells Spark where the **Standalone Master** is.

Common forms:
- `spark://master1:7077`
- `spark://10.0.0.10:7077`

> If you can’t connect, check network/firewall and that the master is actually listening on 7077.

---

## 4) Section B — Resources (Standalone)

In Spark, the **driver** coordinates work, and **executors** do the distributed computation.

### `spark.executor.instances`
How many executors Spark should request.

- More executors ⇒ more parallelism (up to cluster limits)
- Too many executors ⇒ overhead, scheduling churn

**When to increase**
- Cluster has many nodes/cores and your job is slow due to lack of parallelism.

**When to reduce**
- Small cluster or you share the cluster with other jobs.
- You see heavy overhead / too many small tasks.

### `spark.executor.cores`
Cores per executor.

Common values: `1` to `5` (depends on your node size).

- Higher cores/executor ⇒ fewer executors for same cores
- Lower cores/executor ⇒ more executors, more JVMs

**Rule of thumb**
- Start with `2–4` cores per executor.
- Avoid extremely large executors unless you know why.

### `spark.executor.memory`
Executor JVM heap size.

- Too small ⇒ OutOfMemoryError / frequent spills
- Too large ⇒ fewer executors can fit on nodes, longer GC pauses

**Rule of thumb**
- Start with `4g` or `8g` depending on workload and node RAM.

### `spark.driver.memory` and `spark.driver.cores`
Driver resources.

- In `--deploy-mode client`, driver runs on the machine you launch from.
- In `--deploy-mode cluster`, driver runs inside the cluster.

Driver memory needs increase when:
- You do very large `collect()` or `toPandas()` (generally avoid)
- Large job planning, many partitions, many files
- Huge broadcast variables on driver (careful)

### `spark.cores.max` (Standalone feature)
Caps total cores the application can use across all executors.

Example:
- If cluster has 100 cores but you set `spark.cores.max=8`, the app uses at most 8.

Useful when:
- You want to prevent one job from taking the entire cluster
- You share cluster with others

---

## 5) Section C — Driver networking (critical in Standalone client mode)

This is the **#1 issue** when running client-mode from a machine that is not in the same network as workers.

### Why it breaks
Executors must connect back to the driver.  
If the driver advertises an IP/hostname that workers **cannot reach**, tasks never start.

### `spark.driver.host`
Force the driver to advertise a reachable IP/hostname.

Use it if:
- The driver machine has multiple NICs
- DNS resolves to a wrong IP
- You’re launching from a laptop or a NAT network

### `spark.driver.bindAddress`
Which local interface the driver binds to.

Common safe value:
- `0.0.0.0` (listen on all interfaces)

### Fixed ports
Use fixed ports if:
- You have strict firewall rules
- You need to open specific ports only

Keys:
- `spark.driver.port`
- `spark.blockManager.port`
- `spark.ui.port`

> If you don’t have firewall constraints, leave these unset.

**Recommendation**
- If you have driver connectivity problems:  
  ✅ Prefer `spark-submit --deploy-mode cluster`  
  or set `spark.driver.host` properly.

---

## 6) Section D — Serialization & performance

### `spark.serializer = KryoSerializer`
Kryo is usually faster and more compact than Java serialization.

Keep it enabled for performance; some workloads benefit significantly.

### `spark.default.parallelism`
Default number of partitions for RDD operations (when Spark must pick a number).

If too low:
- Underutilizes CPU (not enough tasks)

If too high:
- Too many tasks overhead

**How to choose**
- A common starting point: `2–4 × total cluster cores`

### `spark.sql.shuffle.partitions`
Number of partitions after shuffle operations in Spark SQL:
- joins
- aggregations
- distinct
- repartition by key

Same rule as above:
- Too low ⇒ few huge partitions ⇒ slow + skew risks
- Too high ⇒ overhead

### AQE (Adaptive Query Execution)
These options let Spark **change the plan at runtime** based on real statistics.

- `spark.sql.adaptive.enabled=true`
  - Turns AQE on.

- `spark.sql.adaptive.coalescePartitions.enabled=true`
  - Combines tiny shuffle partitions into fewer bigger ones to reduce overhead.

- `spark.sql.adaptive.skewJoin.enabled=true`
  - Helps when one join key is extremely frequent (data skew).

AQE is usually recommended for Spark SQL workloads.

### Broadcast join controls
- `spark.sql.autoBroadcastJoinThreshold`
  - If a table is smaller than this threshold, Spark may broadcast it to all executors.
  - Broadcasting can make joins much faster (no shuffle for that side).

- `spark.sql.broadcastTimeout`
  - If broadcasting takes too long (slow network / big broadcast), job may fail.
  - Increasing timeout helps stability.

---

## 7) Section E — Shuffle / compression

Shuffles move data over the network and write intermediate data to disk.

### `spark.shuffle.compress=true`
Compress shuffle data sent over network and stored.

### `spark.shuffle.spill.compress=true`
Compress spilled data written to disk during shuffle.

### `spark.io.compression.codec`
Codec used for compression:
- `lz4` (fast)
- `snappy` (popular)
- `zstd` (often better ratio; depends on Spark build/version)

**Rule of thumb**
- Use `lz4` or `snappy` for speed
- Consider `zstd` if you want better compression and have CPU to spare

---

## 8) Section F — Dynamic allocation (optional)

Dynamic allocation scales executor count up/down based on load.

Keys:
- `spark.dynamicAllocation.enabled`
- `spark.dynamicAllocation.minExecutors`
- `spark.dynamicAllocation.maxExecutors`
- `spark.dynamicAllocation.initialExecutors`

**When to use**
- Shared cluster where you want resources to be released automatically.

**When NOT to use**
- Very small clusters or when you want predictable executor counts.
- Some environments require additional setup (shuffle tracking / external shuffle service depending on Spark version).

If you enable it and see odd behavior, disable and set `spark.executor.instances` explicitly.

---

## 9) Section G — Timeouts & reliability

### `spark.network.timeout`
How long Spark waits before considering a network connection dead.

Increase it if:
- You have long GC pauses
- Network is slow or unstable
- Huge shuffles cause long delays

### `spark.executor.heartbeatInterval`
Executors send heartbeats to driver.

- Must be **less** than `spark.network.timeout`.
- If heartbeat is too infrequent, driver might mark executor dead.

### Missing/corrupt files behavior
- `spark.sql.files.ignoreMissingFiles=false`
- `spark.sql.files.ignoreCorruptFiles=false`

If `false`:
- Spark fails fast when data problems happen (good for correctness).

If `true`:
- Spark will skip missing/corrupt files (useful for some streaming/lake scenarios, but can hide issues).

---

## 10) Section H — Logging

### `spark.ui.showConsoleProgress`
Shows the progress bar in console.

Real logging level is typically configured via `log4j2.properties`.

If you want less spam, you usually change log4j settings, not Spark configs.

---

## 11) Section I — Extra JARs / Packages

You often need connectors:
- JDBC drivers (Postgres, MySQL, etc.)
- S3/HDFS connectors (depending on environment)
- Custom UDF jars

Preferred ways:
- `spark-submit --packages group:artifact:version`
- `spark-submit --jars /path/a.jar,/path/b.jar`

In code you can also set:
- `spark.jars`
- `spark.jars.packages`

But operationally it’s cleaner to keep dependency wiring in `spark-submit`.

---

## 12) Section J — Hive support (optional)

`.enableHiveSupport()` enables Spark’s Hive integrations:
- reading Hive tables via metastore
- Hive UDFs (depending on setup)
- `spark.sql.catalogImplementation` becomes hive-like behavior

Only enable if:
- You have a Hive metastore configured
- The cluster is set up for it

Otherwise, leave it off.

---

## 13) Recommended minimal set (start here)

If you want the “best start” minimal config:

```python
spark = (
  SparkSession.builder
    .appName("standalone-test")
    .master("spark://MASTER_HOST:7077")
    .config("spark.executor.instances", "4")
    .config("spark.executor.cores", "2")
    .config("spark.executor.memory", "4g")
    .config("spark.driver.memory", "2g")
    .config("spark.sql.adaptive.enabled", "true")
    .getOrCreate()
)
```

Then tune:
- shuffle partitions
- executor count
- driver networking (only if needed)

---

## 14) Troubleshooting quick table

| Symptom | Likely cause | Fix |
|---|---|---|
| Executors start but tasks never run | Workers cannot reach driver (client mode) | Use `--deploy-mode cluster` or set `spark.driver.host` |
| Job fails with OOM on executor | executor memory too small | increase `spark.executor.memory` or reduce partitions skew |
| Very slow joins/aggregations | shuffle partitions wrong / skew | tune `spark.sql.shuffle.partitions`, keep AQE on |
| Too many tiny tasks | parallelism too high | reduce `spark.default.parallelism` / `spark.sql.shuffle.partitions` |
| Broadcast join timeout | broadcast takes too long | increase `spark.sql.broadcastTimeout` or lower threshold |

---

## 15) One more important note: “builder vs spark-submit”

If you run:
```bash
spark-submit --conf spark.executor.memory=8g your_job.py
```

and inside code you do:
```python
.config("spark.executor.memory","4g")
```

**the final value depends on precedence.**  
In practice: keep resource configs in one place (preferably `spark-submit`) to avoid confusion.

