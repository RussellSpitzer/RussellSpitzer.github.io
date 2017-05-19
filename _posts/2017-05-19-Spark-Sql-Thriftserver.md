---
title: Spark Thrift Server Basics and a History
layout: post
comments: True
tags:
 - Spark
 - Cassandra
 - SQL
 
---

Spark Sql ThriftServer is an excellent tool for allowing multiple remote clients to access
Spark. In provides a generic JDBC endpoint that lets any client including BI tools connect and
access the power of Spark. Let's talk about how it came to be and why you should use it.

---

## Wait Thrift? I thought we got rid of that ....

For users of Cassandra who remember the good old days there may be a gut reaction of "Thrift? 
I thought we got rid of that." Well let's start out by clarifying what `Thrift`"
actually is. Apache Thrift is a [framework](https://thrift.apache.org/) which lets developers quickly 
develop RPC interfaces to their software. Basically, you have a client-server application and you 
want an easy way for the client to call functions on the server. Cassandra was one such application
which had clients (drivers) and a server (the Cassandra Server.) The Cassandra Thrift Protocol 
refers to the original protocol with the Apache Thrift Framework used for all client operations. Modern
Cassandra now uses a unique native [protocol](https://www.datastax.com/dev/blog/binary-protocol) 
developed in house for efficiency and performance. HiveServer also used a Thrift based framework
to develop it's original client server communication but this is unrelated to the old Cassandra 
 thrift protocol.

Bottom line: Spark Thrift Server is not related to the Cassandra Thrift Protocol.


## But Hive? This is just Hive right? I heard it was built on HiveServer.

### A brief history of Hive and Spark

This is a bit of a complicated history, basically a ship of Theseus story. We start with our original
server which is almost completely Hive. Then, piece by piece, replacing hive until until almost 
nothing of the original code remains. 

Spark originally started out shipping with something called Shark and SharkServer. In those days there was 
a lot of Hive code in the mix. SharkServer was Hive, it parsed Hive, it did optimizations in Hive, 
and at the end of the day it ended up actually ended up running Hadoop style Map/Reduce jobs 
just on top of the Spark engine. It was still [really cool at the time](https://github.com/amplab/shark/wiki/Shark-User-Guide) 
as it provided a way to utilize Spark without doing any functional programming, just using the HQL
that you already knew. Unfortunately Map/Reduce and Hive were not ideal matches for the Spark 
ecosystem and all development ended at [Spark 1.0](https://databricks.com/blog/2014/07/01/shark-spark-sql-hive-on-spark-and-the-future-of-sql-on-spark.html)
 as Spark stared moving to more Spark native expressions of SQL. 

Spark began replacing those various Hive-isms. Spark introduced a new great representation for 
distributed data with a schema called 
[~~SchemaRDDs~~](https://github.com/apache/spark/blob/branch-1.0/sql/core/src/main/scala/org/apache/spark/sql/SchemaRDD.scala) 
[~~Dataframes~~](https://github.com/apache/spark/blob/branch-1.3/sql/core/src/main/scala/org/apache/spark/sql/DataFrame.scala) 
[DataSets](https://github.com/apache/spark/blob/branch-2.0/sql/core/src/main/scala/org/apache/spark/sql/Dataset.scala) ... naming is hard. 
And with that a brand new Spark native optimization engine known as [Catalyst](https://databricks.com/blog/2015/04/13/deep-dive-into-spark-sqls-catalyst-optimizer.html)! 
The old Map/Reduce style execution could be dropped and instead Spark optimized execution plans
could be built and run. In addition we get this new api which lets us build Spark Aware interfaces 
called DataSources (like this [Cassandra one](https://github.com/datastax/spark-cassandra-connector/blob/master/spark-cassandra-connector/src/main/scala/org/apache/spark/sql/cassandra/CassandraSourceRelation.scala)) instead of 
just relying on Hadoop/HiveInputFormats. DataSources could tap directly into the query plans generated
by Spark and perform push-downs and optimizations.

While all this is happening the Hive Parser gets pulled and replaced with one completely in [Spark](https://github.com/apache/spark/tree/v2.1.1/sql/catalyst/src/main/scala/org/apache/spark/sql/catalyst/parser),
HQL is still accepted but the syntax expands and expands. SparkSql can now handle all of [TPC-DS queries](http://spark.apache.org/releases/spark-release-2-0-0.html)
as well as a bunch of Spark specific extensions. (There was a short period in development where you
had to pick between a 
[`HiveContext`](https://github.com/apache/spark/blob/v1.6.3/sql/hive/src/main/scala/org/apache/spark/sql/hive/HiveContext.scala) 
and [`SqlContext`](https://github.com/apache/spark/blob/v1.6.3/sql/core/src/main/scala/org/apache/spark/sql/SQLContext.scala) both of which had different parsers but we don't talk about that anymore.) 
Now all of this goodness is accessible through a [`SparkSession`](https://github.com/apache/spark/blob/v2.1.1/sql/core/src/main/scala/org/apache/spark/sql/SparkSession.scala)
So now there is almost no Hive left in Spark. While the Sql Thrift Server is still built on
the [`HiveServer2`](https://github.com/apache/spark/blob/v2.1.1/sql/hive-thriftserver/src/main/scala/org/apache/spark/sql/hive/thriftserver/HiveThriftServer2.scala) code, 
almost all of the internals are now completely Spark native.

## But why is it important?

I've written about this before, Spark Applications are 
[Fat]({% post_url 2017-2-3-Spark-Applications-Are-Fat %}). Each application is a complete 
self-contained cluster complete with exclusive execution resources. This is an issue if you want
multiple users to share the same pool of cluster resources. The Spark Thrift Server provides a 
single context with a well defined protocol. This means external users can all send requests
to have Spark work done without any Spark dependencies and fully utilize a cluster's resources. 

Spark Contexts are also unable to share cached resources amongst each other. This means that unless
you have a single Spark Context it is impossible for multiple users to share a cached table. The
Spark Thrift server can be that single context, providing globally available cached data.

Additionally the ThriftServer provides additional levels of Security by limiting the incoming jobs 
that a user can run. Instead of being able to run generic JVM code, only SQL is allowed to to be 
processed and executed.

## How it works?

The modern ThriftServer is relatively simple application. A single `SparkSession` is started and 
then on a loop it accepts new strings and executes them with a `.collect`. The results are then 
sent back to the requester. You can see in the [code](https://github.com/apache/spark/blob/v2.1.1/sql/hive-thriftserver/src/main/scala/org/apache/spark/sql/hive/thriftserver/SparkExecuteStatementOperation.scala#L231-L246), 
the basic execution is

```scala
result = sqlContext.sql(statement)
resultList = Some(result.collect())
```

with a bunch of formatting and other bells and whistles. End users connect via JDBC and then send
SQL strings. The strings are parsed and run using the same code you might use in a stand alone
Spark Application. There are two options I think most users should be aware of:


### Multiple Sessions

[Docs](http://spark.apache.org/docs/latest/sql-programming-guide.html#upgrading-from-spark-sql-15-to-16)

```spark.sql.hive.thriftServer.singleSession=false```

Multiple clients connecting to the JDBC Server can either share the same Session or they can each
have a new session on connection. This basically fits two different usecases. Should users be able
to access each other's configuration and registered functions? Or should every user act independently
of another.

For example

Single Session: 
```
User1 registers function and temporary views
User(2,3,4,5) uses those functions and views
```

Multiple Session:
```
User 1 makes a private view of the data
User 2 makes a private view of the data
No user can see another's work or override their catalogue entries
This will *not* prevent users from editing the underlying sources
```


### Incremental Collect

```spark.sql.thriftServer.incrementalCollect=false```

This internal/mostly undocumented feature is necessary for BI tools or other other sources that
request enormous result sets through the ThriftServer. If you noticed before `collect` is used as an
operation to get the results before they are fed back through JDBC. `collect` pulls datasets completely
into the driver's heap. This means that a JDBC request which returns a huge result set will be 
placed completely in the heap of the Spark Sql ThriftServer. This can lead to a lot of OOMs which 
can be inscrutable to those users expecting the resultset to be paged through the ThriftServer 
small bits at a time. It is sometimes possible to avoid this by increasing the `driver` heap size
to fit the entire result set but it is possible to do some rough paging.

The setting called `IncrementalCollect` changes the gather method from `collect` to `toLocalIterator`. 
`toLocalIterator` is a Spark action which only requests and returns the result of a job 1 Spark 
Partition at a time. This can have some performance impacts but reduces the amount 
of RAM required on the heap from the entire result set down to only a single partition's worth.

Remember that even with these considerations, if multiple users are making requests simultaneously
it is possible for all of their partitions to be requested simultaneously so the number of concurrent
users should be controlled or result sizes limited.

### Want to Learn More?

I hope this has been useful and please check out these additional blog posts for more information
on the ThriftServer

* [Jacek Laskowski's great reference manual for Spark](https://jaceklaskowski.gitbooks.io/mastering-apache-spark/content/spark-sql-thrift-server.html)
* [DataStax Documentation on Spark Sql Thriftserver](http://docs.datastax.com/en/dse/5.1/dse-dev/datastax_enterprise/spark/sparkSqlThriftServer.html)
* [Apache Spark Documentation on Spark Sql ThriftServer](https://spark.apache.org/docs/latest/sql-programming-guide.html#distributed-sql-engine)
* [The Raw Code itself](https://github.com/apache/spark/tree/master/sql/hive-thriftserver/src/main/scala/org/apache/spark/sql/hive/thriftserver)