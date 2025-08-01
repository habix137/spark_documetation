
# Apache Spark Standalone Installation Guide

## 1. Install Java

```bash
sudo apt update
sudo apt install openjdk-11-jdk -y
```

## 2. Install Spark

Download and extract Spark:

```bash
wget https://dlcdn.apache.org/spark/spark-3.5.4/spark-3.5.4-bin-hadoop3.tgz
tar xvf spark-3.5.4-bin-hadoop3.tgz
mv spark-3.5.4-bin-hadoop3 /opt/spark
```

## 3. Set Environment Variables

Add the following lines to your `~/.bashrc`:

```bash
nano ~/.bashrc
```

```bash
# Spark Environment Variables
export SPARK_HOME=/opt/spark
export PATH=$PATH:$SPARK_HOME/bin:$SPARK_HOME/sbin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
```

Reload the shell:

```bash
source ~/.bashrc
```

## 4. Run Spark in Standalone Mode

```bash
start-master.sh
start-worker.sh spark://localhost:7077
```

## 5. Verify Installation

```bash
spark-shell
```

### Sample Scala Code

```scala
val data = sc.parallelize(Seq("Hello", "World", "Hello", "Spark"))
val counts = data.map(word => (word, 1)).reduceByKey(_ + _)
counts.collect().foreach(println)
```

## 6. Install PySpark

```bash
sudo apt install pip
pip install pyspark
```

Add to `~/.bashrc`:

```bash
export PYSPARK_PYTHON=/usr/bin/python3
```

### Sample Python Code

```python
rdd = sc.parallelize([1, 2, 3, 4, 5])
rdd_squared = rdd.map(lambda x: x * x)
print(rdd_squared.collect())
```

## 7. Configure Spark Master and Workers

Backup and configure `spark-env.sh`:

```bash
cd /opt/spark/conf/
cp spark-env.sh.template spark-env.sh
```

Edit `spark-env.sh`:

```bash
export SPARK_MASTER_HOST=172.27.8.92
export SPARK_MASTER_PORT=7077
export SPARK_WORKER_CORES=4
export SPARK_WORKER_MEMORY=4g
```

### Update `/etc/hosts`

```bash
nano /etc/hosts
```

Example:

```
127.0.0.1 localhost
172.27.8.92 master
172.27.8.95 worker2
172.27.8.94 worker3
```

and also in each workers add master ip in /etc/hosts
```bash
172.27.8.92 master
```


### Configure Workers

```bash
cp /opt/spark/conf/workers.template /opt/spark/conf/workers
nano /opt/spark/conf/workers
```

```
worker1
worker2
worker3
```

## 8. Start Spark Services

Start Master:

```bash
start-master.sh
```

Start Worker:

```bash
start-worker.sh spark://<master_ip_address>:7077
```

Or use:

```bash
start-workers.sh
```

## 9. Spark Monitoring

Master Web UI: `http://<master_ip>:8080`  
Worker Web UI: `http://<worker_ip>:8081`

Check Worker status:

```bash
curl http://localhost:8080/json/
```

## 10. Client Configuration

```bash
cd /opt/spark/conf
cp spark-defaults.conf.template spark-defaults.conf
nano spark-defaults.conf
```

Add:

```
spark.master spark://<MASTER_IP>:7077
spark.driver.host <CLIENT_IP>
```

```bash
cp spark-env.sh.template spark-env.sh
nano spark-env.sh
```

Add:

```bash
SPARK_MASTER_HOST=<MASTER_IP>
SPARK_LOCAL_IP=<CLIENT_IP>
```

Submit Spark job:

```bash
spark-submit --master spark://<master_ip>:7077 --executor-memory 2g --driver-memory 2g <program_name>
```

## 11. Dynamic Allocation (Optional)

`spark-defaults.conf`:

```
spark.dynamicAllocation.enabled=true
spark.dynamicAllocation.minExecutors=1
spark.dynamicAllocation.maxExecutors=10
spark.dynamicAllocation.initialExecutors=2

# Or disable
spark.dynamicAllocation.enabled=false
```
