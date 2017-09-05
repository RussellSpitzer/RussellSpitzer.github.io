---
title: How Spark Data Locality Works
layout: post
comments: True
tags:
 - Spark
 - Locality
 - Cassandra
 
---

Apache Spark is the data processing system that lets you have in-memory analytics and data locality, but how
does that work? How does Spark know where the data is? The Spark UI is full of messages talking about 
NODE_LOCAL, ANY or PROCESS_LOCAL. What are these things and how do they get set? Let's explore how 
Spark handles data locality when processing data.

---

## Background

### How the Spark Scheduler Work

Inside of every Spark application there is an extremely important class called the [DAGScheduler](https://github.com/apache/spark/blob/master/core/src/main/scala/org/apache/spark/scheduler/DAGScheduler.scala). 
You have probably seen references to this in `Task Failed Exceptions` or any other runtime exception. 
DAGScheduler stands for the Direct Acyclic Graph Scheduler and is the core of actually getting any 
work done in a Spark Cluster. This is the class that actually takes "tasks" from a Spark application 
and sends them out to Executors to get processed. This is why whenever a remote Executor fails to run a 
task, `DAGScheduler` is going to end up in the stack trace.

When our code calls a Spark action like `collect` or `saveToCassandra` the request ends up in the 
`DAGScheduler` . That action ends up submitting a job to the DAGScheduler which transforms the RDD
action and all it's dependencies into a series of stages made up of tasks. Each task can be 
thought of as a series of functions applied to a single Spark partition of data.

The first hint of locality comes in a little function called [submitMissingTasks](https://github.com/apache/spark/blob/aba9492d25e285d00033c408e9bfdd543ee12f72/core/src/main/scala/org/apache/spark/scheduler/DAGScheduler.scala#L960). This
function will be used whenever there is work to be done that has not yet been done. One of the first
things it does is to probe the head RDD for a partition level piece of information called `preferredLocation`. 
This list of strings is the only message that the underlying RDD can send to tell the scheduler
about data locality.

### Who Decides Locality? PreferredLocation

PreferredLocation is one of the basic components of an RDD. See the clearly labeled [java doc](https://github.com/apache/spark/blob/aba9492d25e285d00033c408e9bfdd543ee12f72/core/src/main/scala/org/apache/spark/rdd/RDD.scala#L137)
which states that this function can be ```Optionally overridden by subclasses to specify placement preferences.``` RDD 
designers, like the authors of the [DSE Spark Cassandra Connector](https://github.com/datastax/spark-cassandra-connector), can use this function to indicate that a particular Spark
partition is located on a particular [IP address or set of IP addresses](https://github.com/datastax/spark-cassandra-connector/blob/master/spark-cassandra-connector/src/main/scala/com/datastax/spark/connector/rdd/CassandraTableScanRDD.scala#L284-L285). 
Hadoop RDDs can use the location of the underlying HDFS data to indicate where their partitions can be run. 
Kafka RDDs similarly indicate that a Kafka Spark partition should getting data from the same machine hosting
that [Kafka Topic](https://github.com/apache/spark/blob/823baca2cb8edb62885af547d3511c9e8923cefd/external/kafka-0-10-sql/src/main/scala/org/apache/spark/sql/kafka010/KafkaSourceRDD.scala#L118-L121).
In the case of Spark Streaming jobs using Receivers, every partition is marked as local to the node 
where the receiver is running and has stored the data. Other RDDs won't implement this function at 
all since they are assumed to be working in place on data that comes from a parent RDD.   

The important thing to remember is the decision on what is "Local" for any given Spark Task is going to be solely based upon 
what the implementer of the RDD decided would be "local" and whether or not that "Set\[String\]" contains a match
for any of the executors currently running.

### Four Flavors of Locality 

The `DagScheduler` passes tasks to a `TaskScheduler` which in turn makes a `TaskSet` which gets to
actually decided which tasks are run at which times.  Inside the `TaskSet` tasks are sorted on a
priority order based on 4 Locality levels. 
    
    * PROCESS_LOCAL // This task will be run within the same process as the source data
    * NODE_LOCAL // This task will be run on the same machine as the source data
    * RACK_LOCAL // This task will be run in the same rack as the source data
    * NO_PREF (Shows up as ANY)// This task cannot be run on the same process as the source data or it doesn't matter 
    
When actually running tasks, those with the highest level of locality `PROCESS-LOCAL` are assigned 
first, then the `NODE-LOCAL` tasks and finally the `RACK_LOCAL` tasks.  But what if we have `NODE-LOCAL`
tasks for a specific node and run out of execution space on that machine?

### When to give up on locality `spark.locality.wait`

Imagine we are pulling data from a co-located Kafka node in a 3 node Spark Cluster. The Kafka is running
on machine `A` of Spark nodes `A`,`B`,and `C` All of the data  will be marked as being `NODE_LOCAL` to a Node `A`.
This means once every core on `A` is occupied we will be left with tasks whose preferred location is `A` but
we only have execution space on `B` and `C`. Spark only has two options, wait for cores to become available
on `A` or downgrade the locality level of the task and try to find a space for it and take whatever
penalty there is for running non-local.
 
The `spark.locality.wait` parameter describes how long to wait before downgrading tasks that could 
potentially be run a higher locality level to a lower level. This parameter is basically our estimate of how
much time waiting for locality is worth. The default is 3 seconds which means that in our Kafka example,
once our co-located node `A` is saturated with tasks, our other machines `B` and `C`  will stand idle 
for 3 seconds before tasks which could have been `NODE_LOCAL` are downgraded to `ANY`* and
run [(code reference)](https://github.com/apache/spark/blob/823baca2cb8edb62885af547d3511c9e8923cefd/core/src/main/scala/org/apache/spark/scheduler/TaskSetManager.scala#L579-L585).

\* If there is 'A' and 'C' were specified to be in the same rack, the locality would be downgraded to 
`RACK_LOCAL`  first and run on 'C' instead. Once `C` was full it would wait another 3 seconds before
doing the final downgrade to `ANY` and run on `B`.


## Conclusion

In a streaming applications, I've seen many users just set `spark.locality.wait` to 0 to insure
that all tasks are being worked on immediately. A batch window of 5 seconds makes the default wait of 3 
seconds excruciatingly long. After all, waiting 60% of your batch time before starting work is probably
inefficient.  In other applications I've seen locality be extremely important and the `wait` time 
increased to near infinite. The correct setting will depend on the latency goals and locality benefit 
for your particular application. There are even finer grained controls if you would like to make the
delays between different [levels of locality](http://spark.apache.org/docs/latest/configuration.html)
weighted differently.

With these controls it should be easy to tune your application for maximum throughput.


Thanks to Gerard Maas For Reviewing!
