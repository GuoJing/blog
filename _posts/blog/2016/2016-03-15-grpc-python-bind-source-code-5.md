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
def insecure_channel(host, port):
  intermediary_low_channel = _intermediary_low.Channel(
      '%s:%d' % (host, port), None)
  return Channel(intermediary_low_channel._internal, intermediary_low_channel)  # pylint: disable=protected-access
{% endhighlight %}

{:.center}
grpc/beta/implementations.py

其中就是初始化了一个 Channel 对象。

{% highlight python %}
class Channel(object):
  def __init__(self, low_channel, intermediary_low_channel):
    self._low_channel = low_channel
    self._intermediary_low_channel = intermediary_low_channel
    self._connectivity_channel = _connectivity_channel.ConnectivityChannel(
        low_channel)
{% endhighlight %}

{:.center}
grpc/beta/implementations.py

初始化 Channel 对象就是初始化了几种不同类型的 Channel。到此为止，Channel 就已经结束了。

当然，Channel 不是那么简单。现在还需要回头结合 [Stub](/posts/grpc-python-bind-source-code-4/) 和 C Core 一齐来看。

### 相关文章

1. [Basic](/posts/grpc-python-bind-source-code-1/)
2. [Server](/posts/grpc-python-bind-source-code-2/)
3. [CompletionQueue](/posts/grpc-python-bind-source-code-3/)
4. [Stub](/posts/grpc-python-bind-source-code-4/)
5. [Channel](/posts/grpc-python-bind-source-code-5/)

### 有关 C Core 的笔记

1. [Notes of gRPC](https://github.com/GuoJing/book-notes/tree/master/grpc)

