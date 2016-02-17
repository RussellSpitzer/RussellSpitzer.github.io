---
title: Folding with Spark
layout: post
comments: True
tags:
 - Fold
 - Spark
 - Scala
---

---
I felt the need to write this post after I read the [blog post](http://blog.madhukaraphatak.com/spark-rdd-fold/)
which did a great job at explaining how `fold` and `foldByKey` worked. The only thing I thought 
was missing from this rundown was a bit of detail on how these operations work *differently* than 
their scala counterparts.

---

From the original api you might think that `fold` and `foldByKey` executed in Scala and
executed in a Spark Closure would act the same way and for most cases they do. Lets take a look
at a few examples.

## Finding the minimum value from a list

```scala
//Fold function = Math.min(acc, element)

scala> sc.parallelize(1 to 10).fold(1000){(acc,element) => Math.min(acc, element)}
res1: Int = 1

scala> (1 to 10).fold(1000){(acc,element) => Math.min(acc, element)}
res2: Int = 1
```
    
## Finding the sum of elements in a list

```scala
//Fold function = acc + element

scala> sc.parallelize(1 to 10)
         .fold(0){(acc,element) => acc + element}
res3: Int = 55

scala> (1 to 10)
         .fold(0){(acc,element) => acc + element}
res4: Int = 55
```

    
In these examples I get the same answer whether I perform the operation on an RDD or do it on
a collection. But there is a class of functions that you can write which will not have the same 
answer if run in a distributed fold vs a local one. Here is an example of a "Counting" fold.

## "Counting" elements in a list 

```scala
//Fold function = acc + 1

scala> (1 to 10).fold(0){(acc, ele) => acc + 1}
res5: Int = 10

scala> sc.parallelize(1 to 10).fold(0){(acc,element) => acc + 1}
res6: Int = 8
```
    
I'm pretty sure 8 isn't 10, and you may get a different answer on your machine (I'll go into why in 
a moment.) Too find out why we can actually walk though the steps spark is doing. To have our debug
print in the same JVM as the driver we'll run the spark-shell in `local` mode. 

## Folding intra partition and inter partition

```scala
scala> sc.parallelize(1 to 10).fold(0){ (acc,element) => println(s"$acc : $element"); acc + 1}
0 : 3
0 : 1
0 : 6
0 : 8
0 : 7
0 : 4
1 : 5
0 : 2
0 : 9
1 : 10
0 : 1
1 : 1
2 : 1
3 : 1
4 : 2
5 : 1
6 : 2
7 : 1
res13: Int = 8
```
    
1 : 10? 7 : 1? Why do we see element `1` so many times! Something strange does seem to be afoot. 
The answer comes in the Spark 
[Scala Docs](http://spark.apache.org/docs/latest/api/scala/index.html#org.apache.spark.rdd.RDD) 
for the `fold` and `foldByKey` operations. 

> Aggregate the elements of each partition, and then the results for all the partitions, 
using a given associative and commutative function and a neutral "zero value". The function 
op(t1, t2) is allowed to modify t1 and return it as its result value to avoid object allocation; 
however, it should not modify t2.

> This behaves somewhat differently from fold operations implemented for non-distributed collections 
in functional languages like Scala. This fold operation may be applied to partitions individually, 
and then fold those results into the final result, rather than apply the fold to each element 
sequentially in some defined ordering. For functions that are not commutative, the result may 
differ from that of a fold applied to a non-distributed collection.

This lets us know that when Spark is doing the fold it's actually doing multiple folds in parallel
one within each task. This means the number of tasks created will adjust our answer when we do a 
non-commutitive operation like this particular count.

Here is an example:
```scala
scala> sc.parallelize(1 to 10, 100).fold(0){ (acc,element) => acc +1}
res15: Int = 100

scala> sc.parallelize(1 to 10, 40).fold(0){ (acc,element) => acc +1}
res16: Int = 40

scala> sc.parallelize(1 to 10, 20).fold(0){ (acc,element) => acc +1}
res17: Int = 20

scala> sc.parallelize(1 to 10, 1).fold(0){ (acc,element) => acc +1}
res18: Int = 1

scala> sc.parallelize(1 to 10, 4).fold(0){ (acc,element) => acc +1}
res19: Int = 4
```
    
Notice how the number of partitions (The second parameter of parallelize) we are working with 
changes the final total! This is the reason why your answer may have been different than my original 
eight. I ran this example on my MacBook which has 8 cores, setting the default parallelism level to 8. 
This made 8 partitions, which translates to 8 tasks. Each task dutifully counted the elements in it's list, 
but then when those results were combined we ended up doing something that looked like

##Folding Partition Results

```
// (acc, ele) => acc +1
(0, totalFromPartition1) => 0 + 1 = 1
(1, totalFromPartition2) => 1 + 1 = 2
...
(7, totalFromPartition8) => 7 + 1 = 8
```
    
There is of course an easy way around this, if we are actually trying to count we need to do so in
the usual word count map-reduce sort of fashion, where each element has it's count mapped in the original
state.

Lets pretend for example we want to find the average of a list of numbers, first we would map each
element to it's count (1) then use a single fold to both sum the elements and the counts at the
same time.

##Counting in a commutitive way

```scala
scala> sc.parallelize(1 to 10)
         .map( x=> (x,1))
         .fold(0,0){(acc,element) => (acc._1 + element._1, acc._2 + element._2)}
res24: (Int, Int) = (55,10)
```
    
And we get the result we expected! These counting examples were of course a bit contrivied, but this
same problem comes into play if you are only trying to count a subset of elements in your fold. So 
when using `fold` and `foldByKey` make sure you don't accidentally write in a non-commutative closure. 
The best way to think about this is that the "ele" portion of your fold function will sometimes 
be the acc from a sub fold.

