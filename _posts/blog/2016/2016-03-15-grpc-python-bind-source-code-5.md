---
layout:    post
title:     gRPC Python 源码浅析 - Channel
category:  blog
description: gRPC Python 源码
tags: gRPC Python Google Source Coding HTTP2 CompletionQueue
---
### Overview

在了解 Server 是怎么启动的，Client 是怎么创建一个 Call 传输 Ticket 之后，实际上还有很多盲点，最主要的盲点是为什么一个 Call 到 Server 就可以返回呢？这个过程还没有完全的了解清楚，所以需要了解 gRPC 中 Channel 的概念。

### Channel

在客户端创建 Client 的时候，需要创建 Channel 对象，代码如下。

{% highlight python %}
channel = implementations.insecure_channel(self.host, self.port)
stub = jedi_pb2.beta_create_JediService_stub(channel)
stub.SayHello()
{% endhighlight %}

{:.center}
sample.py

可见，stub 要使用，还是需要 Channel 的帮助的。当然，也给我们一些线索去看代码。

{% highlight python %}
{% endhighlight %}
