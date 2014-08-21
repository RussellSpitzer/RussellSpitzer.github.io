---
title: Setting up github.io.pages
layout: post
---
## Setting up github.io.pages with Jekyll
I was a little tired of how difficult it was for me to manage my wordpress
style blog and I love git. So after I saw a couple of my friends with their
awesome github.io.pages blogs I knew I needed one as well.

Accomplishing this took a few steps. First I followed the tutorial for setting
up my github.io account from [pages.github.com](https://pages.github.com/). I then created a
`CNAME` file to redirect to my personal domain and filed for a `CNAME` change with my
DNS. 

With the routing setup I realized I would like to have some sort of blogging framework around the pages
interface. The site recommeneded jekyll so I installed that following their instructions as well. This unfortunately just
left me with a blank page that said `hello world` so I then found this [tutorial](https://www.andrewmunsell.com/tutorials/jekyll-by-example/tutorial)
for Jekyll. 

Unfortunately this tutorial is slightly out of date as it references an older version of bootstrap
but I was able to convert most of the code to work with bootstrap 3.2.0. I then implemented the blog template
avalible on the [boostrap site](http://getbootstrap.com/examples/blog/) to work inside of my Jekyll framework. I split up the code into a nice rough
draft and it's commited [here](https://github.com/RussellSpitzer/RussellSpitzer.github.io). Now I have a 
framework and hopefully all of this will be useful for my future notes to my self.