---
title: Where does my Spark Output go?
layout: post
comments: True
tags:
 - Spark
---

"My output worked in local mode, but now it's all gone ... where is it?" 

---

One of my favorite, and perhaps most common, debugging 
technique is the good old ```println("Got to this point")```. Try this in
Spark and you may have a lot of unfortunate disappearing output. Or so it seems.

Let's take a quick example in the Scala Shell using the `Local` Spark Master.

```scala
scala> println("Hello World")
Hello World

scala> sc.parallelize(1 to 2).foreach(println)
2
1
```

Everything worked exactly the way we wanted! All of our output appeared
exactly how we expected. But let's see what happens when we run the 
Spark Shell with the Standalone (or DSE) Spark Master.

```scala
scala> println("Hello World")
Hello World

scala> sc.parallelize(1 to 2).foreach(println)

scala>
```

Where did it go! Did those DSE dev's just break Spark? (Hint: No.)

This is an expected behavior from Spark! So why did our output vanish? It 
*didn't*, it just didn't end up where we expected. ```println``` sends our
text to `STDOUT` but that is the `STDOUT` of the process where the code
is running. 

In the above example we actually have 2 different processes running user
code, the Spark-Shell (acting as the Spark Driver) and the Spark Executor
which is the process actually running our remote code. The Spark Executor
runs the `println` inside the foreach and it's `STDOUT` is not the 
Spark Shell's `STDOUT`. But this does not mean our output is lost!

The Executor process sends it's output to a special set of files in it's
working directory. This directory by default is in a place that looks like
`/var/lib/spark/worker/app-#/executor#/std[out|err]` on DSE and 
`work/app-20181127160938-0000/0/stdout` in my Stand Alone install. 

Let's take a look

```
16:37:18 ➜  ~/SparkInstalls/spark-2.2.1-bin-hadoop2.7  cat work/app-20181127160938-0000/0/stdout
   2
   1
```
   
Our output! Exactly where we told it to be `STDOUT`, just not the Shell `STDOUT`. 
This is just a little thing we always need be aware of when we are running
code in our distributed framework. Sometimes our code doesn't run in the
process we expect!
