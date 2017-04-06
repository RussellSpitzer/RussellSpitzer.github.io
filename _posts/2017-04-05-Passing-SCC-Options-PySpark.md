---
title: Passing Spark Cassandra Connector Options in Pyspark
layout: post
comments: True
tags:
 - Spark
 - Cassandra
 - Python
 
---

Pyspark provides a great wrapper for DataFrame access but does come with a few little
quirks. One that you may run into is trying to pass options to a DataFrame which include
punctuation in their key names.

---

This may be obvious to a lot of folks, but Python doesn't let you use special characters in variable
names. Chief among these is ".". This presents a problem when using the Python version of 
`DataFrameReader.options`. Why is this? Let's take a look at the definition

[PyDoc Link](http://spark.apache.org/docs/latest/api/python/pyspark.sql.html?highlight=options#pyspark.sql.DataFrameReader.options)

```python
def options(**options):
  ..

```

Unlike Scala and Java which take a `Map[String, String]` python takes **options. If you aren't familiar, 
the `**options` means that this particular function takes `**kwargs` parameters.
`**kwargs` means that the function takes variable number of arguments in the form of `keyword = value`.
You would invoke such a function like

```python
spark.read.options(keyword = value, keyword2 = value2)
```

This means that your `keywords` must obey standard Python variable/function 
naming policy which means something like

```python
spark.read.options(spark.cassandra.input.split_size_in_mb = "52")
#SyntaxError: keyword can't be an expression
```

Will throw an error.

To get around this you can use the `**` operator/un-packer to treat a python dictionary as
`**kwargs` and pass through the otherwise illegal keys.

```python
option_dict = { "spark.cassandra.connector.input.split_size_in_mb" : "52"}
spark.read.options(**option_dict)

```

This solves the problem and lets us use all of the Spark Cassandra Connector 
[parameters](https://github.com/datastax/spark-cassandra-connector/blob/master/doc/reference.md) just
like were we using Scala or Java.

I've added a note about this to the Python [Documentation](https://github.com/datastax/spark-cassandra-connector/blob/master/doc/15_python.md) 
on the SCC as well. Happy Pythoning!