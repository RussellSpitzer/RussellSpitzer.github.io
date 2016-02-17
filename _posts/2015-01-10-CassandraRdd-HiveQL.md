---
title: Loading a CassandraRDD into a HiveContext in Spark
layout: post
tags:
 - Cassandra
 - Spark
 - Scala
 - Java
---

Spark is awesome and I love it. SparkSQL is also awesome but unfortunately is not fully mature. Although the
folks at DataBrix have talked about how it will eventually become as full ANSI SQL langauge that time
is honestly far off. This means that most folks will want to fall back onto HiveQL for doing their 
more complicated queries on Spark.

Accessing your data via Hive on Spark is easy if you have DataStax Enterprise since everything is 
already bundled together and it should "just work." But if you are using Apache Cassandra and
Apache spark there is still a solution.

First load up your Cassandra Data into a cassandra RDD mapped to a case class or MBean like object. Be sure to apply any predicates you want
at this time. This is crucial if you want to do a primary key pushdown or something of that nature.

### Scala

```scala
case class AsciiRow (pkey:String, ckey1:String, data1:String)
val rdd = sc.cassandraTable("ascii_ks","ascii_cs")
```


### Java

```java
public static class AsciiRow implements Serializable
{
    private String pkey;
    private String ckey1;
    private String data1;
    
    ... getters and setters ...
}
JavaRDD<AsciiRow> rdd = javaFunctions(jsc)
  .cassandraTable("ascii_ks", "ascii_cs", mapRowTo(AsciiRow.class))
  .where("pkey = 'One'");
```
      
Once we have our rdd's we can simply register them in our HiveContext and we can do all the HiveQL we
desire!

### Scala

```scala
rdd.registerTempTable("ascii_cs")
csc.sql("SELECT pkey from ascii_cs")
```

###Java
```java
JavaSchemaRDD schemaAscii = sqlContext.applySchema(rdd, AsciiRow.class);
schemaAscii.registerTempTable("ascii_cs");
JavaSchemaRDD result = sqlContext.sql("SELECT pkey FROM ascii_cs");
```
