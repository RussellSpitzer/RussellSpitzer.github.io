---
title: Spark Partitions and the 2GB Limit
layout: post
comments: True
tags:
 - Spark
---

Did you know Spark has a 2GB architectural limit on certain memory structures? I didn't. Then
I was helpfully pointed to [SPARK-6235](https://issues.apache.org/jira/browse/SPARK-6235) which points
out there are several places in the Spark code which use byte arrays and byte buffers. These objects
are sized with INT which means anything larger than MAX_INT will cause failures. In practice this
usually means a user running into this issue will need to fix their data's Partitioning.

## Partitioning

Partitioning is the process of taking a very large amount of data and splitting it into multiple smaller
chunks based on some property. In Spark's case this happens within the RDD class which defines 
the *partitions* for any give operation and how to operate on them. If we think about an RDD as
a giant array, a partition could be something like elements (1-5) and then another partition could be
elements (6-10). 

What does this have to do with our limit? Well a partition to Spark is basically the smallest unit
of work that Spark will handle. This means for several operations Spark needs to allocate enough 
memory to store an entire Partition. It stores the Partition with Java structures whose size is 
determined by an Integer. This leads to our 2GB limit, if a single Partition exceeds
2GB of memory and needs to be shuffled or cached we will run into problems.

## Who decides Partitioning

### RDDs 

#### Sources
Within RDDs partitioning is almost always explicitly defined. For example, with the Spark Cassandra 
Connector partitions are initially defined by dividing up the Cassandra Token range into pieces. 
Different numbers of partitions can be requested which results in larger or smaller token range pieces 
and consequently larger and smaller Spark Partitions. This is similar to almost all sources which 
define their number of partitions based on information provided by the user and information derived 
from the source.

Summary: 
```
Partitions usually defined based on source no one size fits all rule
```

#### One to One Transformations
Applying certain functions to an RDD can change the partitioning as well, these mostly cause a shuffle. 
Operations which do not cause a shuffle almost always just inherit the partitioning
of the RDD they are called on. For example, calling `map` on a RDD will just use the previous RDD's
partitioning.

Summary: 

```
   Partitions in == Partitions Out
```



#### Shuffles

When a Shuffle does occur, the new partitioning is heavily dependent on whether or not the RDD needs
a new Partitioner. Partitioners locate which partition a piece of data would be in (if it existed). 
For example, say we want to join RDD[CatName, CatAge] with RDD[CatName, CatFavoriteTreat]. If we 
want to check whether a CatName exists in both RDDs then a common Partitioner would let us check
only a single Partition in both RDDs. If both RDDs are already partitioned with a Partitioner
(CatName => PartitionNumber) then we don't need to shuffle, we just line up our partitions one
by one and join. We know that if "Mr Pants" is in the first RDD partition 3, then we know it would
also be in second RDD partition 3 if it existed. In this case the result of joining the two RDDs
would have the same partitioner as the RDDs being joined since partition 3 would still contain all
of elements where "Mr Pants" was the name.

If there is no Partitioner then Spark will automatically repartition our data using the 
defaultPartitioner on the key of our RDD. This is defined as the HashPartitioner with 
`spark.default.parallelism` output partitions if set, or the number of partitions in the
largest dependency if not set. The implementation of the hash partitioner is: 
1. Take the key 
2. Apply a hash function 
3. Modulo the number of partitions
The shuffle would rearrange all the data in all of our partitions so that this rule would hold
true. Once complete, our data could be joined partition to partition.  since they now have the
same partitioners. Almost every operation which would cause a shuffle has an API which also accepts
number of partitions as a Parameter.

Summary: 
```
If shuffle required
  If spark.default.parallelism set
      New hash partitioning with `spark.default.parallelism`
  else if spark.default.parallelism not set
      Number of partitions in parent RDD with most partitions
else
  Partitions in = Partitions out
```


### Reducing Partition Sizes in RDDs

With RDDs there are a lot of internal mechanics we have to be aware of to actually determine why
the partitioning of an RDD is the way it is. The whole lineage must be investigated to see when
partitioning changes and why.

For example if we never have any shuffle operations, the only way to change our partitioning is
to look at how our source originally partitions data. If a shuffle is occurring we
can either use the programmatic approach and explicitly pass a large number of partitions or set the 
`spark.default.parallelism` parameter. 

## Datasets/Dataframes/SparkSQL

Within all of these apis, Spark decides on the order of operations and when to do shuffle related 
actions. There are several options left though to do explicit repartitioning, see `repartition`
which let us manually control the new number of partitions. For all of the built in shuffles
the parameter `spark.sql.shuffle.partitions` sets our default number of output partitions. Datasources,
as with RDDs, will all have rules specific to their implementation dictating the number of partitions.

### Reducing Partition Sizes in DataFrames

Here we have to explicitly add a repartition command into our flow, or set the
`spark.sql.shuffle.parttions` parameter to a larger number (Default is [200](https://spark.apache.org/docs/2.3.0/sql-programming-guide.html#other-configuration-options)).
Note that this parameter is *completely different than the RDD parameter*.


## When repartitioning does not help

One problem with all of the above methods is that they rely on the keys for the repartition being
evenly (or close to it) distributed. This means that if I'm repartitioning my Cat data using "name"
as a key, I'm never going to be able to subdivide any particular name. Mitten, for example, would most
likely lead to a Partition with lots and lots of data since Mittens is a very common name. For issues
like this the best thing to do is to try repartitioning on a different column if possible or use a
collection of columns like name and age.

## How many Partitions is too many?

Obviously going above our 2GB limit is bad, but does that mean having 1KB partitions is a good idea?
Unfortunately there is no hard and fast answer to this question. Every partition represents a piece 
of data that Spark can work on independently. If an RDD has 5 partitions but the Cluster has 40 cores
then only 5 of those cores will be in use. Conversely, an RDD with 40000 very small partitions will
spend a tremendous amount of time just doing book-keeping organizing results and monitoring the job. 

For most use cases it makes sense to keep partitions above 2x your number of cores as a minimum and
make sure they are not so large as they get close to the 2GB minimum. Your mileage may very based
on the cpu/IO considerations of the specific work your application is doing.



  
 


