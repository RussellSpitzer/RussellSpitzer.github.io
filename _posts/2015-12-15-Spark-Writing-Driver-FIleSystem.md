---
title: Writing to the Driver FileSystem using Spark
layout: post
comments: True
tags:
 - Spark
 - Scala
 
---

---
Spark Loves Distributed filesystems, but sometimes you just want to write to wherever the driver is
running. You may try use a `file://` or something of that nature and run into a lot of strange errors
or files located in random places. Never fear there is a simple solution with `toLocalIterator`.
 
---

The key issue here is that when you use a location of `file://` every machine assume you are talking 
about it's local filesystem. This can lead to madness, what you actually want is all of the data to
write to a single file on the Driver's Local filesystem.

A first instinct my be to use `collect` on the RDD before attempting to write it to a file but this
has a distinct limitation. When you use collect every partition is moved from the remote cluster
to the driver machine at the same time. This means if you use collect you can never write a file 
larger than driver heap. 

`toLocalIterator` lets us get around this by only pulling down a single Spark partition's worth
of data to the DRiver at a time. This means that you can write as large a file as HDD space you have 
as long as no one Spark Partition is bigger than the driver heap.

Example of Writing an RDD using `toLocalIterator`

```scala
scala> import java.io._
import java.io._

scala> val pw = new PrintWriter(new File("LocalText"))
pw: java.io.PrintWriter = java.io.PrintWriter@5879197

scala> val rdd = sc.parallelize(1 to 100000).map( num => s"$num::Line")

scala> for (line <- rdd.toLocalIterator) { pw.println(line) }

scala> pw.close
scala>:quit

15:40:11 ➜  ~/SparkInstalls/spark-1.5.1-bin-hadoop1  tail LocalText
99991::Line
99992::Line
99993::Line
99994::Line
99995::Line
99996::Line
99997::Line
99998::Line
99999::Line
100000::Line
```

In the Application UI you'll notice that the toLocalIterator runs a {{Job}} on each Spark Partition 
one at a time, rather than one single Job as in collect. 
