---
title: Pruning and Spark DataSources, A Love Story
layout: post
comments: True
tags:
 - Spark
 - Cassandra
 - Scala
 - SparkSQL

---

I was looking through a pile of Jiras and I noticed an interesting complaint that DataFrame pruning
was broken for the Spark Cassandra Connector. The ticket noted that even when very specific columns
were selected, it seemed like the Connector was pulling all of the rows from the source Cassandra
table. This is surprising, since that particular part of the connector code has some rather heavy
testing coverage and there haven't been any comments on this feature not working from anyone else.
Compared to predicate pushdown, pruning is easy so what went wrong?

---

The complaint was focused around a DataFrame count operation being invoked directly after pruning
the DataFrame. So I turned on debug logging, and started firing off some commands. First I created
a two column table (k,v) and ran a show.

```scala
df.show
```
```
DEBUG ... SELECT "k", "v" FROM "test"."tab" WHERE token("k") >= ? ...
```

Looks good, the underlying CQL is pulling all the columns as expected. So let's prune that down
by requesting only the "v" column and seeing what happens

```scala
df.select("v").show
```
```
DEBUG ... SELECT "v" FROM "test"."tab" WHERE token("k") >= ? ...
```

Vindicated! Only "v" was requested *close ticket won't fix* ... Or maybe not. I decide to check
the use case the submitter actually filed.

```scala
df.select("v").count
```
```
DEBUG ... SELECT "k", "v" FROM "test"."tab" WHERE token("k") >= ? ...
```

This "count" seems to force all the columns back into the picture. This is not as planned :(
Is there a bug in the Connector? Well lets just do a quick sanity check and try out the SparkSQL
interface just to see if the issue exists there as well.

```scala
sqlContext.sql("SELECT count(v) FROM test.tab").show
```
```
DEBUG ... SELECT "v" FROM "test"."tab" WHERE token("k") >= ? ...
```

By counting the "v" is all we restore the optimal behavior. But why does count act so
weird all by itself? Well this is the implementation of count in
DataFrame.scala

```scala
 groupBy().count()
```

And `groupBy` takes columns as an argument. Which means this essentially means group on nothing
and then count. This means all that precious information about only caring about "v" is gone! After
all what's better than pruning down to one column. Pruning down to zero columns is the answer.

```scala
scala> df.groupBy().count.explain
== Physical Plan ==
TungstenAggregate(key=[], functions=[(count(1),mode=Final,isDistinct=false)], output=[count#14L])
+- TungstenExchange SinglePartition, None
   +- TungstenAggregate(key=[], functions=[(count(1),mode=Partial,isDistinct=false)], output=[count#18L])
      +- Scan org.apache.spark.sql.cassandra.CassandraSourceRelation@5fa851ac[]
```

That poor lonely CassandraSourceRelation. Since no columns are listed there we don't know what to
Select from C*. Nothing isn't really an option in C* so the default falls back to pulling everything!
I'm not sure if any other sources are configured this way but I imagine this could be an issue for
other sources as well that don't know how to return empty rows.

Ok so how do we get the sweet prune action from the DF api? Let's just use the count by column function!
```scala
scala> import org.apache.spark.sql.functions._
scala> df.select(count('v)).show
== Physical Plan ==
TungstenAggregate(key=[], functions=[(count(v#39),mode=Final,isDistinct=false)], output=[count(v)#81L])
+- TungstenExchange SinglePartition, None
   +- TungstenAggregate(key=[], functions=[(count(v#39),mode=Partial,isDistinct=false)], output=[count#85L])
      +- Scan org.apache.spark.sql.cassandra.CassandraSourceRelation@6f5acac9[v#39]
```
Our scan is once more happy and the pruned information goes all the way down to Cassandra! Until
we have a way to push a direct COUNT(*) down to C* (Like in the RDD API see cassandraCount) this is
probably as good as it gets.