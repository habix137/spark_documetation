# Upload / Put Files into HDFS with PySpark (and read/write correctly)

This guide covers **everything practical** you need to:
- **Upload (PUT) files from local → HDFS**
- **Read files from HDFS in PySpark**
- **Write datasets back to HDFS with Spark**
- (Bonus) **Download from HDFS → local** when you need a copy

> Notes:
> - In Spark, “upload to HDFS” usually means either:
>   1) **Copy a raw file** into HDFS (`hdfs dfs -put`), or  
>   2) **Read data (local or HDFS) and write it** as Parquet/CSV/etc. into HDFS.
> - Spark jobs run distributed. A local path like `/tmp/a.csv` exists only on the **driver machine**, not on executors (unless shared storage).

---

## 0) Prerequisites (must be correct)

### 0.1 You need working HDFS client access
On the machine where you run `spark-submit` (usually an edge/gateway node):

```bash
hdfs version
hdfs dfs -ls /
```

If those fail, fix HDFS client / configs first.

### 0.2 Hadoop configs
Usually you need:

```bash
export HADOOP_CONF_DIR=/etc/hadoop/conf
# then
hdfs dfs -ls /
```

### 0.3 Kerberos (only if your cluster is secure)
```bash
klist
# if not logged in:
kinit <your_principal>
```

---

## 1) Understanding paths: `hdfs:///` vs `hdfs://namenode:8020/`

### Recommended
Use **logical default FS** (cleanest):
- `hdfs:///data/input/file.csv`
- `hdfs:///warehouse/tables/mytable`

Spark/Hadoop will resolve the Namenode from `core-site.xml`.

### Explicit Namenode URI (when needed)
- `hdfs://namenode-host:8020/data/input/file.csv`

Use this if your environment does **not** have correct `fs.defaultFS` configured.

---

## 2) Upload (PUT) a local file into HDFS (recommended for raw files)

### 2.1 Copy a single file
```bash
hdfs dfs -mkdir -p /data/input
hdfs dfs -put -f ./myfile.csv /data/input/
hdfs dfs -ls -h /data/input
```

Equivalent commands:
- `hdfs dfs -copyFromLocal`
- `hadoop fs -put` (older style)

### 2.2 Copy a directory (many files)
```bash
hdfs dfs -mkdir -p /data/input/batch1
hdfs dfs -put -f ./local_folder/* /data/input/batch1/
```

### 2.3 Upload large files safely (resumable download is easier than resumable upload)
HDFS CLI `-put` is not truly resumable like some object stores.
For large data, consider:
- splitting into parts (optional)
- or doing the transfer from a stable server close to the cluster

### 2.4 Verify size
```bash
hdfs dfs -du -h /data/input/myfile.csv
```

---

## 3) Upload into HDFS **from inside a PySpark job** (2 common approaches)

### Approach A (simple): call the HDFS CLI using `subprocess` (driver-side)
This runs on the **driver machine** (the machine launching the job).

```python
import subprocess

local_path = "/path/on/driver/myfile.csv"
hdfs_path  = "/data/input/myfile.csv"

subprocess.run(["hdfs", "dfs", "-mkdir", "-p", "/data/input"], check=True)
subprocess.run(["hdfs", "dfs", "-put", "-f", local_path, hdfs_path], check=True)

print("Uploaded to HDFS:", hdfs_path)
```

✅ Pros:
- Works anywhere HDFS CLI works
- Easy to debug

⚠️ Cons:
- Driver must have the file locally
- Not “distributed” (single machine upload)

---

### Approach B: use WebHDFS (HTTP upload) (works even without `hdfs` CLI)
Only if WebHDFS is enabled on your cluster.

**How WebHDFS upload works** (two-step redirect):
1) Request a create URL from NameNode  
2) Upload bytes to the DataNode URL you get in redirect

Example (driver-side) using `requests`:

```python
import requests

namenode_http = "http://NAMENODE_HOST:9870"     # Hadoop 3.x often 9870 (HTTP)
user = "hdfs"                                   # or your HDFS user
hdfs_target = "/data/input/myfile.csv"
local_path = "./myfile.csv"

# Step 1: ask NameNode to create (it redirects to a DataNode)
create_url = f"{namenode_http}/webhdfs/v1{hdfs_target}"
params = {"op": "CREATE", "overwrite": "true", "user.name": user}
r1 = requests.put(create_url, params=params, allow_redirects=False)
r1.raise_for_status()

# Step 2: PUT the data to the redirected URL
dn_url = r1.headers["Location"]
with open(local_path, "rb") as f:
    r2 = requests.put(dn_url, data=f)
r2.raise_for_status()

print("Uploaded via WebHDFS:", hdfs_target)
```

✅ Pros:
- Does not require `hdfs` CLI installed
- Useful from containers / restricted environments

⚠️ Cons:
- WebHDFS may be disabled
- Kerberos-secured clusters require extra auth setup (SPNEGO)

---

## 4) “Upload with Spark”: read local → write to HDFS (best for datasets)

If your goal is to **convert** a local file into a distributed dataset on HDFS (Parquet recommended),
Spark can read local data on the **driver** and write it distributed.

### 4.1 Read a local CSV and write Parquet to HDFS
```python
from pyspark.sql import SparkSession

spark = SparkSession.builder.appName("local-to-hdfs").getOrCreate()

df = (spark.read
      .option("header", "true")
      .option("inferSchema", "true")
      .csv("file:///home/user/myfile.csv"))     # local path on the DRIVER

(df.repartition(32)                              # controls number of output files
   .write.mode("overwrite")
   .parquet("hdfs:///data/parquet/myfile_parquet"))

spark.stop()
```

✅ Pros:
- Produces fast Spark-friendly format (Parquet)
- Distributed write
- You can control file counts with repartition

⚠️ Key rule:
- `file:///...` is local to the machine running the driver.
- If you run in standalone **cluster deploy mode**, driver is in the cluster and needs access to that local file.

---

## 5) Read files from HDFS with PySpark (common patterns)

### 5.1 Read Parquet
```python
df = spark.read.parquet("hdfs:///data/parquet/myfile_parquet")
```

### 5.2 Read CSV
```python
df = (spark.read
      .option("header", "true")
      .option("inferSchema", "true")
      .csv("hdfs:///data/input/*.csv"))
```

### 5.3 Read JSON
```python
df = spark.read.json("hdfs:///data/input/events/*.json")
```

### 5.4 Read text files (lines)
```python
rdd = spark.sparkContext.textFile("hdfs:///data/logs/app/*.log")
```

### 5.5 Read whole files as a single record (small files only)
```python
rdd = spark.sparkContext.wholeTextFiles("hdfs:///data/docs/*.txt")
# rdd: (path, file_content)
```

### 5.6 Read binary files (images, zip, pdf, etc.)
```python
rdd = spark.sparkContext.binaryFiles("hdfs:///data/binary/*")
# rdd: (path, PortableDataStream)
```

---

## 6) Write back to HDFS with Spark (best practices)

### 6.1 Write Parquet (recommended)
```python
(df.write
   .mode("overwrite")               # overwrite | append | errorifexists | ignore
   .parquet("hdfs:///warehouse/my_table"))
```

### 6.2 Write partitioned datasets (good for big tables)
```python
(df.write
   .mode("overwrite")
   .partitionBy("dt")               # creates dt=YYYY-MM-DD folders
   .parquet("hdfs:///warehouse/events"))
```

### 6.3 Control number of output files
- Use `repartition(N)` **before write** to increase parallelism / files
- Use `coalesce(N)` to reduce files (no full shuffle when shrinking)

```python
(df.repartition(64)
   .write.mode("overwrite")
   .parquet("hdfs:///data/out/part64"))
```

**Avoid writing a single file unless you must**
```python
(df.coalesce(1)
   .write.mode("overwrite")
   .csv("hdfs:///data/out/single_file_csv", header=True))
```
This writes **one partition** (can be slow and bottlenecked).

### 6.4 Compression
Parquet is usually compressed by default (commonly snappy). You can set:

```python
spark.conf.set("spark.sql.parquet.compression.codec", "snappy")  # or zstd, gzip
```

For CSV:
```python
(df.write
   .mode("overwrite")
   .option("compression", "gzip")
   .csv("hdfs:///data/out/csv_gz", header=True))
```

---

## 7) Download (GET) from HDFS to local (when you need a local copy)

### 7.1 Download a file
```bash
hdfs dfs -get /data/input/myfile.csv ./myfile.csv
```

### 7.2 Download a directory
```bash
hdfs dfs -get /data/parquet/myfile_parquet ./myfile_parquet
```

### 7.3 From inside Python (driver-side)
```python
import subprocess
subprocess.run(["hdfs", "dfs", "-get", "/data/input/myfile.csv", "./myfile.csv"], check=True)
```

> Spark itself does not “download” distributed files to your laptop.  
> Spark reads data **in cluster** and processes it distributed.

---

## 8) “Small files problem” (HDFS + Spark)

HDFS is not efficient with millions of tiny files:
- Namenode memory pressure
- Slow listing / planning
- Poor performance

**Fix strategies**
- Merge small files into Parquet
- Write fewer larger partitions (`repartition`)
- Use reasonable partition sizes (often 128–512MB per file as a starting target)

---

## 9) Permissions & common errors

### Permission denied
```bash
hdfs dfs -ls /data
# check owner/group/perms
```

Fix (if you have rights):
```bash
hdfs dfs -chown -R user:group /data/input
hdfs dfs -chmod -R 770 /data/input
```

### “File not found” in Spark
- You used `file:///...` but driver cannot see that local file.
- Your HDFS path is wrong (missing leading `/` after scheme).
  - Correct: `hdfs:///data/input/file.csv`
  - Wrong: `hdfs://data/input/file.csv` (missing namenode host)

### Executors can’t read local path
Executors run on worker nodes. They **cannot** read your driver local disk path.

Use one of:
- Put file into HDFS first (`hdfs dfs -put`)
- Put file into shared storage mounted on all nodes
- Use `--files` or `SparkFiles` for small configs (not huge datasets)

---

## 10) Cheat sheet

### Upload local → HDFS
```bash
hdfs dfs -mkdir -p /data/input
hdfs dfs -put -f local.csv /data/input/
```

### Read from HDFS in PySpark
```python
df = spark.read.csv("hdfs:///data/input/*.csv", header=True, inferSchema=True)
```

### Write to HDFS in Parquet
```python
df.repartition(64).write.mode("overwrite").parquet("hdfs:///warehouse/mytable")
```

### Download HDFS → local
```bash
hdfs dfs -get /data/input/local.csv .
```

---

## Recommended workflow (for datasets)
1) Copy raw files to HDFS with `hdfs dfs -put`  
2) In Spark: read raw → write Parquet partitioned  
3) Use Parquet tables for all testing/ETL/SQL workloads

