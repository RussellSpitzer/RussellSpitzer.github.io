---
title: Concurrency in Spark
layout: post
comments: True
tags:
 - Spark
 - Cassandra
 - Concurrency
 
---

How does Spark actually execute code and how can I do concurrent work within a Spark execution pipeline?
Spark is complicated, Concurrency is complicated, and distributed systems are also complicated. To
answer some common questions I'm going to go over some basic details on what Spark is doing and 
how you can control it.

---

## EDIT

We have found that this pattern is even better and are using it in the Spark Cassandra Connector

```scala
  /** Prefetches a batchSize of elements at a time **/
  protected def slidingPrefetchIterator[T](it: Iterator[Future[T]], batchSize: Int): Iterator[T] = {
    val (firstElements, lastElement) =  it
      .grouped(batchSize)
      .sliding(2)
      .span(_ => it.hasNext)

    (firstElements.map(_.head) ++ lastElement.flatten).flatten.map(_.get)
  }
```

Which uses a similar pattern but insures we have even more futures in flight (based on batch size)

---



* Jump to [Cassandra](#concurrency-with-the-cassandra-java-driver) Specific code
* Jump to [General Explanation](#concurrency-in-spark)


Example without explanation for general purpose concurrency in a Spark task.
##### General Purpose Parallel Execution in Spark

 ```scala
 /** A singleton object that controls the parallelism on a Single Executor JVM */
object ThreadedConcurrentContext {
  import scala.util._
  import scala.concurrent._
  import scala.concurrent.duration.Duration
  import scala.concurrent.duration.Duration._
  import scala.concurrent.ExecutionContext.Implicits.global

  /** Wraps a code block in a Future and returns the future */
  def executeAsync[T](f: => T): Future[T] = {
    Future(f)
  }

  /** Awaits only a set of elements at a time. Instead of waiting for the entire batch
    * to finish waits only for the head element before requesting the next future*/
  def awaitSliding[T](it: Iterator[Future[T]], batchSize: Int = 3, timeout: Duration = Inf): Iterator[T] = {
    val slidingIterator = it.sliding(batchSize - 1) //Our look ahead (hasNext) will auto start the nth future in the batch
    val (initIterator, tailIterator) = slidingIterator.span(_ => slidingIterator.hasNext)
    initIterator.map( futureBatch => Await.result(futureBatch.head, timeout)) ++
      tailIterator.flatMap( lastBatch => Await.result(Future.sequence(lastBatch), timeout))
  }
}
```
  
  Usage Looks Like
  
```scala
sc.parallelize(1 to 10)
  .map(fastFoo)
  .map(x => ThreadedConcurrentContext.executeAsync(slowFoo(x))) //Async block goes here
  .mapPartitions( it => ThreadedConcurrentContext.awaitSliding(it)) //
  .foreach( x => println(s"Finishing with $x"))
```

## Concurrency in Spark

Spark runs pieces of work called `tasks` inside of `executor jvms`. The amount of `tasks` running at
the same time is controlled by the number of `cores` advertised by the executor. The setting of this
 is defined in your job submission and in general is constant unless you are using 
 [dyanmic allocation](http://spark.apache.org/docs/latest/job-scheduling.html#dynamic-resource-allocation).
 Each `task` is generally just a single thread which is running the seriailzed code written for that
 particular `task`. The code within the task will be single-threaded and synchronus unless you code
 something to have it not be synchronous. Now given that you will have threads for every core, the 
 application will be running work concurrently but you may want to increase the parallelism.
 
Let's start out with the most basic example. Imagine I have two functions, one is fast and one
is slow.  (Note: All of the following examples are run in the Spark-Shell with the master set
to `local[1]` so that the only explicitly programmed concurrency will be present.)

```scala
/** Waits five second then returns the input. Represents some kind of IO operation **/
def slowFoo[T](x: T):T = { 
  println(s"slowFoo start ($x)")
  Thread.sleep(5000)
  println(s"slowFoo end($x)")
  x 
}
  
/** Immediately returns the input **/
def fastFoo[T](x: T): T = { 
  println(s"fastFoo($x)")
  x 
}
```

My slow operation here represents: reading from a database (like Cassandra); accessing a url; or some other
 long but cpu-idle operation. The fast operation is something that is purely cpu bound so that running
  num-core threads would max out our throughput. I want to chain these operations together but
I don't want to wait synchronously on each `slowFoo` to do the next `fastFoo`. 

### No Concurrency

Applying these functions in order shows that we get a strict sequential execution. Each
 element is passed 1 at a time through `fastFoo` and then `slowFoo`. We never call 
 `fastFoo(n+1)` until `slowFoo(n)` has finished. 

```scala
scala> sc.parallelize(1 to 10).map(fastFoo).map(slowFoo).collect
fastFoo(1)
slowFoo start (1)
slowFoo end(1)
fastFoo(2)
slowFoo start (2)
slowFoo end(2)
fastFoo(3)
slowFoo start (3)
  ...
slowFoo end(10)
res1: Array[Int] = Array(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
*/
```

Under the hood this happens because Spark's map operator basically just takes the
function it applies to the iterator generated by the previous partition and composes 
[it](https://github.com/apache/spark/blob/v2.0.2/core/src/main/scala/org/apache/spark/rdd/MapPartitionsRDD.scala#L38).

Basically `it.map(g).map(f)` becomes `it.map(f(g(_))`. Elements are processed
sequentially, blocking until each element is completely processed by the composed function.

### Concurrency using Futures

Futures are a means of doing asynchronous programming in Scala. They provide a native way
for us to express concurrent actions without having to deal with the nitty gritty of
actually setting up threads. We can set up a wrapper which uses futures
like so:

##### Unbounded Concurrent Execution Ignoring Results

```scala
/** A singleton object that controls the parallelism on a Single Executor JVM, Using the GlobalContext **/
object ConcurrentContext {
  import scala.util._
  import scala.concurrent._
  import scala.concurrent.ExecutionContext.Implicits.global
  /** Wraps a code block in a Future and returns the future */
  def executeAsync[T](f: => T): Future[T] = {
    Future(f)
  }
}
```

Creating an object to accomplish this allows us to switch the executionContext for this code
and allow us to control the concurrency at a JVM level. Each executor JVM will only make 
one instance of this `ConcurrentContext` which means if we switch to a threadpool based
ExecutionContext it can be shared by all tasks running on the same machine.

This context will use the 
[global execution context](http://docs.scala-lang.org/overviews/core/futures.html#the-global-execution-context.) 
on the executor to do work on many threads at a time. 

Our `executeAsync` method simply takes a code block and transforms it into a 
task to be run on the global context (implicitly imported and set). The result is left
in a Future object which we can poll at our leisure.

If we wrap our slowFoo in the executeAsync we see that all the tasks are queued
and our code returns immediately.

```scala
scala> sc.parallelize( 1 to 10).map(fastFoo).map(x => ConcurrentContext.executeAsync(slowFoo(x))).collect
fastFoo(1)
fastFoo(2)
fastFoo(3)
fastFoo(4)
slowFoo start (2)
slowFoo start (1)
fastFoo(5)
slowFoo start (3)
  ...
res6: Array[scala.concurrent.Future[Int]] = Array(List(), List(), List(), List(), List(), List(), List(), List(), List(), List())

scala>  // Our request returns
//Then 5 seconds later
slowFoo end(1)
slowFoo end(7)
slowFoo end(8)
slowFoo end(4)
slowFoo start (10)
slowFoo end(5)
...
```

While it's nice that everything is going on in parallel this has a few fatal flaws.
 1. We have no form of error handling. If something goes wrong we are basically lost
 and Spark will not retry the task.
 
 2. The Spark task completes before all the work is done. This means that if the application
 shut down it could close out our executors while they are still processing work.
 
 3. We have no way of feeding the results of this asynchronous work into another process 
 meaning we lose the results as well
 
 4. Unlimited futures flying around can lead to the overhead of their managment decreasing
 throughput
 
To fix 1 - 3 we need to actually end up waiting on our `Futures` to complete but this is
where things start getting tricky.

#### Unbounded Concurrent Execution Awaiting Results
```scala
/** A singleton object that controls the parallelism on a Single Executor JVM, Using the GlobalContext**/
object ConcurrentContext {
   import java.util.concurrent.Executors
   import scala.util._
   import scala.concurrent._
   import scala.concurrent.ExecutionContext.Implicits.global
   import scala.concurrent.duration.Duration
   import scala.concurrent.duration.Duration._
   /** Wraps a code block in a Future and returns the future */
   def executeAsync[T](f: => T): Future[T] = {
     Future(f)
   }
   
   /** Awaits an entire sequence of futures and returns an iterator. This will
    wait for all futures to complete before returning**/
   def awaitAll[T](it: Iterator[Future[T]], timeout: Duration = Inf) = {
     Await.result(Future.sequence(it), timeout)
   }
   
 }
```

Here we introduce a method `awaitAll` to actually make sure that our futures finish
and give us back the resultant values. This means that our Spark Job will not complete
until all of our Futures have completed as we see in the following run.

```scala
sc.parallelize( 1 to 10)
  .map(fastFoo)
  .map(x => ConcurrentContext.executeAsync(slowFoo(x)))
  .mapPartitions( it => ConcurrentContext.awaitAll(it))
  .foreach( x => println(s"Finishing with $x"))

/**
fastFoo(1)
fastFoo(2)
fastFoo(3)
slowFoo start (1)
fastFoo(4)
slowFoo start (3)
lowFoo end(3)
slowFoo end(2)
slowFoo start (9)
slowFoo start (10)
//All Futures are started
slowFoo end(6)
slowFoo end(8)
slowFoo end(7)
...
slowFoo end(4)
slowFoo end(5)
slowFoo end(10)
slowFoo end(9)
//We start waiting until all futures are completed
Finishing with 1
Finishing with 2
...
inishing with 8
Finishing with 9
Finishing with 10
//Command returns
```

This is better but we still have some issues. The code behind `Futures.sequence` will greedly
 grab all of our futures at once. This means the amount of concurrent work that is being run
 is unbounded. This issue is compounded by the fact that we need to hold the results of all
 the futures in memory at the same time before we return *any* of the results. In practical
 terms this means that you will have OOM's if the set we are waiting on here is large. For example,
 `rdd.map(parallelThing).filter(x < 1).count` would benefit from filtering the records as
 they are calculated rather than getting all the values then filtering.
 
#### Batched Concurrent Execution Awaiting Results

```scala
/** A singleton object that controls the parallelism on a Single Executor JVM, Using the GlobalContext**/
object ConcurrentContext {
   import scala.util._
   import scala.concurrent._
   import scala.concurrent.ExecutionContext.Implicits.global
   import scala.concurrent.duration.Duration
   import scala.concurrent.duration.Duration._
   /** Wraps a code block in a Future and returns the future */
   def executeAsync[T](f: => T): Future[T] = {
     Future(f)
   }
   
   /** Awaits only a set of elements at a time. At most batchSize futures will ever
   * be in memory at a time*/
   def awaitBatch[T](it: Iterator[Future[T]], batchSize: Int = 3, timeout: Duration = Inf) = {
     it.grouped(batchSize)
       .map(batch => Future.sequence(batch))
       .flatMap(futureBatch => Await.result(futureBatch, timeout))
   }
 }
```

Now instead of waiting for the entire task at once we break it up into chunks then await
each chunk. This means we will never have more than `batchSize` tasks in progress at a time
solving our "unbounded parallelism" and "having all records in memory" issues.

```scala
sc.parallelize( 1 to 10)
  .map(fastFoo)
  .map(x => ConcurrentContext.executeAsync(slowFoo(x)))
  .mapPartitions( it => ConcurrentContext.awaitAll(it))
  .foreach( x => println(s"Finishing with $x"))
/* 
fastFoo(1)
fastFoo(2)
slowFoo start (1)
...
slowFoo end(1)
Finishing with 1
Finishing with 2
Finishing with 3
fastFoo(4)
fastFoo(5)
slowFoo start (4)
...
slowFoo end(4)
Finishing with 4
Finishing with 5
Finishing with 6
fastFoo(7)
...
Finishing with (10)
*/
```

Notice how we are only ever working on 3 elements at a time? Unfortunately we are blocking 
on every batch. Every batch must wait for the previous batch to completely finish before any
of the work in the next batch can start. We can do better than this with a few different
methods. Here is one possibility where the ordering is maintained but we keep a rolling buffer
of futures to be completed.
 
#### Sliding Concurrent Execution Awaiting Results with Separate Executor
 ```scala
 /** A singleton object that controls the parallelism on a Single Executor JVM
 */
object ThreadedConcurrentContext {
  import scala.util._
  import scala.concurrent._
  import scala.concurrent.duration.Duration
  import scala.concurrent.duration.Duration._
  import scala.concurrent.ExecutionContext.Implicits.global

  /** Wraps a code block in a Future and returns the future */
  def executeAsync[T](f: => T): Future[T] = {
    Future(f)(ec)
  }

  /** Awaits only a set of elements at a time. Instead of waiting for the entire batch
    * to finish waits only for the head element before requesting the next future*/
  def awaitSliding[T](it: Iterator[Future[T]], batchSize: Int = 3, timeout: Duration = Inf): Iterator[T] = {
    val slidingIterator = it.sliding(batchSize - 1).withPartial(true) //Our look ahead (hasNext) will auto start the nth future in the batch
    val (initIterator, tailIterator) = slidingIterator.span(_ => slidingIterator.hasNext)
    initIterator.map( futureBatch => Await.result(futureBatch.head, timeout)) ++
      tailIterator.flatMap( lastBatch => Await.result(Future.sequence(lastBatch), timeout))
  }
}
```
This gives us a order maintaining buffered set of Futures. The sliding batch makes sure 
that the iterator has queued up to `batchSize` futures while still making sure that 
we pass along the head element as soon as we can. The `span` is required to make sure that
we wait on the last sliding window for it to finish completely. 
  
```scala
  sc.parallelize( 1 to 10).map(fastFoo).map(x => ThreadedConcurrentContext.executeAsync(slowFoo(x))).mapPartitions( it => ThreadedConcurrentContext.awaitSliding(it)).foreach( x => println(s"Finishing with $x"))
  fastFoo(1)
  fastFoo(2)
  slowFoo start (1)
  fastFoo(3)
  slowFoo start (2)
  slowFoo start (3)
  slowFoo end(3)
  slowFoo end(1)
  slowFoo end(2)
  //The moment we finish with 1 we can move on to the next future
  Finishing with 1
  //Next future is queued
  fastFoo(4)
  Finishing with 2
  fastFoo(5)
  slowFoo start (4)
  ...
```

At this point you may want to consider switching out the Global Execution context which is used in 
the example with a executor tailored to your use case, but for most things this should be sufficient.
See [Scala Futures docs](http://docs.scala-lang.org/overviews/core/futures.html#adapting-a-java-executor)
  
## Concurrency with the Cassandra Java Driver
 
 The lessons from the above examples can be applied to using the C* java driver as well. Since
 the C* java driver uses Guava we can just use those futures in a very similar manner. The Spark
 Cassandra provides means to do most of this automatically through `cassandraTable` and 
 `saveToCassandra` but this pattern can be used if you are dealing with custom queries that may
 not fit directly into those paradigms.
 
```scala
import com.datastax.spark.connector.cql.CassandraConnector
val rdd = sc.parallelize(1 to 100000)
val connector = CassandraConnector(sc.getConf)
val batchSize = 1000
// Use the serializable CassandraConnector to establish Session pools on the spark executors
val resultSetRDD = rdd.mapPartitions{ it => connector.withSessionDo { 
  session =>
    // Use the prepared statement cache to either make or retrieve a prepared statement
    val ps = session.prepare("INSERT INTO test.kv (k,v) VALUES (?, ?)")
    // Setup the iterator to bind values into our prepared statement
    val boundStatementIterator = it.map(x => ps.bind(x: java.lang.Integer,x: java.lang.Integer))
    // Setup the iterator to executeAsync our statements, returning ResultSetFutures
    val resultSetFutureIterator = boundStatementIterator.map(session.executeAsync)
    // Perform the sliding technique to queue only a set amount of records at a time
    val slidingIterator = resultSetFutureIterator.sliding(batchSize - 1)
    val (initIterator, tailIterator) = slidingIterator.span(_ => slidingIterator.hasNext)
    initIterator.map(futureBatch => futureBatch.head.getUninterruptibly) ++
      tailIterator.flatMap(lastBatch => lastBatch.map(_.getUninterruptibly))
  }
}
//If we were doing some kind of select this is where we could access values from inside the ResultSets
//But in this case we'll just do a count to let the inserts get computed
resultSetRDD.count

```

In this code sample we basically use the same sliding trick to make sure we are always running a set
amount of queries asynchronously. The `getUninterruptibly` method is our way of blocking the slide
method from moving onto the next `executeAsync` just like `Await.result` did in the Scala Futures 
example.


## Conclusion

It's not always right to try to increase parallelism inside of a Spark Task but these examples
will hopefully help you out the next time you are attempting to fold in some asynchronous code
into your Spark pipeline.





