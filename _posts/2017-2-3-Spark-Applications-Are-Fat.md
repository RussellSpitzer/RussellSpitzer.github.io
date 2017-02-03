---
title: Spark Applications are Fat
layout: post
comments: True
tags:
 - Spark
 - DSE
 - Spark-Submit
 
---

Spark Submit is great and you should use it.

One Line Summary: 
Any applications which use a Spark Context should be started with `dse spark-submit` in place of `java -jar` because they need full cluster configuration. 

----

A common question that comes up when we talk about Spark is “Why does my Spark Application require so many libraries and configuration? Why can’t i just run java -jar foo.jar?”  The main reason for this is that any application that uses a `Spark Context` is implicitly a Fat Client for Spark which requires all the setup and configuration of a full Spark cluster.

## Why is the `Spark Context` not a thin Client?

Creating a `Spark Context` is basically the same as creating a new Cluster whose members include:

    * the application, known as the Spark Driver
    * a set of brand new Executor JVMs that are created solely to communicate with that application.

This cluster expects to be able to communicate internally and by default allows know external actors to influence it. Every Spark Application is basically a completely isolated set of distributed JVMs. The Spark Driver is basically the scheduler/master while the executors are its workers.

The Spark Master and Worker would probably be better named Cluster Resource Manager and Executor Launcher. They have no responsibilities related running the application. They are solely dedicated to resource management have no ability to actually influence (outside of shutting down) the processing of any information through the system. In fact, you can kill the Spark Master while your application is running and it will continue working with only a few error messages in the log about the heartbeats failing. In Hadoop terms, making a Spark Context is the same as spawning up a new JobTracker and set of TaskTrackers for every application. Spark Executors cannot be accessed except through the driver application which they were  spawned for and they only exist in context of that application.

This architecture means that even a statement like spark.sql(“SELECT * FROM lah”) requires the Spark Driver to do all of the following 

  1. Negotiating the creation of the remote JVMs with the Spark Master
  2. Initiating two way communication with every  Executor JVM created
  3. Management of liveness of all remote machines
  4. Creation of a catalogue of Sql Table and Keyspace definitions (held locally but this may involve communicating with a remote metastore)
  5. Parsing and optimizing  the query
  6. Conversion of the query into a set of compiled at runtime java code
  7. Sending out the newly compiled java code
  8. Dividing the query into chunks to be processed
  9. Distribution of those chunks
  10. Tracking the completed locations of those chunks
  11. Redistributing metadata to let executors know what additional work they should do and where those completed chunks are
  12. Negotiating shuffles between executor JVMS incase chunks need to be co-grouped
  13. Gathering back the results from all of the remote executors

All of this work means a considerable amount of configuration and classpath organization has to happen. This simple statement basically has to know how to completely run a Spark Cluster in order to execute. All optimizations, filters, custom datatypes, classloader specifications, and cluster configuration notes need to be set correctly for just that tiny statement to run in an isolated application. 

Most users come in with an expectation that Spark will operate instead in a workflow like

  1. Send a request
  2. Receive a response
  
We cannot do this with a single Spark Standalone application. To achieve this kind uncoupled behavior we direct users to use a different architecture where the machinery of the Spark Application is separate from the Application using Spark Results. This environment is created by running a Spark Driver like the SparkJobserver, SparkSQLThriftServer, Spark Notebook or Zepplin as a separate process. These programs are designed with their own infrastructure to allow external third parties to connect to them. End users can write thin-client applications connecting to these Spark Drivers. For the SparkJobserver applications can be executed via Rest Requests, the SparkSQLThriftServer allows for JDBC and Zepplin even allows the generation of embeddable HTML forms and graphs which can be utilized in any website. In all of these cases it should be noted that there is still a Spark Drivers with Executors that are tightly coupled but the end user is completely decoupled from this fact. All of these applications (Jobserver, Thriftserver, Zepplin) are also launched with Spark Submit which I will argue is really the only correct way to launch a Spark Application.


## Why is Spark Submit the only correct way to launch a Spark App?
Spark Submit is a terribly misnamed and overloaded function but it is simply put the only real supported way to run a Spark Application. It should be called "SparkApplicationLauncher" but Spark has many misnamed components (see Spark Master). In fact OSS Spark added a programatic api for running [Spark Applications](http://spark.apache.org/docs/latest/api/scala/index.html#org.apache.spark.launcher.SparkLauncher) which is actually called `Spark Launcher.` Under the hood this (basicaly undocumented) api also just just ends up calling [Spark Submit](https://github.com/apache/spark/blob/master/launcher/src/main/java/org/apache/spark/lahttps://github.com/apache/spark/blob/master/python/pyspark/java_gateway.py#L49). SparkR? Calls [Spark Submit]( https://github.com/apache/spark/blob/a36a76ac43c36a3b897a748bd9f138b629dbc684/bin/sparkR#L26). This is obviously a very popular script but it is popular for a reason.

Spark Submit has a variety of features that are extremely important for running a distributed cluster. It allows for configuration from the CLI of almost all parameters related to resource allocation and acquisition. This means that there is no need to hardcode in any environment specific variables into the application. Classpaths are automatically and correctly set up on both the driver and executor JVMS. Spark actually uses several classloaders when operating and having classes on the wrong classpath or missing resources can cause all sorts of opaque errors. In addition it correctly places newly added libraries, packages and even Maven Artifacts and all their dependencies on all relevant classpaths. But most important for users of DSE is that `dse spark-submit` is where the setup and configure all of the DSE specific modifications occurs. This includes Security, DSE Only DataTypes, Solr Integration Classes and automatic connection to (CFS and DSEFS), Cassandra Hive Metastore integration and others. Without using Spark Submit all of the above and all Spark parameters  would have to be set manually and would need to be updated on every DSE/Spark version update to be correct. 


## What about --deploy-mode cluster?

The --deploy-mode cluster option is a special spark-submit mode designed for actually running the Spark Driver within the Spark Cluster and not on the client running `spark-submit`. This could be considered an actual “submission” unlike the default value (client) which keeps the Spark Driver on the client issuing `spark-submit`. Instead of running the application from the client machine, the `spark-submit` request and all relevant information are sent to the Spark Master. The Spark Master then chooses a worker to execute the submission and the Driver ends up running as an independent process under a Worker’s supervision. The client is given an “identifier” for this process and the submission is complete. This can be useful if a Spark Application needs to be started from a remote machine because it still keeps all resources of the newly created application within the cluster. In addition there is a `supervise` flag for this mode which will restart failed drivers. Invoking this should still be done through `dse Spark Submit` for getting the correct configuration options and DSE specific enhancements.

## Cheat Sheet

### Requirement: I want to run SQL from many clients against a single set of resources
Example Use Cases: BI Tools, Exploratory Analysis
SparkDriver: Spark SQL Thrift Server
ClientApplication: Java application using JDBC (beeline, simba)

### Requirement: I want to run custom code from multiple clients against a single set of resources
Example Use Cases: Custom Algorithms against Big Data, Custom Batch Jobs
Spark Driver: Spark Job Server
ClientApplication: CURL, any HTTP Client

### Requirement: I want to run SQL/ML/Custom Code from a batch job against an exclusive set of resources
Example Use Cases: ETL between Mysql and C*, Daily Report Aggregates
ClientApplication / SparkDriver: User written Application utilizing sqlContext(1.6)/SparkSession(2.0)
This should most likely be submitted by a general purpose job scheduler

### Requirement: I am running a Streaming Application
Example Use Case: Processing clickstreams from kafka
ClientApplication/ SparkDriver: User written application
This should be submitted in --deploy mode cluster --supervise for HA

