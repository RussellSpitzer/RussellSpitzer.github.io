---
title: Is the Spark Cassandra Connector Asynchronous / How Spark Works
layout: post
comments: True
tags:
 - Spark
 - Cassandra
 - Scala
 - Concurrency

---

Are the Spark Cassandra Connector Api's Async?

Short Answer: No

Are the underlying requests made to Cassandra Async?

Yes

This question led me into an extremely long email where I began to think
how best to describe how Spark works and how concurrency fits into
that.

---

## How Spark Works:
Spark is much higher level an abstraction than Hadoop based Map Reduce 
code (although Map Reduce does have some higher level input format apis 
see [CqlStorage](https://github.com/apache/cassandra/blob/trunk/src/java/org/apache/cassandra/hadoop/cql3/CqlInputFormat.java)).
Spark uses a high level RDD/DataSet interface that hides much of the
internal logistics of distributed computing.


The application that the end user writes is the Spark Driver, basically 
the manager of the distributed system. From there you call on a series of
APIs to create RDDs (or DataFrames). 

For example the call `sc.cassandraTable` returns instantly with an RDD 
which represents the operations which map data from C* into a RDD. The 
RDD is basically a mapping of the C* into discrete independent blocks of 
data called Spark Partitions. This call takes milliseconds and reads NO 
data from Cassandra (recent versions of the SCC do schema checks but 
mostly this is lazy). Transformation functions are then applied to RDDs 
which in turn yield more RDDs (again instantaneously). This should be 
familiar to people who have used fluent APIs before. For example

```scala
val x = sc.cassandraTable(ks, table)
  .map( this => that )
  .filter(that > something)
  .map(that => complicatedFunction(that))
```
Would instantly return an RDD of type *that* which would represent the 
complete set of operations required to transform the entire table (ks, table) 
into our objects of type *that*. This RDD is lazily constructed and no 
data is actually pulled from Cassandra. All that is made is the plan
of work that is required to get to the endpoint. This is a common 
pattern with Spark. Lazily constructed objects that only  do work when 
absolutely required. These functions above are called http://spark.apache.org/docs/latest/programming-guide.html#transformations 
Only when an [action](http://spark.apache.org/docs/latest/programming-guide.html#actions) 
function is applied (like collect or saveToCassandra) does any 
 distributed work actually happen. 

So if you then call

```scala
x.saveToCassandra
```

The metadata for constructing and computing the RDD is shipped by the 
driver to various spark executors (remote JVMs), each executor core will 
work on one partition at a time until it reaches a shuffle stage (Shuffling 
is a little more complicated but basically blocks go from one executor 
to another). This means the the above code will be executed in parallel 
running items through the full chain of operations in multiple parallel 
threads on many different machines.
```
Reading from C* (asynchronously) 
  --> Passing through a Filter 
  --> Applying some weird function 
  --> Save back to Cassandra
```

Each executor core will be running through this chain with it's own block 
of data, each command (passing through a filter/ applying some function) 
both taking and emitting an iterator so that objects are pulled through 
as quickly as possible. At no time during this process is any data 
(except for the metadata about task failure or success) sent back to the
 Spark Driver application. 

If one Core finishes on a partition, the driver will assign it another 
block to work on. All of this happens automatically and is in not 
something that the Spark API user has to be aware of.

## Back to why the Spark Cassandra Connector API is Sync

During the whole process the Spark Driver is blocked on awaiting the 
result of this "Job". Being asynchronous in waiting for this scheduling 
to complete can only benefit you if you are running less partitions than 
the entire Spark Cluster can handle at max or if you are using the 
[Fair Scheduler](http://spark.apache.org/docs/latest/job-scheduling.html#fair-scheduler-pools) within Spark. 

In those cases you could use the scala Future api to start scheduling 
multiple sets of distributed work at the same time. This is usually not 
a priority for most Spark Application writers as they usually have far 
more work than their cluster can do (Partitions >>> number of cores.) and 
they aren't using their Driver Applications to do any processing since none 
of the data is actually present on the local machine.

If you had to jobs you wanted to run at the time you could do something 
like example

```scala
AwaitAll (
Future { sc.cassandraTable.map.saveToCassandra},
Future { sc.cassandraTable.map.saveToCassandra}
)
```

AwaitAll is a construct we made up in our testing code but is basically 
await(Future.Sequence(args:_*, indefinitely)}


Will start two separate spark jobs being scheduled in parallel but if 
the first job get's all it's tasks into the queue and there are no cores 
left then the jobs will run FIFO. The Fair Scheduler would interleave 
tasks between the two jobs. 

Usually I recommend folks use the SparkSqlThriftServer or the [Spark
Job Server](https://github.com/spark-jobserver/spark-jobserver) if they 
are doing that kind of scheduling.

## Being Async Manually within Spark Operations 

The SCC also allows you to use any Java driver API internally within your
 Spark Job including the async APIs. Usually I recommend that users do 
 something like

```scala
val cc =  CassandraConnector(sc.getConf)
RDD.mapPartitions( it =>
   cc.withSessionDo( session => 
     it.map( rddElement =>  session.something here)))
```

If they have an complicated command they would like to run. But this is 
usually not needed as the normal apis like CassandraTable implement 
basic asynchronous reading and writing under hood.

## The Driver Functions without any of Distributed Data Moved to It

There is only a single type of task execution process in Spark, the Spark 
Executor. Executors only need to communicate with each other during 
"Shuffles." During a shuffle, each machine will if possible directly 
ship blocks to the nodes which requires them. If the amount of memory 
required to store the information in the partition exceeds the available 
ram, the partition will to disk. The Executor's local disk will the hold
 the partition till it is ready to be shipped to another Executor.

None of this information except for the location of the completed blocks
is going back to the Spark Driver. This is because all of this communication 
is done Executor to Executor with the Driver only handling orchestration 
(where the blocks are and who should get what blocks.) All the shuffling
 and disk and network I/O is internal within the Spark Executor and is 
 not a part of User code. The Executor process does both mapping and 
 reducing work (as well as arranging shuffling.) None of this is directly exposed.
 
## Why is Save To Cassandra the only Blocking Call

Only Spark Actions on an RDD are blocking (as they wait for the job to 
complete to proceed) and saveToCassandra is the only action the Spark
 Cassandra Connector provides. Functions like cassandraTable or select 
 or joinWithCassandraTable are all Transformations which generate new 
 RDDs with dependencies linking to their predecessors. Because of this,
  they don't actually do any work on the cluster and they return instantly.

All of the other actions you could do on an RDD are Spark APIs so the
the connector could not wrap and making them non-blocking. Although it 
would still be trivial to wrap them in futures if you wanted to run 
multiple jobs at the same time.

## Conclusion and More Resources

Spark is a really fun technology so take a look at some of the following 
videos and blog posts to get more accustomed to it and 
how it works with Cassandra. 

[http://spark.apache.org/docs/latest/programming-guide.html]

Paco Talking about Apache Spark (Warning 6 awesome hours)
[https://www.youtube.com/watch?v=EuWDz2Vb1Io]

[https://academy.datastax.com/resources/how-spark-cassandra-connector-reads-data]

[https://academy.datastax.com/resources/how-spark-cassandra-connector-writes-data]

[http://www.slideshare.net/JenAman/spark-and-cassandra-2-fast-2-furious-63064852]

Cassandra and Spark optimizing For Data Locality
[https://www.youtube.com/watch?v=ikCzILOpYvA]

And there is a whole set of associated documentation and training here

[https://academy.datastax.com/resources/getting-started-apache-spark-and-cassandra]
