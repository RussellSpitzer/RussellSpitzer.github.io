---
title: It isn't fast enough
layout: post
tags:
 - rant
 - performance
---

## It isn't fast enough

I'm often confronted with people asking my why a certain technology or program isn't fast enough. This is
a good question since we should always be interested in making things fast. But usually I hear these
questions in response to a perceived slowness which is hard to define or can only be explained in terms
of other technologies. This seems to happen a lot as various companies strive for a [lambda architecture](http://lambda-architecture.net/),
people want all the convenience of a traditional RDBMS with the the additional benefits of linear scaling,
fault tolerance, consistency, speed,  etc ...

Usually a question will be phrased in the following way, "When I do X query on an RDBMS it is fast, why 
is it slow on this system?" or "Why is this in-memory queue so much faster than this database which persists to 
disk?" I think these questions are coming from the idea that we have reached a technological point where
you can have your cake and eat it too. The CAP theorem still exists, hard drives are still slow, and when
you build any system be it distributed or not, you have to make a large number of trade-offs.

## Trade-offs

The most basic example of this I can think of is the speed difference between reading data from a database
and reading it from a flat file. I'll be speaking about this in generalities but these properties are generally
true of all file. Reading the entire contents of a flat file is faster than reading the entire contents
of a database (given that the data to be queried is persisted to a physical disk.) The reason behind this 
is because these two methods of data persistence are both making different trade-offs to get different benefits. 

Storing your data in flat files (in hdfs or just a normal fs) makes it difficult to insert arbitrary new data unless
you are only going to append to the end of the file. Reading specific values from a file will require some
kind of sorting or a full scan to determine whether or not it exists. On the other hand, loading the entire
contents of the file will be extremely fast since all of the data should be relatively contiguous on disk. So
for some applications, like counting the total number of pieces of data in a set, keeping all of your data in
a flat file system could be the right choice.

A generic database needs to keep it's information in a structured format. This makes it difficult to get large amounts
of data out of the system since it's been designed to make small well defined queries quickly. Databases are also 
designed in that way making small changes to the data or retrieving tiny parts of it is extremely fast. This means
for other applications, like quickly and repeatedly asking small well defined questions, using a database makes
more sense. 


## Apples and Oranges

Because of the various trade-offs different systems and methodologies it is almost always a boring question
when someone asks why is this Queue faster than this Database or vice versa. In-memory systems will always be faster
than those that require persisting to disk. Unstructured data will always be faster to write to than structured.
Reading will always be faster for unstructured. A queue will almost always be able to deal with pushing and
popping faster than a database can, but will lack the ability to scan within the queue. The real question to be asking
is for the particular application "What properties are most important." Speed should just be one component in
a spectrum of requirements.



