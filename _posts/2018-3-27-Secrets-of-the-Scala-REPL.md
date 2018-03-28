---
title: Secrets of the Scala REPL 
layout: post
comments: True
tags:
 - Spark
 - Scala
 - Lies my compiler told me 
---

Scala 2.11 from here on out!

Recently a co-worker of mine reported an issue with extending a 
specific class. The error reported that, via reflection, there was
no 0-arg constructor and that the parent api expected there to be one. I
asked whether or not such a constructor was implemented. Since I have great
co-workers, an example was quickly produced which reproduced the error
and also had a 0-arg constructor. We were confused for a moment until they
mentioned that they were pasting this into the Scala REPL. I realized that 
REPL was doing some undercover magic that was messing this up.

---

## Background

The Spark REPL (Read Evaluate Print Loop) lets you type in lines of Scala
code which get compiled the moment you hit enter. This should sound amazing, normally
we have compile our code, go through some annoying build process, and start a
brand new process to actually see if things work. The REPL seems to do away with
all of that ... but how does it actually accomplish this?

## Hidden State

When you compile lines in the REPL, subsequent lines can reference previous ones,
even though they were compiled at different times. This is possible because the
Scala REPL is secretly hiding all of that previously compiled information in every
new line we compile.

For example

```scala
//Line 1
val x = 5  
// x: Int = 5

//Line 2
val y = x
// y: Int = 5
```

When we refer to X in line 2, the REPL is internally checking previous compiled lines
to see if "x" is ever actually defined. This can kind of be thought of as each line 
importing the context of the previous line into its compilation. 

This is all well and good, but what happens we define a class?

## Class X: More than meets the Eye

```scala
scala> class X() {}
defined class X
```

Here we have a simple class with a no-arg constructor.

```scala
new X()
//res7: X = X@2a742ee4

new X()
//res8: X = X@7fec354
```

"But Russell that is obviously a no arg constructor, what are you talking about."

This is where the REPL is actually lying to us. Now it can't guarantee that in that
class we aren't using values from previous lines so it's going to tweak our
class a bit to make sure it has a reference to those other values. We don't notice
this because it also sneakily puts that hidden state into our constructor calls even when
we don't specify it.

This probably sounds a bit like I'm a conspiracy theorist ... but let me pull back
the curtains.

```scala
val xClass = new X().getClass
//xClass: Class[_ <: X] = class X

xClass.getConstructors
//res0: Array[java.lang.reflect.Constructor[_]] = Array(public X($iw))
//public X($iw) 
// $iw <---------- WHAT!
```

*$iw* an enemy you have probably seen multiple times in REPL Exceptions. Even though
you have never typed it, and never even really thought about it, it has always been there,
hiding in the darkness.

The Conspiracy is real and stopping you from having an actual 0 arg constructor! This 
means any class you ever make inside the Scala (2.11) REPL or a REPL derived from it 
like the Spark REPL will have secret parameters. 

As a workaround you can always compile your 0-arg classes outside of the REPL and
load the on the classpath. This will preserve their 0-ness and prevent the compiler
from adding hidden parameters.

