---
title: Distributed Locks are Hard
layout: post
comments: True
tags:
 - Cassandra
 - Concurrency

---

I recently was answering a [Stack Overflow Question](http://stackoverflow.com/questions/41227921/cassandra-data-reappearing/41230313#41230313) which made me start thinking
a bit about locking and some assumptions made in Distributed systems. In this case we had
what I find is a pretty common error in distributed systems and particularly with Cassandra.

---

The code looked like this

```python
try:
    writeToCassandra(Lock)
except:
    deleteFromCassandra(Lock)
```

So why is this a problem? Let's start with the basics of Cassandra. A Cassandra Cluster
is built up of nodes of which subsets are responsible for replicating specific pieces of
data. When writing and reading data you are allowed to specify a `Consistency Level`(CL) on the client
which determines how many of these replicas must acknowledge your request before the client
considers it completed.

In a common scenario of having `Replication Factor`(RF) = 3 we would have 3 replicas
for every piece of data. If we attempt to write to this with a CL of ALL it would mean
the client would only report a success if all of the replicas acknowledged receiving the write
and were able to communicate this information back. There are other CLs which allow for waiting
for fewer responses but what is interesting is what happens when we fail to reach CL.

When the Client gets an exception we actually know very little about the state of the cluster. Without
acknowledgement the Cassandra cluster may have written our new value to anywhere between 0 and 3 replicas. This 
means even though our write "failed" the cluster may have actually accepted it. This leads to situations
were data which we did not think was successfully written is actually readable and present on the cluster. Since 
deletes are also writes to Cassandra this leads to some issues with the above code sample. Basically
we need to ask "What happens when the `deleteFromCassandra` portion fails?"


Let's imagine a few scenarios with Replicas A, B and C.

Client writes `lock` but an error is thrown. `lock` is present on all replicas but the client gets a 
timeout because that connection is lost or broken. This triggers our exception handling
block.

#### State of System
```
A[Lock], B[Lock], C[Lock]
```

The client gets the exception and issues the delete request, but this can also fail! This means the 
system can be in a variety of states.

#### 0 Successful Writes of the Delete
```
A[Lock], B[Lock], C[Lock] 
```
All `quorum` requests will see the Lock. There exists no combination of replicas which would show us 
the Lock has been removed. This means all future reads at any CL will witness that the Lock still exists.

#### 1 Successful Writes of the Delete

```
A[Lock], B[Lock], C[]
```

In this case we are still vulnerable. Any request which excludes C will 
miss the deletion. If only A and B are polled than we'll still see the lock existing. This means
CL of ONE and Quorum are vulnerable. Only CL `ALL` will be safe (of course we don't know if we)
are in this situation or the 0 write case. 

#### 2/3 Successful Writes of the Delete (Quorum CL Is Met)


```A[Lock/], B[], C[]```
 
 In this case we have once more lost the connection to the driver but 
 somehow succeeded internally in replicating the delete request. These 
 scenarios are the only ones in which we are actually safe and that 
 future reads will not see the Lock with a Quorum CL. For CL ONE we would still be 
 vulnerable if 2 of the writes were successful.

### Conclusion


One of the tricky things with situations like this is that if you fail do make 
your lock correctly because of network instability it is also unlikely that your 
correction will succeed since it has to work in the exact same environment. To make the
above code secure we would need to repeat our delete request at a high enough CL until we
get a full success from our cluster. Until we get a client success the system could still
be in any of the above states and the lock would still exists.

This may be an instance where CAS operations can be beneficial. The Paxos protocol
 lets Cassandra do minor IF X then SET Y requests. But in most 
cases it is better to not attempt to use distributing locking if at all possible.
