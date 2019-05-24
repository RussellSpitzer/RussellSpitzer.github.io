---
title: What language should I use with Spark?
layout: post
comments: True
tags:
 - Spark
---

I had a great time at DataStax Accelerate and got asked a lot of great
questions about Cassandra and Spark. I'll post some the most common ones and 
their answers here for posterity.
---
                          
                          
## What language should I use when working with Spark?
  
One of the greatest features of Spark is the Dataframe API. It's amazing and
available in a variety of languages: R, Python, Java, Scala, and there is even work
being done in .net! One of the drawbacks of RDD's was that depending on the
language you choose, your performance could be dramatically different (Scala and Java = Fast; Python = Slow) 
but in DataFrames *every language will perform nearly identically* (with some caveats.)

The reason that Dataframes provide such consistent and excellent performance
is because they only describe *what* the application has to do at a very high
level. This description is then, regardless of language, transformed into highly
optimized Java code. This means that if we provide the same description of the problem
it does not matter what language we use. The end result of our operation will yield
the same optimized Java code!

The caveats are:

1. Any time you break out of built in DataFrame operations, like a 
"map" or "flatMap" and have to unencode your rows. The implementation goes
back to the native language you are using for the lambda. This means that if at all possible
you should avoid custom native language functions. This is actually a good
tip even if you are using Java/Scala applications as well, so try to stay away from "map" when
using DataFrames.

2.Initial paralleization of datasets can be different depending on the
native language. For example if you parallelize a python collection it will
need to be converted into Java objects before it can be turned into a DataFrame.
Usually you will not be parallelizing a large data set so this shouldn't be
a huge perf difference, but the schema may end up being different based on the language. For example
a Python numerical type doesn't have a direct analogue to a Java type, so parallelizing
a Java/Scala collection of numbers will probably result in "Integer" type in Spark
but Python numbers will end up as "BigIntger/Long" type.


