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
stub = hello_pb2.beta_create_HelloService_stub(channel)
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

初始化 Channel 对象就是初始化了几种不同类型的 Channel。而其中最重要的就是 *low_channel* 了。

{% highlight python %}
def insecure_channel(host, port):
  intermediary_low_channel = _intermediary_low.Channel(
      '%s:%d' % (host, port), None)
  # 这里 intermediary_low_channel._internal 就是在 _adapter._low
  return Channel(intermediary_low_channel._internal, intermediary_low_channel)  # pylint: disable=protected-access
{% endhighlight %}

{:.center}
grpc/beta/implementations.py

直接看 *_adapter._low*。

{% highlight python %}
class Channel(_types.Channel):

  def __init__(self, target, args, creds=None):
    args = list(args) + [
        (cygrpc.ChannelArgKey.primary_user_agent_string, _USER_AGENT)]
    args = cygrpc.ChannelArgs(
        cygrpc.ChannelArg(key, value) for key, value in args)
    # 创建一个 C Channel
    if creds is None:
      self.channel = cygrpc.Channel(target, args)
    else:
      self.channel = cygrpc.Channel(target, args, creds)
{% endhighlight %}

{:.center}
grpc/_adapter/_low.py

那么进入到 C Channel 里去看。

{% highlight python %}
cdef class Channel:

  def __cinit__(self, target, ChannelArgs arguments=None,
                ChannelCredentials channel_credentials=None):
    cdef grpc_channel_args *c_arguments = NULL
    self.c_channel = NULL
    self.references = []
    if arguments is not None:
      c_arguments = &arguments.c_args
    if isinstance(target, bytes):
      pass
    elif isinstance(target, basestring):
      target = target.encode()
    else:
      raise TypeError("expected target to be str or bytes")
    if channel_credentials is None:
      # 普通的创建 channel
      self.c_channel = grpc_insecure_channel_create(target, c_arguments,
                                                         NULL)
    else:
      # 创建加密的 channel
      self.c_channel = grpc_secure_channel_create(
          channel_credentials.c_credentials, target, c_arguments, NULL)
      self.references.append(channel_credentials)
    self.references.append(target)
    self.references.append(arguments)
{% endhighlight %}

{:.center}
grpc/_cython/_cygrpc/channel.pyx.pxi

到这里，Channel 反而很容易查看创建，那么直接扎到 C 代码里去看。

{% highlight c %}
grpc_channel *grpc_insecure_channel_create(const char *target,
                                           const grpc_channel_args *args,
                                           void *reserved) {
  grpc_channel *channel = NULL;
#define MAX_FILTERS 3
  // 创建 grpc_channel_filter
  const grpc_channel_filter *filters[MAX_FILTERS];
  grpc_resolver *resolver;
  subchannel_factory *f;
  grpc_exec_ctx exec_ctx = GRPC_EXEC_CTX_INIT;
  size_t n = 0;
  // n = 0
  // 如果 census 开启
  // channel 绑定 filter 为 grpc_client_census_filter
  if (grpc_channel_args_is_census_enabled(args)) {
    filters[n++] = &grpc_client_census_filter;
  }
  // 再次绑定 grpc_compres_filter
  filters[n++] = &grpc_compress_filter;
  // filter 数组下一个 filter 绑定 grpc_client_channel_filter
  filters[n++] = &grpc_client_channel_filter;
  GPR_ASSERT(n <= MAX_FILTERS);

  // 初始化 filters 之后，通过 filters 创建 channel
  channel =
      grpc_channel_create_from_filters(&exec_ctx, target, filters, n, args, 1);

  // f 为 subchannel_factory
  f = gpr_malloc(sizeof(*f));
  f->base.vtable = &subchannel_factory_vtable;
  gpr_ref_init(&f->refs, 1);
  f->merge_args = grpc_channel_args_copy(args);
  f->master = channel;
  GRPC_CHANNEL_INTERNAL_REF(f->master, "subchannel_factory");
  resolver = grpc_resolver_create(target, &f->base);
  if (!resolver) {
    GRPC_CHANNEL_INTERNAL_UNREF(&exec_ctx, f->master, "subchannel_factory");
    grpc_subchannel_factory_unref(&exec_ctx, &f->base);
    grpc_exec_ctx_finish(&exec_ctx);
    return NULL;
  }

  grpc_client_channel_set_resolver(
      &exec_ctx, grpc_channel_get_channel_stack(channel), resolver);
  GRPC_RESOLVER_UNREF(&exec_ctx, resolver, "create");
  grpc_subchannel_factory_unref(&exec_ctx, &f->base);

  grpc_exec_ctx_finish(&exec_ctx);

  return channel;
}
{% endhighlight %}

{:.center}
src/core/surface/channel_create.c

从上面我们可以创建一个 Channel。但是 Channel 的数据结构还比较复杂，所以我们需要画图来详细了解 Channel 和 Call 之间的关系。如果不清楚。还需要回头结合 [Stub](/posts/grpc-python-bind-source-code-4/) 和 C Core 一齐来看。

### Channel 结构体

Coming soon.

### Channel Stack

Coming soon.

### Call Stack

Coming soon.

### 相关文章

1. [Basic](/posts/grpc-python-bind-source-code-1/)
2. [Server](/posts/grpc-python-bind-source-code-2/)
3. [CompletionQueue](/posts/grpc-python-bind-source-code-3/)
4. [Stub](/posts/grpc-python-bind-source-code-4/)
5. [Channel](/posts/grpc-python-bind-source-code-5/)

### 有关 C Core 的笔记

1. [Notes of gRPC](https://github.com/GuoJing/book-notes/tree/master/grpc)

