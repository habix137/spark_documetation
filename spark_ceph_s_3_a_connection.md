# Connecting Apache Spark to Ceph Object Storage via S3A

This guide documents how to configure an Apache Spark standalone cluster to read and write data from a Ceph RGW (RADOS Gateway) endpoint using the `s3a://` protocol.

---

## Cluster Overview

- **Spark Mode**: Standalone
- **Nodes**: 1 master, 2 workers
- **Java Libraries Directory**: `/opt/spark/jars`
- **Library JARs**:
  - `hadoop-aws-3.4.1.jar`
  - `bundle-2.25.60.jar`
- **Spark Configuration Directory**: `/opt/spark/conf/`

---

## Required JARs for S3A Support

Place the following libraries on **all nodes (master and workers)**:

```bash
/opt/spark/jars/hadoop-aws-3.4.1.jar
/opt/spark/jars/bundle-2.25.60.jar
```

These libraries enable Spark to communicate with S3-compatible APIs such as Ceph RGW.

---

## S3A Configuration (spark-defaults.conf)

Edit the file `/opt/spark/conf/spark-defaults.conf` on **all nodes** and add the following lines:

```properties
spark.hadoop.fs.s3a.endpoint                 http://rwg-endpoint-ip:port
spark.hadoop.fs.s3a.path.style.access        true
spark.hadoop.fs.s3a.connection.ssl.enabled   false
spark.hadoop.fs.s3a.endpoint.region          us-east-1
spark.hadoop.fs.s3a.aws.credentials.provider org.apache.hadoop.fs.s3a.SimpleAWSCredentialsProvider
```

> ✅ Replace `rwg-endpoint-ip:port` with the actual IP address and port of your Ceph RGW (usually `8080`).

---

## Example Usage in PySpark

To read a file from a Ceph bucket:

```python
spark.read.csv("s3a://mybucket/myfile.csv")
```

To write back:

```python
df.write.csv("s3a://mybucket/output/")
```

---

## Notes

- You must also pass AWS credentials (access key and secret key) in your Spark code or set them via environment variables or configuration.
- Ensure Ceph RGW is reachable from Spark nodes over the specified endpoint.
- If SSL is enabled in Ceph, change `spark.hadoop.fs.s3a.connection.ssl.enabled` to `true`.

---

## Tested With

- **Hadoop AWS Version**: 3.4.1
- **Spark Version**: Compatible with Hadoop 3.x
- **Ceph Version**: Pacific / Quincy (with RGW enabled)

