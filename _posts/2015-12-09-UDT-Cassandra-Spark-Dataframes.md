---
title: Working with Cassandra UDTs and Spark Dataframes
layout: post
comments: True
tags:
 - Cassandra
 - UDT
 - Spark
 - Scala
---

---
We just fixed a [bug](https://datastax-oss.atlassian.net/browse/SPARKC-271)
 which was stopping `DataFrames` from being able to write into Cassandra UDTs. But I noticed there
 aren't a lot of great documents around how this works. Here is just a quick example on how you can
 make a dataframe which can insert into a C* UDT.
---

First in CQLSH we need to make a table

    CREATE KEYSPACE jd WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1 };
    CREATE TYPE  address_type ( street text, city text, zipcode text);
    CREATE TABLE jd.test ( key int PRIMARY KEY, address map<text, frozen<address_type>>);
    
The keyspace is named JD in honor of someone on the Spark Cassandra Connector mailing list who 
inspired me to quickly write this. This table has a collection which contains a UDT within it. In 
Spark the UDT type is represented as mini-rows within your normal DataFrame row. This means it is
easiest to represent this in scala as a Case Class which contains a case class.

So in the Spark Shell

    case class address ( street: String, city: String, zipcode: String ); // Represents our UDT
    case class testRow ( key: Int, address: Map[String, address]); // Represents our C* Row
    val df = sc.parallelize( 1 to 10).map( x => 
      testRow( x, Map("Hello" -> address("Melody Lane", "Oakland", "90210"))))
      .toDF 
      /** Uses Reflection to automatically infer the schema from our case classes. This will end up
      making the schema of this DataFrame 
      Row(key:Int, Map(key: Text -> Row( street: Text, city: Text, zipcode: Text))
      **/
      
    // Then use the normal DataFrame Api to save our data back to C*
    df.write.format("org.apache.spark.sql.cassandra").options(Map("keyspace" -> "jd", "table" -> "test")).save

    // Finally we can just read it back to prove the insert worked
    sc.cassandraTable("jd","test").collect.foreach(println)
    
    /*
    CassandraRow{key: 5, address: {Hello: {street: Melody Lane, city: Oakland, zipcode: 90210}}}
    CassandraRow{key: 10, address: {Hello: {street: Melody Lane, city: Oakland, zipcode: 90210}}}
    CassandraRow{key: 1, address: {Hello: {street: Melody Lane, city: Oakland, zipcode: 90210}}}
    CassandraRow{key: 8, address: {Hello: {street: Melody Lane, city: Oakland, zipcode: 90210}}}
    CassandraRow{key: 2, address: {Hello: {street: Melody Lane, city: Oakland, zipcode: 90210}}}
    CassandraRow{key: 4, address: {Hello: {street: Melody Lane, city: Oakland, zipcode: 90210}}}
    CassandraRow{key: 7, address: {Hello: {street: Melody Lane, city: Oakland, zipcode: 90210}}}
    CassandraRow{key: 6, address: {Hello: {street: Melody Lane, city: Oakland, zipcode: 90210}}}
    CassandraRow{key: 9, address: {Hello: {street: Melody Lane, city: Oakland, zipcode: 90210}}}
    CassandraRow{key: 3, address: {Hello: {street: Melody Lane, city: Oakland, zipcode: 90210}}}
    */
    
This is the easiest way to quickly test UDTs, if you are reading form a source like json, it will 
automatically build these internal rows if you have nested types. In addition reading from C* will 
automatically turn UDTs into these internal rows, so UDTs can be copied from one table to another
without modification.
