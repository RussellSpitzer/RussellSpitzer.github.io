---
title: Can I use Spark SQL to get Low Latency Cassandra Requests
layout: post
comments: True
tags:
 - Spark
---

I had a great time at DataStax Accelerate and got asked a lot of great
questions about Cassandra and Spark. I'll post some the most common ones and 
their answers here for posterity.
---
                          
                          
## Can I user Spark SQL to get Low Latency Cassandra Requests?

TLDR; No

Sometimes when folks hear about SparkSQL they think they've just solved all
of their Cassandra data modeling questions. After all, SparkSQL provides an
ANSI SQL interface to Cassandra, so shouldn't we be able to just move our data
in to C* in whatever form we want and have great latency? Unfortunately, the
answer is no for a variety of reasons.

1. SparkSQL requesets are not low latency operations. To begin with, SparkSQL and Spark in
General, function with a lot of extra network communication not required for single machine
systems. This means even for requests which aren't using a huge amount of data, we pay 
an additional cost for setting up, planning, and distributing the metadata required to run a Spark Job.
This can greatly increase the latency of a request which could have run in CQL
directly and shipped directly to a C* server.

2. For requests that require a large amount of data, SparkSQL will default to doing
full table scans on the underlying DataSources. This means that a request on a single
table will most likely require reading the entire table into Spark to answer the question. This 
basically eliminates our ability to do anything with sub second (or even sub hour) latency
for large requests.

3. When performing joins in most cases Spark needs to do a network shuffle. A sort-merge 
Shuffle in Spark requires writing the join to disk and then sending various "shuffle files"
to other machines to be combined. This is tremendously expensive and basically eliminates
the ability to do any rapid joins in SparkSQL.

SparkSQL is there to enable queries that would otherwise be impossible, but if you
are trying to rely on it to sub 4ms arbitrary queries, you will be sorely disappointed. Spark
is a great tool, but to get the most out of your real time applications you will still
need to model your data to fit your requests.
