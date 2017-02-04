---
title: Ordering with saveToCassandra
layout: post
comments: True
tags:
 - Spark
 - DSE
 - Idempotency 
 
---

Responding to a question on Stack Overflow
http://stackoverflow.com/questions/42020173/savetocassandra-is-there-any-ordering-in-which-the-rows-are-written/42031425#42031425

To paraphrase the question: "I have two records which should arrive in order, but the last one is
overwritten by the first. Does saveToCassandra respect RDD order?"

----

## Is there an order to SaveToCassandra? 

Within a single task execution is deterministic but that may not be the
ordering you are expecting. There are two things to think about here.

1. RDDs are made of Spark Partitions and the order of execution for these partitions is dependent on system conditions. Having different numbers of cores, heterogeneous machines or executor failures could all change execution order. Two Spark Partitions with data for the same Cassandra Partition could be executed in any order based on the system.
2. For each Spark partition, records are batched in the same order as they are received but this does not necessarily mean that they will be *sent to Cassandra* in the same order. There are settings in the connector that determine when a Batch is sent and it is conceivable that batch containing later data will be executed before a batch with earlier data. This means while the order in which the batches are sent is deterministic but not necessarily in the same order as the previous iterator.

## Does this matter for your application?

Probably not. This should only really matter if your data is really spread out 
in the RDD. If entries for a particular Cassandra Partition are spread amongst
multiple Spark Partitions then the order of Spark Execution could mess up
your upsert. Consider

    Spark Partition 1 has Record A
    Spark Partition 2 has Record B
    
    Both Spark Partitions have work start simultaneously, but Record B is
    reached before Record A.

But I think this is unlikely the issue.

The issue you are running into is most likely the common: [the order of statements in my batch is not respected][1]. The core of this issue is that all statements within a Cassandra batch are executed "simultaneously." This means that if there are conflicts for any `Primary Key` there needs to be a conflict resolution. In these cases Cassandra chooses the greater cell value for all conflicts. Since the connector is automatically batching together writes to the same partition key, you can end up with conflicts. 
  
You can see this in your example, the larger value (PT0H9M30S) is kept and the smaller(PT0H10M0S) is discarded. The problem isn't really the order, but the fact that the batching is occurring.

## How can I do upserts based on time then?

Very carefully. There are a few approaches I would consider taking. 

The best option would be to not do upserts based on time. If you have multiple entries for a `PRIMARY_KEY` but only want the last one, do the reduction in Spark prior to hitting Cassandra. Removing your unwanted entries before you try to write will save time and load on your Cassandra cluster. Otherwise you are using Cassandra as a rather expensive de-duping machine.

A much worse option would be to just disable the batching in the Spark Cassandra Connector. This will hurt performance but will fix the issue if you only care about the order within Spark Partitions. This will still cause conflicts if you have multiple Spark Partitions because you cannot control their order of execution.

## The Moral of this Story
State is bad. Order is bad. Design your system to be idempotent if at all possible. If there are multiple records and you know which ones matter, remove the ones that don't before you get to a distributed LWW system.


  [1]: http://stackoverflow.com/questions/30317877/cassandra-batch-statement-execution-order
