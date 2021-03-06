---
title: Spark Thrift Server Basics and a History
layout: post
comments: True
tags:
 - Spark
 - Cassandra
 - SQL
 
---

Spark (SQL) Thrift Server is an excellent tool built on the HiveServer2 for allowing multiple remote 
clients to access Spark. It provides a generic JDBC endpoint that lets any client including BI tools
connect and access the power of Spark. Let's talk about how it came to be and why you should use it.

---

## Wait Thrift? I thought we got rid of that ....

TLDR: Spark Thrift Server is *not* related to the Cassandra Thrift Protocol.

Users of Cassandra who remember the good old days may have a gut reaction of "Thrift? 
I thought we got rid of that." Well let's start out by clarifying what `Thrift`
actually is. Apache Thrift is a [framework](https://thrift.apache.org/) which lets developers quickly 
develop RPC interfaces to their software. Basically, when developing a client-server application you 
want an easy way for the client to call functions on the server. Cassandra was one such application
which had clients (drivers) and a server (the Cassandra Server). The Cassandra Thrift Protocol 
refers to the original Cassandra protocol built upon the Apache Thrift Framework. 
Modern Cassandra now uses a unique native [protocol](https://www.datastax.com/dev/blog/binary-protocol) 
developed in-house for efficiency and performance. HiveServer also used a Thrift-based framework
to develop its original client server communication but this is unrelated to the old Cassandra 
thrift protocol.

## But you said HiveServer? This is just Hive right?

### A brief history of Hive and Spark

This is a bit of a complicated history, basically a ["Ship of Theseus"](https://en.wikipedia.org/wiki/Ship_of_Theseus) 
story. We start with our original server, which is almost completely Hive. Then over time Hive code is 
replaced, piece by piece, until almost none of the original code remains.

Spark originally started out shipping with Shark and SharkServer (a portmanteau of Spark and Hive). 
In those days there was a lot of Hive code in the mix. SharkServer was Hive, it parsed HiveQL, 
it did optimizations in Hive, it read Hadoop Input Formats, and at the end of the day it actually ran Hadoop style Map/Reduce jobs 
on top of the Spark engine. It was still [really cool at the time](https://github.com/amplab/shark/wiki/Shark-User-Guide) 
as it provided a way to utilize Spark without doing any functional programming. With only HQL you 
could access all the power of Spark. Unfortunately Map/Reduce and Hive were not ideal matches for the Spark 
ecosystem and all Shark development ended at [Spark 1.0](https://databricks.com/blog/2014/07/01/shark-spark-sql-hive-on-spark-and-the-future-of-sql-on-spark.html)
as Spark stared moving to more Spark-native expressions of SQL. 

Spark began replacing those various Hive-isms. Spark introduced a new representation for distributed tabular data, called 
[~~SchemaRDDs~~](https://github.com/apache/spark/blob/branch-1.0/sql/core/src/main/scala/org/apache/spark/sql/SchemaRDD.scala) 
[~~Dataframes~~](https://github.com/apache/spark/blob/branch-1.3/sql/core/src/main/scala/org/apache/spark/sql/DataFrame.scala) 
[DataSets](https://github.com/apache/spark/blob/branch-2.0/sql/core/src/main/scala/org/apache/spark/sql/Dataset.scala) ... naming is hard. 
And with that, a brand new Spark-native optimization engine known as [Catalyst](https://databricks.com/blog/2015/04/13/deep-dive-into-spark-sqls-catalyst-optimizer.html)! 
Catalyst, a [Tree Manipulation Framework](https://jaceklaskowski.gitbooks.io/mastering-apache-spark/spark-sql-catalyst.html), provided a basis for the query optimization present in everything from GraphFrames to
Structured Streaming. The advent of Catalyst meant that old Map/Reduce-style execution could be dropped, and instead, Spark-optimized execution plans
could be built and run. In addition, Spark released a new API which lets us build Spark-Aware interfaces 
called "DataSources" (like this [Cassandra one](https://github.com/datastax/spark-cassandra-connector/blob/master/spark-cassandra-connector/src/main/scala/org/apache/spark/sql/cassandra/CassandraSourceRelation.scala)).
The flexibility of DataSources ended reliance on Hadoop Input Formats (although they are still supported).
DataSources can tap directly into the query plans generated by Spark and perform predicate push-downs and other optimizations.

While all this was happening the Hive Parser was pulled and replaced with one a native [Spark Parser](https://github.com/apache/spark/tree/v2.1.1/sql/catalyst/src/main/scala/org/apache/spark/sql/catalyst/parser).
HQL is still accepted but the syntax has been greatly expanded. Spark SQL can now handle all of the [TPC-DS queries](http://spark.apache.org/releases/spark-release-2-0-0.html),
as well as a bunch of Spark-specific extensions. (There was a short period in development where you
had to pick between a 
[`HiveContext`](https://github.com/apache/spark/blob/v1.6.3/sql/hive/src/main/scala/org/apache/spark/sql/hive/HiveContext.scala) 
and [`SqlContext`](https://github.com/apache/spark/blob/v1.6.3/sql/core/src/main/scala/org/apache/spark/sql/SQLContext.scala) both of which had different parsers, but we don't talk about that anymore. 
Today all requests start with a [`SparkSession`](https://github.com/apache/spark/blob/v2.1.1/sql/core/src/main/scala/org/apache/spark/sql/SparkSession.scala)).
Now there is almost no Hive left in Spark. While the Sql Thrift Server is still built on
the [`HiveServer2`](https://github.com/apache/spark/blob/v2.1.1/sql/hive-thriftserver/src/main/scala/org/apache/spark/sql/hive/thriftserver/HiveThriftServer2.scala) code, 
almost all of the internals are now completely Spark-native.

## But why is the Spark Sql Thrift Server important?

I've written about this before; Spark Applications are 
[Fat]({% post_url 2017-2-3-Spark-Applications-Are-Fat %}). Each application is a complete 
self-contained cluster with exclusive execution resources. This is a problem if you want
multiple users to share the same pool of cluster resources. The Spark Thrift Server provides a 
single context with a well-defined external protocol. This means external users can simultaneously 
send requests for Spark work without any Spark dependencies. 

Spark Contexts are also unable to share cached resources amongst each other. This means that unless
you have a single Spark Context, it is impossible for multiple users to share a cached data. The
Spark Thrift server can be that "single context," providing globally-available cache.

The Thrift Server can also benefit from [Fair Scheduling](https://spark.apache.org/docs/latest/job-scheduling.html#fair-scheduler-pools). Fair
Scheduling means that user requests do not have to be answered in a "First in, First out" manner.
Instead, tasks from user queries can be interleaved. A long running query will not be able to 
 block a shorter query from completing.

Additionally, the Thrift Server provides a greater level of Security by limiting the domain of jobs 
that a user can run. The Thrift Server prohibits running generic JVM code. Only SQL can be 
processed and executed.

## How does the Spark Sql Thrift Server work?

The modern Thrift Server is a relatively simple application. A single `SparkSession` is started, and 
then on a loop it accepts new strings and executes them with a `.collect`. The results are recieved
from the cluster and then delivered to the requester. You can see in the [code](https://github.com/apache/spark/blob/v2.1.1/sql/hive-thriftserver/src/main/scala/org/apache/spark/sql/hive/thriftserver/SparkExecuteStatementOperation.scala#L231-L246)
that the basic execution is

```scala
result = sqlContext.sql(statement)
resultList = Some(result.collect())
```

with a bunch of formatting and other bells and whistles. End users connect via JDBC and then send
SQL strings. The strings are parsed and run using the same code you might use in a stand-alone
Spark Application. There are two options most users should be aware of:

### "Inception" or "Multiple Sessions"

[Docs](http://spark.apache.org/docs/latest/sql-programming-guide.html#upgrading-from-spark-sql-15-to-16)

```
spark.sql.hive.thriftServer.singleSession=false
```

Multiple clients connecting to the JDBC Server can either share the same Session or not. This basically
fits two different use-cases. Should users be able to access each other's configuration and registered 
functions? Or should every user act independently?

For example:

#### Single Session: 

```
User1 registers function and temporary views
User(2,3,4,5) use those functions and views
```

#### Multiple Session:

```
User 1 makes a private view of the data
User 2 makes a private view of the data
No user can see another's work or override their temporary catalog entries
This will *not* prevent users from editing the underlying sources
```


### "Mysterious OOMs and How to Avoid Them" or "Incremental Collect"

```
spark.sql.thriftServer.incrementalCollect=false
```

This internal/mostly undocumented feature is necessary for Business Intelligence tools or other
sources that request enormous result-sets through the Thrift Server. By default, `collect` is used as an
operation to get the results from Spark before they are fed back through JDBC. `collect` pulls data-sets 
completely into the driver's heap. This means that a JDBC request which returns a huge result-set will be 
placed completely in the heap of the Spark Sql Thrift Server. This can lead to Out Of Memory Errors(OOMs),
surprising users expecting the result-set to be paged through the Thrift Server small bits at a time. 
It is sometimes possible to avoid OOMs by increasing the `driver` heap size to fit the entire result-set,
but it is also possible to do some manual paging and have the same effect.

The setting `IncrementalCollect` changes the gather method from `collect` to `toLocalIterator`. 
`toLocalIterator` is a Spark action which only returns one Spark Partition's worth of data at a time. 
This can hurt performance but reduces the amount of RAM required on the Thrift Server heap -- from the 
entire result set down to only a single partition.

Remember that even with these considerations, if multiple users are making requests simultaneously each
request still requires one partition of data in the heap. Therefore it is still important
to control the number of concurrent users to avoid OOMs.

### Want to Learn More?

I hope this has been useful and please check out these additional blog posts for more information
on the Thrift Server. 

* [Jacek Laskowski's great reference manual for Spark](https://jaceklaskowski.gitbooks.io/mastering-apache-spark/content/spark-sql-thrift-server.html)
* [DataStax Documentation on Spark Sql Thriftserver](http://docs.datastax.com/en/dse/5.1/dse-dev/datastax_enterprise/spark/sparkSqlThriftServer.html)
* [Apache Spark Documentation on Spark Sql ThriftServer](https://spark.apache.org/docs/latest/sql-programming-guide.html#distributed-sql-engine)
* [The Raw Code itself](https://github.com/apache/spark/tree/master/sql/hive-thriftserver/src/main/scala/org/apache/spark/sql/hive/thriftserver)

One whole post about Spark without talking about or using Monads. Oops ruined it.

### Thanks for comments and notes

Marguerite Sheffer
Jaroslaw Grabowski
Jacek Laskowski
Brian Hess