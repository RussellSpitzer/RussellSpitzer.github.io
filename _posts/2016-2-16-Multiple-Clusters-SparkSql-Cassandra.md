---
title: Utilizing Multiple C* Clusters using the Spark Cassandra Connector Part II
layout: post
comments: True
tags:
 - Spark
 - Cassandra
 - Scala
 - SparkSQL
 
---

---
Talking to Multiple Clusters, Now with Spark SQL 

---

I previously wrote up a small example about using multiple `CassandraConnector` options to write
to multiple Clusters but the same thing can be done with Spark SQL.

Here is the code for using pure RDDs 

#### Example of reading from one cluster and writing to another with RDDS

```scala
import com.datastax.spark.connector._
import com.datastax.spark.connector.cql._

import org.apache.spark.SparkContext


def twoClusterExample ( sc: SparkContext) = {
  val connectorToClusterOne = CassandraConnector(sc.getConf.set("spark.cassandra.connection.host", "127.0.0.1"))
  val connectorToClusterTwo = CassandraConnector(sc.getConf.set("spark.cassandra.connection.host", "127.0.0.2"))

  val rddFromClusterOne = {
    // Sets connectorToClusterOne as default connection for everything in this code block
    implicit val c = connectorToClusterOne
    sc.cassandraTable("ks","tab")
  }

  {
    //Sets connectorToClusterTwo as the default connection for everything in this code block
    implicit val c = connectorToClusterTwo
    rddFromClusterOne.saveToCassandra("ks","tab")
  }

}
```

#### Example of reading from one cluster and writing to another with DataFrames


```scala
import com.datastax.spark.connector._
import com.datastax.spark.connector.cql._

import org.apache.spark.SparkContext

sqlContext.setConf("ClusterOne/spark.cassandra.connection.host", "127.0.0.1")
sqlContext.setConf("ClusterTwo/spark.cassandra.connection.host", "127.0.0.2")

//Read from ClusterOne
val dfFromClusterOne = sqlContext
  .read
  .format("org.apache.spark.sql.cassandra")
  .options(Map( 
    "cluster" -> "ClusterOne",
    "keyspace" -> "ks",
    "table" -> "tab
    ))
  .load
  
//Write to ClusterTwo
val dfFromClusterOne
  .write
  .format("org.apache.spark.sql.cassandra")
  .options(Map( 
    "cluster" -> "ClusterTwo",
    "keyspace" -> "ks",
    "table" -> "tab
    ))
  .save
}
```

Like the `RDD` example we are actually making two different CassandraConnectors but here we do it
by specifying their details in SparkSql Cluster configurations. This is done with a 
"Cluster/property" format but this should be improved in 
[SPARKC-289](https://datastax-oss.atlassian.net/browse/SPARKC-289) with some helper functions. For
now this is the way to go.

```scala
sqlContext.setConf("ClusterOne/spark.cassandra.connection.host", "127.0.0.1")
sqlContext.setConf("ClusterTwo/spark.cassandra.connection.host", "127.0.0.2")
```

This will internally make two Cluster configurations, one for "ClusterOne" and one for "ClusterTwo".
Each of these will make their own connection to their respective Clusters.

Then we performing our `DataFrame` operations we need to specify which Cluster we are using. This is
done via an Option which is passed to the read or write operation.

```scala
//Read from ClusterOne
val dfFromClusterOne = sqlContext
  .read
  .format("org.apache.spark.sql.cassandra")
  .options(Map( 
    "cluster" -> "ClusterOne",  // << The Cluster Config we will use to Read
    "keyspace" -> "ks",
    "table" -> "tab"
    ))
  .load
```

The above code generates a DataFrame sourced from the first Cluster. The configuration for reading
is not seen by other operations so we don't need to do any kind of code blocking here like we did
in the RDD operation.

When writing we just specify the alternate Cluster

```scala
val dfFromClusterOne
  .write
  .format("org.apache.spark.sql.cassandra")
  .options(Map( 
    "cluster" -> "ClusterTwo", // << The Cluster Config we use to Write
    "keyspace" -> "ks",
    "table" -> "tab"
    ))
  .save
```

And we have successfully read from 127.0.0.1 and written to 127.0.0.2
