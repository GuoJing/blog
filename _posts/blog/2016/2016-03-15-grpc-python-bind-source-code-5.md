---
layout:    post
title:     gRPC Python 源码浅析 - Channel
category:  blog
description: gRPC Python 源码
tags: gRPC Python Google Source Coding HTTP2 CompletionQueue
---
### Overview

此部分代码的基于 git log **0aa23d83ade7234d10fc27ea08b6713182ae996c** 分析。

在了解 Server 是怎么启动的，Client 是怎么创建一个 Call 传输 Ticket 之后，实际上还有很多盲点，最主要的盲点是为什么一个 Call 到 Server 就可以返回呢？这个过程还没有完全的了解清楚，所以需要了解 gRPC 中 Channel 的概念。

### Channel Stack

{% highlight c %}
struct grpc_channel_stack {
  grpc_stream_refcount refcount;
  size_t count;
  size_t call_stack_size;
};
{% endhighlight %}

{:.center}
src/core/lib/channel/channel_stack.h

Channel Stack 关联的还有 Channel Element，在此之前先看 Channel Args 定义。

{% highlight c %}
typedef struct {
  grpc_channel_stack *channel_stack;
  const grpc_channel_args *channel_args;
  int is_first;
  int is_last;
} grpc_channel_element_args;
{% endhighlight %}

{:.center}
src/core/lib/channel/channel_stack.h

Channel Element Args 定义。

{% highlight c %}
struct grpc_channel_element {
  const grpc_channel_filter *filter;
  void *channel_data;
};
{% endhighlight %}

{:.center}
src/core/lib/channel/channel_stack.h

可见，Channel Element 用来追踪其中的 filter。Channel Element Args 则保存了 Element 的一些参数。Channel Stack 和 Channel Element 的数据结构相对简单。

### Call Stack

Call Stack 和 Channel Stack 很类似，那么就无须废话，直接看代码。

{% highlight c %}
struct grpc_call_stack {
  grpc_stream_refcount refcount;
  size_t count;
};
{% endhighlight %}

{:.center}
src/core/lib/channel/channel_stack.h

继续看 Call Element。

{% highlight c %}
struct grpc_call_element {
  const grpc_channel_filter *filter;
  void *channel_data;
  void *call_data;
};
{% endhighlight %}

{:.center}
src/core/lib/channel/channel_stack.h

Call Element Args 和 Channel 类似。

{% highlight c %}
typedef struct {
  grpc_call_stack *call_stack;
  const void *server_transport_data;
  grpc_call_context_element *context;
} grpc_call_element_args;
{% endhighlight %}

{:.center}
src/core/lib/channel/channel_stack.h

上面就了解了两个非常重要的数据结构。

### Channel Filter

除了上面的基本数据结构，每个 Channel Element 和 Call Element 都包含，Channel Filter 结构。代码如下，具体的作用也写在了注释中。

{% highlight c %}
/* Channel filters specify:
   1. the amount of memory needed in the channel & call (via the sizeof_XXX
      members) channel & call 的内存使用量
   2. functions to initialize and destroy channel & call data
      (init_XXX, destroy_XXX) 定义接口比如创建和销毁 channel & call data
   3. functions to implement call operations and channel operations (call_op,
      channel_op) 定义 channel 和 call 操作的接口
   4. a name, which is useful when debugging

   Members are laid out in approximate frequency of use order. */
typedef struct {
  /* 很熟悉，就是要看的 start_transport_stream_op */
  void (*start_transport_stream_op)(grpc_exec_ctx *exec_ctx,
                                    grpc_call_element *elem,
                                    grpc_transport_stream_op *op);
  /* Channel 级别的操作，比如 new calls, transport 和 closure */
  /* 可以看  grpc_channel_next_op */
  void (*start_transport_op)(grpc_exec_ctx *exec_ctx,
                             grpc_channel_element *elem, grpc_transport_op *op);

  size_t sizeof_call_data;
  /*
     初始化 call data
     elem 在 call 开始的时候被创建
     server_transport_data 是一个不透明的指针，如果是 NULL 则
     这个 call 来自客户端，否则来自服务端，大多数的 filter 不需要
     关心这个参数
  */
  void (*init_call_elem)(grpc_exec_ctx *exec_ctx, grpc_call_element *elem,
                         grpc_call_element_args *args);
  void (*set_pollset)(grpc_exec_ctx *exec_ctx, grpc_call_element *elem,
                      grpc_pollset *pollset);
  /* 销毁 call data */
  void (*destroy_call_elem)(grpc_exec_ctx *exec_ctx, grpc_call_element *elem);

  size_t sizeof_channel_data;
  /*
     初始化 channel elemment
     is_first, is_last 标志了该 element 在 stack 中的位置
  */
  void (*init_channel_elem)(grpc_exec_ctx *exec_ctx, grpc_channel_element *elem,
                            grpc_channel_element_args *args);
  /* 销毁 channel element */
  void (*destroy_channel_elem)(grpc_exec_ctx *exec_ctx,
                               grpc_channel_element *elem);

  /* 实现 grpc_call_get_peer() */
  char *(*get_peer)(grpc_exec_ctx *exec_ctx, grpc_call_element *elem);

  /* 该 filter 的名字，用于调试 */
  const char *name;
} grpc_channel_filter;
{% endhighlight %}

{:.center}
src/core/lib/channel/channel_stack.h

当创建一个 Channel 和 Call 的时候，会创建若干个 Element，每个 Element 都有一个 filter，每个 filter 做的事情不一样。一个 Channel 创建后有多个 filter。

下面就来看创建 Channel 和创建 Call。

### Channel Create

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
  return Channel(intermediary_low_channel._internal, intermediary_low_channel)
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
      with nogil:
          self.c_channel = grpc_insecure_channel_create(
              target, c_arguments, NULL)
    else:
      # 创建加密的 channel
      with nogil:
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
/* Create a client channel:
   Asynchronously: - resolve target
                   - connect to it (trying alternatives as presented)
                   - perform handshakes */
grpc_channel *grpc_insecure_channel_create(const char *target,
                                           const grpc_channel_args *args,
                                           void *reserved) {
  grpc_exec_ctx exec_ctx = GRPC_EXEC_CTX_INIT;
  GRPC_API_TRACE(
      "grpc_insecure_channel_create(target=%p, args=%p, reserved=%p)", 3,
      (target, args, reserved));
  GPR_ASSERT(!reserved);

  client_channel_factory *f = gpr_malloc(sizeof(*f));
  memset(f, 0, sizeof(*f));
  f->base.vtable = &client_channel_factory_vtable;
  gpr_ref_init(&f->refs, 1);
  f->merge_args = grpc_channel_args_copy(args);

  grpc_channel *channel = client_channel_factory_create_channel(
      &exec_ctx, &f->base, target, GRPC_CLIENT_CHANNEL_TYPE_REGULAR, NULL);
  if (channel != NULL) {
    f->master = channel;
    GRPC_CHANNEL_INTERNAL_REF(f->master, "grpc_insecure_channel_create");
  }
  grpc_client_channel_factory_unref(&exec_ctx, &f->base);

  grpc_exec_ctx_finish(&exec_ctx);

  return channel != NULL ? channel : grpc_lame_client_channel_create(
                                         target, GRPC_STATUS_INTERNAL,
                                         "Failed to create client channel");
}
{% endhighlight %}

{:.center}
src/core/ext/transport/chttp2/client/insecure/channel_create.c

继续往下创建。

{% highlight c %}
static grpc_channel *client_channel_factory_create_channel(
    grpc_exec_ctx *exec_ctx, grpc_client_channel_factory *cc_factory,
    const char *target, grpc_client_channel_type type,
    grpc_channel_args *args) {
  client_channel_factory *f = (client_channel_factory *)cc_factory;
  grpc_channel_args *final_args = grpc_channel_args_merge(args, f->merge_args);
  grpc_channel *channel = grpc_channel_create(exec_ctx, target, final_args,
                                              GRPC_CLIENT_CHANNEL, NULL);
  grpc_channel_args_destroy(final_args);
  grpc_resolver *resolver = grpc_resolver_create(target, &f->base);
  if (!resolver) {
    GRPC_CHANNEL_INTERNAL_UNREF(exec_ctx, channel,
                                "client_channel_factory_create_channel");
    return NULL;
  }

  grpc_client_channel_set_resolver(
      exec_ctx, grpc_channel_get_channel_stack(channel), resolver);
  GRPC_RESOLVER_UNREF(exec_ctx, resolver, "create_channel");

  return channel;
}
{% endhighlight %}

{:.center}
src/core/ext/transport/chttp2/client/insecure/channel_create.c

下面看看 *grpc_channel_create* 的使用。

{% highlight c %}
grpc_channel *grpc_channel_create(grpc_exec_ctx *exec_ctx, const char *target,
                                  const grpc_channel_args *input_args,
                                  grpc_channel_stack_type channel_stack_type,
                                  grpc_transport *optional_transport) {
  bool is_client = grpc_channel_stack_type_is_client(channel_stack_type);

  grpc_channel_stack_builder *builder = grpc_channel_stack_builder_create();
  grpc_channel_stack_builder_set_channel_arguments(builder, input_args);
  grpc_channel_stack_builder_set_target(builder, target);
  grpc_channel_stack_builder_set_transport(builder, optional_transport);
  grpc_channel *channel;
  grpc_channel_args *args;
  if (!grpc_channel_init_create_stack(exec_ctx, builder, channel_stack_type)) {
    grpc_channel_stack_builder_destroy(builder);
    return NULL;
  } else {
    args = grpc_channel_args_copy(
        grpc_channel_stack_builder_get_channel_arguments(builder));
    channel = grpc_channel_stack_builder_finish(
        exec_ctx, builder, sizeof(grpc_channel), 1, destroy_channel, NULL);
  }

  memset(channel, 0, sizeof(*channel));
  channel->target = gpr_strdup(target);
  channel->is_client = is_client;
  gpr_mu_init(&channel->registered_call_mu);
  channel->registered_calls = NULL;

  channel->max_message_length = DEFAULT_MAX_MESSAGE_LENGTH;
  grpc_compression_options_init(&channel->compression_options);
  if (args) {
    for (size_t i = 0; i < args->num_args; i++) {
      if (0 == strcmp(args->args[i].key, GRPC_ARG_MAX_MESSAGE_LENGTH)) {
        if (args->args[i].type != GRPC_ARG_INTEGER) {
          gpr_log(GPR_ERROR, "%s ignored: it must be an integer",
                  GRPC_ARG_MAX_MESSAGE_LENGTH);
        } else if (args->args[i].value.integer < 0) {
          gpr_log(GPR_ERROR, "%s ignored: it must be >= 0",
                  GRPC_ARG_MAX_MESSAGE_LENGTH);
        } else {
          channel->max_message_length = (uint32_t)args->args[i].value.integer;
        }
      } else if (0 == strcmp(args->args[i].key, GRPC_ARG_DEFAULT_AUTHORITY)) {
        if (args->args[i].type != GRPC_ARG_STRING) {
          gpr_log(GPR_ERROR, "%s ignored: it must be a string",
                  GRPC_ARG_DEFAULT_AUTHORITY);
        } else {
          if (channel->default_authority) {
            /* setting this takes precedence over anything else */
            GRPC_MDELEM_UNREF(channel->default_authority);
          }
          channel->default_authority = grpc_mdelem_from_strings(
              ":authority", args->args[i].value.string);
        }
      } else if (0 ==
                 strcmp(args->args[i].key, GRPC_SSL_TARGET_NAME_OVERRIDE_ARG)) {
        if (args->args[i].type != GRPC_ARG_STRING) {
          gpr_log(GPR_ERROR, "%s ignored: it must be a string",
                  GRPC_SSL_TARGET_NAME_OVERRIDE_ARG);
        } else {
          if (channel->default_authority) {
            /* other ways of setting this (notably ssl) take precedence */
            gpr_log(GPR_ERROR,
                    "%s ignored: default host already set some other way",
                    GRPC_SSL_TARGET_NAME_OVERRIDE_ARG);
          } else {
            channel->default_authority = grpc_mdelem_from_strings(
                ":authority", args->args[i].value.string);
          }
        }
      } else if (0 == strcmp(args->args[i].key,
                             GRPC_COMPRESSION_CHANNEL_DEFAULT_LEVEL)) {
        channel->compression_options.default_level.is_set = true;
        GPR_ASSERT(args->args[i].value.integer >= 0 &&
                   args->args[i].value.integer < GRPC_COMPRESS_LEVEL_COUNT);
        channel->compression_options.default_level.level =
            (grpc_compression_level)args->args[i].value.integer;
      } else if (0 == strcmp(args->args[i].key,
                             GRPC_COMPRESSION_CHANNEL_DEFAULT_ALGORITHM)) {
        channel->compression_options.default_algorithm.is_set = true;
        GPR_ASSERT(args->args[i].value.integer >= 0 &&
                   args->args[i].value.integer <
                       GRPC_COMPRESS_ALGORITHMS_COUNT);
        channel->compression_options.default_algorithm.algorithm =
            (grpc_compression_algorithm)args->args[i].value.integer;
      } else if (0 ==
                 strcmp(args->args[i].key,
                        GRPC_COMPRESSION_CHANNEL_ENABLED_ALGORITHMS_BITSET)) {
        channel->compression_options.enabled_algorithms_bitset =
            (uint32_t)args->args[i].value.integer |
            0x1; /* always support no compression */
      }
    }
    grpc_channel_args_destroy(args);
  }
  return channel;
}
{% endhighlight %}

{:.center}
src/core/lib/surface/channel.c

这样就创建了一个 Channel。

### 相关文章

1. [Basic](/posts/grpc-python-bind-source-code-1/)
2. [Server](/posts/grpc-python-bind-source-code-2/)
3. [CompletionQueue](/posts/grpc-python-bind-source-code-3/)
4. [Stub](/posts/grpc-python-bind-source-code-4/)
5. [Channel](/posts/grpc-python-bind-source-code-5/)
6. [TCP Server](/posts/grpc-c-core-source-code-1/)

### 有关 C Core 的笔记

1. [Notes of gRPC](https://github.com/GuoJing/book-notes/tree/master/grpc)

