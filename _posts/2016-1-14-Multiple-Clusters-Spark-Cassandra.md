---
title: Utilizing Multiple C* Clusters using the Spark Cassandra Connector
layout: post
comments: True
tags:
 - Spark
 - Cassandra
 - Scala
 
---

---
Most folks don't know that the Spark Cassandra Connector is actually able to connect to multiple
Cassandra clusters at the same time. This allows us to move data between Cassandra clusters or 
even manage  multiple clusters from the same application (or even the spark shell)

---

Operations within the Spark Cassandra Connector are goverened by `CassandraConnector` objects.
The default `CassandraConnector` is created based on the parameters in your `SparkConfiguration` and
the parameters passed on the command line of the form `spark.cassandra.*`. But this default `CassandraConnector`
does not have to be the only connection configuration used.

To use a different connection configuration, the simplest thing to do is to specify a new code
block with an implicit `CassandraConnector` defined in that block. The implicit will then be used
by all of the operations within that block. This works in the shell as well.

####Example of reading from one cluster and writing to another

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

Within this example we make two different `CassandraConnector` objects. Each of them pulls down the
defaults set in the `SparkContext` but overrides the `spark.cassandra.connection.host` parameter. 

```scala
 val connectorToClusterOne = CassandraConnector(sc.getConf.set("spark.cassandra.connection.host", "127.0.0.1"))
 val connectorToClusterTwo = CassandraConnector(sc.getConf.set("spark.cassandra.connection.host", "127.0.0.2"))
```

At this point we haven't changed anything about the default connection configuration, any operations
will still use the default config. So to choose one of these to do something we need to open up a 
code block and declare it as the implicit `CassandraConnector` in that block

```scala
  val rddFromClusterOne = {
    // Sets connectorToClusterOne as default connection for everything in this code block
    implicit val c = connectorToClusterOne
    sc.cassandraTable("ks","tab")
  }
```

Within this block the `cassandraTable` call will use the implicit `CassandraConnector` c which is
`connectorToClusterOne`. The RDD that is created will point at the cluster in `127.0.0.1` regardless
of what else we do elsewhere in the code.

```scala
  {
    //Sets connectorToClusterTwo as the default connection for everything in this code block
    implicit val c = connectorToClusterTwo
    rddFromClusterOne.saveToCassandra("ks","tab")
  }
```

The brackets here start our next code block. This allows us to specify a new implicit `CassandraConnector`
this will change the operation of the `saveToCassandra` method to point towards `127.0.0.2`. The 
`rddFromClusterOne` is already setup and will not be affected by the new implicit connector. When Spark
hits the `saveToCassandra` call, an action will begin and data will be pulled from the first cluster
and placed in the second.
