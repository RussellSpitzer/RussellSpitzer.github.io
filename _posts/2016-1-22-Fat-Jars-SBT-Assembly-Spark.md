---
title: Sbt Assembly (Fat Jars) With Spark 
layout: post
comments: True
tags:
 - Spark
 - SBT
 - Scala
 
---

---
Classpaths are almost always the first error folks run into when writing custom applications
for Spark. The difficult usually centers around the fact that there are many Spark processes and 
their special class-loaders. Most folks get around these issue by building Fat Jars with sbt
assembly but not everyone needs to do this.

---

Lets start with a quick overview of whats going on in Spark class-loaders. On the *Driver* and on 
the *Executor* we have two class-loaders.  

1. The System Class-loader
By default this is where your SparkAssembly jar is going to get loaded as well as all other 
core spark components

2. The Dynamic App Class-loader
Anything added by --jars and --packages is going to be loaded here

When you are running your application, make sure that your code AND all of it's 
dependencies are present on both the *Driver* and on the *Executor*. Now while your code 
most likely depends on Spark, Spark is on the classpath of both the driver and and the executor 
already so there is no need to worry about that. Your application code will also
automatically be placed on the executor cp (if you use `spark-submit`) so don't worry about that. 
For everything else you have two basic options:

## Use `--jars` and `--packages`
Using these commands you can specify specific external dependencies for your application. These can
include things like the *Spark Cassandra Connector* or *Your Secret Sauce ML Lib Which Determines the 
Cuteness of Cat Pics*. The Driver will let the executors know about these resources. The executors will 
pull the jar from Driver if necessarily, or some other source if specified (like `hdfs://` 
or `spark-packages`.) These libraries will be placed on the App class-loader. 

###Positives of this approach:

* Many Spark related libs are already available on the 
[spark-packages website](http://spark-packages.org/package/datastax/spark-cassandra-connector).
ready to go
* This makes it very clear what your dependencies are
* It's very easy to try out switching deps

###Negatives of this approach:

* You need to have the jars available
* Many files to manage rather than just one

## Use sbt-assembly (or some other Fat Jar build tool)

Fat jars are basically an attempt to make a single jar that contains not just your application 
code but also all the code for all the dependencies that code uses. If you built a Jar that depended
on org.apache.commons, your Fat Jar would actually contain folders `org/apache/commons` and all 
of the classes inside of it. This Fat Jar wouldn't require the *Commons* jar on the classpath because 
all of the classes are already there!

That does sound pretty nifty, but how do we actually build a Fat Jar? Most build systems have an 
Assembly plugin. For Scala [sbt-assembly](https://github.com/sbt/sbt-assembly) is the most common 
build system but the same general principles apply to all Fat Jar building. When actually using
these tools we can run into some issues. The most common problem is that when we are building a 
Fat Jar we can run into duplication problems.

Normally there aren't severe issues if multiple jars have similar (but slightly different versioned)
dependencies but assembly runs into an issue. After all, what should your assembly do if it tries
to add a file to `org/apache/commons` like StringUtils.class but it sees to different versions of
this code on your build path? This leads to a deduplication error. 99% of the time if this happens
on a class file something is broken and you most likely would run into issues if you ran the code.
This error is usually a sign that your build is impossible and things will not work as you like but
sometimes it's innocuous. For example, it's fine to skip any files that have conflicts that just 
talk about META-INF or pom.xml. After all you are building a new jar anyway so these other 
inventory files are useless anyway. 

For all other files you should first try your best to make a clean assembly. The way to do this is 
to first make sure that everything on the CP already is marked as "provided" (not included in your
Fat Jar). This means nothing that starts with "spark" should be in your assembly (unless your distro
happens to skip that lib.) If you do leave one of these libs in your jar, you will only suffer 
sadness.

###Positives of this approach:
* Only one jar to worry about and distribute
* Never worry about wrong jars being referenced

###Negatives of this approach:
* Building a Fat Jar can be non-trivial
* Locks your dependencies into your application code
* Yet another component you need to learn

#TL;DR
If at all possible don't make a Fat Jar, --jars and --packages should be simpler for most use cases.

If you do build a Fat Jar

  1. All Spark jars should be provided
  2. All METAINF, pom.xml files can be set to be skipped if there are conflicts
  3. All Class dedupe conflicts mean you most likely will have other problems
