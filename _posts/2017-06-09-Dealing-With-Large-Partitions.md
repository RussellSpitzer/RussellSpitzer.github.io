---
title: Dealing with Large Spark Partitions
layout: post
comments: True
tags:
 - Spark
 - Cassandra
 
---

One of the biggest issues with working with Spark and Cassandra is dealing with
large Partitions. There are several issues we need to overcome before we can really handle
the challenge well. I'm going to use this blogpost as a way of formalizing my 
thoughts on the issue. Let's get into the details

---

## Background

### How the Spark Handles Parallelism

Spark is a [Data Parallel](https://en.wikipedia.org/wiki/Data_parallelism) system. A large set of data 
is broken into partitions (splits for hadoop users) all of which are worked on independently. You can
see this in the [RDD](https://github.com/apache/spark/blob/v2.1.1/core/src/main/scala/org/apache/spark/rdd/RDD.scala#L118-L125) 
class. The work done in each Spark task is defined by the metadata in a single `Partition`. The
 work itself is coded in the [compute method](https://github.com/apache/spark/blob/v2.1.1/core/src/main/scala/org/apache/spark/rdd/RDD.scala#L111-L116). 
Note that `compute` takes an argument of a single `partition`, this means that 
 
 1. The compute method can only interact with a single partitions worth of data
 2. It cannot interact with the data from another partition
 3. The global partitioning cannot be changed during the compute method
 
The `partition metadata` is also only made once before the work begins. These aspects
are what make RDD's not only Immutable but also more or less deterministic. Each partition is
independent of every other partition and this lets Spark spread work to any machine and even 
recompute partitions without ill effects (most of the time[^1]). 

One of the difficulties of writing a datasource RDD is determining how that partitioning will be 
done. 
 
### How the Spark Cassandra Connector Partitions Data

There are many different DataSources for reading from Spark and they all take different
approaches to the partitioning problem. JDBC sources require a specific `partitioning` column
as well as min/max and step value; all of which must be provided before the target database
is contacted. Each partition is built of the results of a query with a where clause bounded by
the step range. Most of the file system sources map one file to one Spark Partition. The
Spark Cassandra connector takes another approach based on the underlying distribution of data
within Cassandra.

Cassandra distributes data based on it's own [partitioner](http://docs.datastax.com/en/cassandra/3.0/cassandra/architecture/archPartitionerAbout.html) 
which is separate from the Spark partitioning and Spark Partitioners. The partitioner takes 
incoming data and uses a hash function (Murmur3-ish[^2]) to map a piece of data to a 
particular value. The mapped value is the Token and the range of all possible tokens is the
Token Range. 
Different nodes in the cluster will own (or be a replica) of particular portions of the token range.
The piece of the data which is hashed is called the `Partition Key`. Within each Cassandra partition 
the order of the data is determined by other columns which are called the `Clustering Keys`. With
this mechanism any piece of data can be located by computing the hash of its `Partition Key` to 
find it's Token. Then the mapping that Token to the node which owns the correct token range.

The [Spark Cassandra](https://github.com/datastax/spark-cassandra-connector/blob/24f392db011fb5a727574456c3ffb562d9834623/spark-cassandra-connector/src/main/scala/com/datastax/spark/connector/rdd/partitioner/CassandraPartitionGenerator.scala#L70-L95) 
connector makes Spark Partitions by taking the Token Range and dividing
it into pieces based on the Ranges already owned by the nodes in the cluster. The number and 
size of the Spark Partitions are based on metadata which is read from the Cassandra cluster. The 
estimated data size[^3] is used to build Spark Partitions containing the amount of data 
specified by a user parameter `split_size_in_mb`. 

For more information see this [visual guide](https://academy.datastax.com/resources/how-spark-cassandra-connector-reads-data)

This strategy for partitioning has a few direct results
  * Spark Partitions Align with Cassandra Nodes - Locality is possible
  * Cassandra Partitions are never split amongst Spark Partitions - Shuffle less operations on partitions are possible
  * Order within a Cassandra Partition is maintained
  
Because Spark Partitions always must hold a full Cassandra Partition we can run into problems
when Cassandra has hotspots (partitions which are exceedingly large). We can also run into issues
if all of our partitions start exceeding a manageable size for Spark.

## The Problem and Possible Solutions

### Why can't we just break up large partitions amongst different Spark Partitions

The real problem with breaking up large partitions is that it is impossible for us to know which
partitions are truly large without reading them first. As I noted previously, we need to specify the
partitioning of the RDD *before* we actually do any computation. This means we are blind to many
aspects of the data. That said, let's explore some approaches we might be able to take to break
up these large partitions. 

### Randomly/evenly choose breakpoints in a partition's domain

The key problem with randomly choosing the partition breakpoints is that the domain of all
clustering column values is exceedingly large while actual usage domain is relatively dense. 

Considering a single clustering column c which is an integer. If we have no information on 
the actual data's bounds, we must is to assume that the data could span `Int.MinValue` to 
`Int.MaxValue`.  If the end user was only using values between 1 and 1000000 it would require
2147 partitions before we did our first slice which would actually divide the user's data.

The problem becomes even more difficult if the clustering key is made of multiple columns.
Consider a clustering key `(c: Int, d: String, e: Int)`, now our range is all of the 
ValidIntegers * ValidStrings * ValidIntegers. A random partitioning of this enormous range
(which is also unbounded because of the String) would almost certainly not match a user's
actual domain.

### Modifying Cassandra to take approximate column statistic and store them in sstable metadata

We could do much better at choosing our breakpoints if we had some approximate information about
column distributions prior to deciding where to make our cuts. SSTables could be built with 
attached metadata describing approximate unique values, mins, and maxs. These values could be
merged to get a conservative estimate about the actual bounds of column values. This would be 
significantly better than assuming the true max bounds of each field. Unfortunately this would require
a deal of upstream work inside of the Cassandra project.

### Sampling Partitions 

Another approach is to run a "pre-scan" job which would distribute a bunch of small tasks. A fully
 independent Spark Job could be launched before the full scan was actually executed. Each
small task would select some portion of the existing partitions and read them into memory. We 
would then compute our own statistics live on this data and use that information to break up
 the full scan we would subsequently do. 
 
 This is a pretty expensive solution as it requires running a pre-job for every full job. Sampling
 randomly from within Partitions also seems like it may be a problem to me. 
 
### Manually dividing our partitions using a Union of partial scans

Pushing the task to the end-user is also a possibility (and the current workaround.) Most end
users already understand why they have long partitions and know in general the domain their
column values fall in. This makes it possible for them to manually divide up a request so that
it chops up large partitions.

For example, assuming the user knows clustering column c spans from 1 to 1000000. They
could write code like

```scala
val minRange = 0
val maxRange = 1000000
val numSplits = 10
val subSize = (maxRange - minRange) / numSplits

sc.union(
  (minRange to maxRange by subSize)
    .map(start => 
      sc.cassandraTable("ks", "tab")
        .where("c > $start and c < ${start + subSize}"))
)
```

Each RDD would contain a unique set of tasks drawing only portions of full partitions. The union
operation joins all those disparate tasks into a single RDD. The maximum number of rows any single
Spark Partition would draw from a single Cassandra partition would be limited to `maxRange/ numSplits`.
This approach, while requiring user intervention, would preserve locality and would still minimize
the jumps between disk sectors.

### Conclusions

Pursuing more sstable adjacent metadata seems like the right course from here on out. The sstables
are immutable and we can do some calculations to get conservative estimates of column statistics. The
underlying problem of having completely accurate statistics is caused by the lack of monotonicity 
in Cassandra operations. Even having estimates within an order of magnitude is probably a good first 
step. This sort of column metadata could be useful even outside the realm of Cassandra specific 
operations as the data could be fed into the Catalyst cost-based optimizer. 


[1^]: It is possible for the compute method to be non-deterministic with respect to it's partition metadata. For example
a compute method could read data from a Database whose contents change. Computing the same partition at different times
would yield different results. Another example would be a compute method could explicitly generate a random number
with a seed that is not tied to the Partition metadata, this would also yield different results of the partition was
recomputed.

[2^]: The actual implementation of the partitioner is one of three options: ByteOrdered which only 
experts should use and most that do use it regret it; Random which is slightly larger and slower
than Murmur3 and was the old default; and Murmur3 which is actually not a canonical (read slightly incorrect)
implementation so its actually more like Murmur3-ish. The "ish" attribute is only important if
you are writing a new driver and want to get token range awareness right or you are trying to
mimic the behavior of the internal Cassandra partitioning for some other reason outside the
helper functions provided by the common drivers.

[3^]: Estimated data size is a field populated in a system table within Cassandra. It provides a 
very rough estimate of the amount of data in a particular Token Range. 
