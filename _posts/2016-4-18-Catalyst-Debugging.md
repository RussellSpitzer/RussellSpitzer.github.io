---
title: Debugging Catalyst and Predicate Pushdown with Spark Cassandra Connector
layout: post
comments: True
tags:
 - Spark
 - Cassandra
 - Scala
 - SparkSQL
 
---

---
Making sure your code is actually pushing down predicates to C* is slightly confusing. In this
post we'll go over the basics on setting up debugging and how to workaround a few common issues.


---

Let's start with a common table schema like 

```sql
CREATE TABLE test.common (
    year int,
    birthday timestamp,
    userid uuid,
    likes text,
    name text,
    PRIMARY KEY (year, birthday, userid)
)
```

And I'll insert a few junk rows

    year | birthday                 | userid                               | likes   | name
    ------+--------------------------+--------------------------------------+---------+-------------------
    1985 | 1985-02-05 00:00:00+0000 | 74cc615c-05b9-11e6-b512-3e1d05defe78 |  soccer | Cristiano Ronaldo
    1980 | 1980-10-03 00:00:00+0000 | 74cc615c-05b9-11e6-b512-3e1d05defe79 | twitter |   Kim Kardashian

This table is perfect for satisfying OLTP lookups for my Favorite Birthday gifts archive website 
(although perhaps a bit heavy at a single partition a year). What's important is that we should 
be able to determine the likes of any out whose birthdays fall within a year. With OLAP we should 
be able to search globally over all years and we should be able to *pushdown* and use the 
`birthday` clustering key.

Too minimize the noise in the console we will set the log4j settings to WARN on the root logger
and info for the connector.

```sh
cp conf/log4j.properties.template conf/log4j.properties
// Edit log4j.properties
// Change root logger from INFO to WARN 
// And Add
// log4j.logger.org.apache.spark.sql.cassandra=DEBUG

```

Let's start up spark-sql and register this table

```sh
./bin/spark-sql \   
    --packages datastax:spark-cassandra-connector:1.6.0-M2-s_2.10 \
    --conf spark.cassandra.connection.host=localhost
```

```sql
CREATE TEMPORARY TABLE common 
    USING org.apache.spark.sql.cassandra 
    OPTIONS ( table "common", keyspace "test");
```

Now when we query we should get some basic info about how C* handles the pushdowns

```sql
spark-sql> select * from common;
16/04/18 17:13:17 INFO CassandraSourceRelation: Input Predicates: []
16/04/18 17:13:17 DEBUG CassandraSourceRelation: Basic Rules Applied:
C* Filters: []
Spark Filters []
16/04/18 17:13:17 DEBUG CassandraSourceRelation: Final Pushdown filters:
C* Filters: []
Spark Filters []
16/04/18 17:13:17 INFO CassandraSourceRelation: Input Predicates: []
16/04/18 17:13:17 DEBUG CassandraSourceRelation: Basic Rules Applied:
C* Filters: []
Spark Filters []
16/04/18 17:13:17 DEBUG CassandraSourceRelation: Final Pushdown filters:
C* Filters: []
Spark Filters []
1985	1985-02-04 16:00:00	74cc615c-05b9-11e6-b512-3e1d05defe78	soccer	Cristiano Ronaldo
1980	1980-10-02 17:00:00	74cc615c-05b9-11e6-b512-3e1d05defe79	twitter	Kim Kardashian
```

These empty brackets `[]` let us know there were no predicates that will be handled by spark
or C*. For a `select *` that makes sense, So lets try adding a predicate to find everyone with 
a birthday before January 1 2001;

```sql
spark-sql> select * from common where birthday < '2001-1-1';
16/04/18 17:16:14 INFO CassandraSourceRelation: Input Predicates: []
16/04/18 17:16:14 DEBUG CassandraSourceRelation: Basic Rules Applied:
C* Filters: []
Spark Filters []
16/04/18 17:16:14 DEBUG CassandraSourceRelation: Final Pushdown filters:
C* Filters: []
Spark Filters []
16/04/18 17:16:14 INFO CassandraSourceRelation: Input Predicates: []
16/04/18 17:16:14 DEBUG CassandraSourceRelation: Basic Rules Applied:
C* Filters: []
Spark Filters []
16/04/18 17:16:14 DEBUG CassandraSourceRelation: Final Pushdown filters:
C* Filters: []
Spark Filters []
Time taken: 0.56 seconds                                                                                     
```

Well that's odd, no predicates ... what's going on here? 
Let's use `explain` to see what Spark's plan was for executing this query.

```sql
select * from common where birthday < '2001-1-1';
Filter (cast(birthday#1 as string) < 2001-1-1)
+- Scan org.apache.spark.sql.cassandra.CassandraSourceRelation@3d3e9163[year#0,birthday#1,userid#2,likes#3,name#4]
Time taken: 0.058 seconds, Fetched 3 row(s)
```

The first line `Filter (cast(birthday#1 as string) < 2001-1-1)` tells a sad story. Catalyst took
a look at this query and said 
    
    '2001-1-1' looks like a string. I'll make birthday a string too! Then I can compare it lexically. 
     Everyone will love me for making this great decision!" 
     
Since it has to  do a `cast` operation on the column, Catalyst won't even let 
C* know that there is a possible  predicate here to compare with. So how do we let Spark a hint 
that the literal `2001-1-1` is a date and not just a random string? 

What we can do is `cast` the literal to a timestamp! This will help let catalyst know that it doesn't
 have to do any casts on the database data. The predicate is now passed to the 
source since Catalyst won't be trying to do any casts.

```sql
spark-sql> select * from common where birthday < cast('2001-1-1' as timestamp);
16/04/18 17:36:15 INFO CassandraSourceRelation: Input Predicates: [LessThan(birthday,2001-01-01 00:00:00.0)]
16/04/18 17:36:15 DEBUG CassandraSourceRelation: Basic Rules Applied:
C* Filters: [LessThan(birthday,2001-01-01 00:00:00.0)]
Spark Filters []
16/04/18 17:36:15 DEBUG CassandraSourceRelation: Final Pushdown filters:
C* Filters: [LessThan(birthday,2001-01-01 00:00:00.0)]
Spark Filters []
16/04/18 17:36:15 INFO CassandraSourceRelation: Input Predicates: [LessThan(birthday,2001-01-01 00:00:00.0)]
16/04/18 17:36:15 DEBUG CassandraSourceRelation: Basic Rules Applied:
C* Filters: [LessThan(birthday,2001-01-01 00:00:00.0)]
Spark Filters []
16/04/18 17:36:15 DEBUG CassandraSourceRelation: Final Pushdown filters:
C* Filters: [LessThan(birthday,2001-01-01 00:00:00.0)]
Spark Filters []
1985	1985-02-04 16:00:00	74cc615c-05b9-11e6-b512-3e1d05defe78	soccer	Cristiano Ronaldo
1980	1980-10-02 17:00:00	74cc615c-05b9-11e6-b512-3e1d05defe79	twitter	Kim Kardashian
Time taken: 0.127 seconds, Fetched 2 row(s)
```

We also see now that our C* Filters have a new entry showing we have correctly pushed down the
timestamp directly to our Cassandra query. We'll be saving time and avoiding any bad lexical 
comparisons on timestamps :)




