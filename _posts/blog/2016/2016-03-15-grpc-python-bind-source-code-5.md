---
layout:    post
title:     gRPC Python 源码浅析 - Channel and Call
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

继续往下创建。

{% highlight c %}
grpc_channel *grpc_channel_create_from_filters(
    grpc_exec_ctx *exec_ctx, const char *target,
    const grpc_channel_filter **filters, size_t num_filters,
    const grpc_channel_args *args, int is_client) {
  size_t i;
  size_t size =
      sizeof(grpc_channel) + grpc_channel_stack_size(filters, num_filters);
  grpc_channel *channel = gpr_malloc(size);
  memset(channel, 0, sizeof(*channel));
  channel->target = gpr_strdup(target);
  GPR_ASSERT(grpc_is_initialized() && "call grpc_init()");
  channel->is_client = is_client;
  gpr_mu_init(&channel->registered_call_mu);
  channel->registered_calls = NULL;

  channel->max_message_length = DEFAULT_MAX_MESSAGE_LENGTH;
  if (args) {
    for (i = 0; i < args->num_args; i++) {
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
      }
    }
  }

  if (channel->is_client && channel->default_authority == NULL &&
      target != NULL) {
    char *default_authority = grpc_get_default_authority(target);
    if (default_authority) {
      channel->default_authority =
          grpc_mdelem_from_strings(":authority", default_authority);
    }
    gpr_free(default_authority);
  }

  // 初始化 channel statck
  grpc_channel_stack_init(exec_ctx, 1, destroy_channel, channel, filters,
                          num_filters, args,
                          is_client ? "CLIENT_CHANNEL" : "SERVER_CHANNEL",
                          CHANNEL_STACK_FROM_CHANNEL(channel));

  return channel;
}
{% endhighlight %}

{:.center}
src/core/surface/channel.c

从上面我们可以创建一个 Channel。但是 Channel 的数据结构还比较复杂，隐约我们发现 Channel 和 Call 之间有千丝万缕的联系。其中 *grpc_call_stack_init* 和 *grpc_channel_stack_init* 都很重要。所以我们需要画图来详细了解 Channel 和 Call 之间的关系。如果不清楚。还需要回头结合 [Stub](/posts/grpc-python-bind-source-code-4/) 和 C Core 一齐来看。

### Channel and Call

Channel 和 Call 在 gRPC C Core 中是非常底层的一个数据结构，整体来看如下图所示。

{:.center}
![Channel Stack and Call Stack](/images/2016/grpc-channel-stack-overview.png){:style="max-width: 800px"}

{:.center}
Channel Stack and Call Stack

上图是一个 Channel Stack 和 Call Stack 的大概的一个结构图，了解了这个图之后我们就可以更加深入的了解每一个对象的意义。

### Channel Stack

{% highlight c %}
struct grpc_channel_stack {
  grpc_stream_refcount refcount;
  size_t count;
  size_t call_stack_size;
};
{% endhighlight %}

{:.center}
src/core/channel/channel_stack.h

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
src/core/channel/channel_stack.h

Channel Element Args 定义。

{% highlight c %}
struct grpc_channel_element {
  const grpc_channel_filter *filter;
  void *channel_data;
};
{% endhighlight %}

{:.center}
src/core/channel/channel_stack.h

可见，Channel Element 用来追踪其中的 filter。Channel Element Args 则保存了 Element 的一些参数。Channel Stack 和 Channel Element 的数据结构相对简单，看看是如何初始化这个 Channel Stack 的。

{% highlight c %}
void grpc_channel_stack_init(grpc_exec_ctx *exec_ctx, int initial_refs,
                             grpc_iomgr_cb_func destroy, void *destroy_arg,
                             const grpc_channel_filter **filters,
                             size_t filter_count,
                             const grpc_channel_args *channel_args,
                             const char *name, grpc_channel_stack *stack) {
  size_t call_size =
      ROUND_UP_TO_ALIGNMENT_SIZE(sizeof(grpc_call_stack)) +
      ROUND_UP_TO_ALIGNMENT_SIZE(filter_count * sizeof(grpc_call_element));
  grpc_channel_element *elems;
  grpc_channel_element_args args;
  char *user_data;
  size_t i;

  stack->count = filter_count;
  GRPC_STREAM_REF_INIT(&stack->refcount, initial_refs, destroy, destroy_arg,
                       name);
  elems = CHANNEL_ELEMS_FROM_STACK(stack);
  user_data =
      ((char *)elems) +
      ROUND_UP_TO_ALIGNMENT_SIZE(filter_count * sizeof(grpc_channel_element));

  /*
    初始化每个 channel element
    从 grpc_insecure_channel_create 代码可知
    创建一个 channel 的时候 filters 最大不超过
    MAX_FILTERS = 3 个
    则 filter_count <= 3
  */
  for (i = 0; i < filter_count; i++) {
    // channel element args 初始化
    args.channel_stack = stack;
    args.channel_args = channel_args;
    args.is_first = i == 0;
    args.is_last = i == (filter_count - 1);
    // channel element 初始化
    // grpc_channel_element 类型
    elems[i].filter = filters[i];
    elems[i].channel_data = user_data;
    elems[i].filter->init_channel_elem(exec_ctx, &elems[i], &args);
    user_data += ROUND_UP_TO_ALIGNMENT_SIZE(filters[i]->sizeof_channel_data);
    call_size += ROUND_UP_TO_ALIGNMENT_SIZE(filters[i]->sizeof_call_data);
  }

  GPR_ASSERT(user_data > (char *)stack);
  GPR_ASSERT((uintptr_t)(user_data - (char *)stack) ==
             grpc_channel_stack_size(filters, filter_count));

  stack->call_stack_size = call_size;
}
{% endhighlight %}

{:.center}
src/core/channel/channel_stack.c

上面的代码初始化了一个 Channel Stack，同时也初始化了每个 Channel Element。其中使用了 *init_channel_elem* 函数。这个函数根据 filter 的类型不同，调用的方法也不同。从之前创建 Channel 的代码来看有 *grpc_compress_filter* 和 *grpc_client_channel_filter*。

### Channel Filter

Channel Filter 代码如下，具体的作用也写在了注释中。

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
src/core/channel/channel_stack.h

所以，由此可见，一个 Channel 创建后有多个 filter，每个 filter 做的事情也不一样，如果要看 *start_transport_stream_op*[^1]，我们需要到特定的 filter 里去看如何实现，例如。

[^1]: 创建 Sever 的时候的第一个 Filter。

{% highlight c %}
// 定义了一个 filter
// filter 的 start_transport_stream_op = server_start_transport_stream_op
// filter 的 start_transport_op = grpc_channel_next_op
static const grpc_channel_filter server_surface_filter = {
    server_start_transport_stream_op, grpc_channel_next_op, sizeof(call_data),
    init_call_elem, grpc_call_stack_ignore_set_pollset, destroy_call_elem,
    sizeof(channel_data), init_channel_elem, destroy_channel_elem,
    grpc_call_next_get_peer, "server",
};
{% endhighlight %}

{:.center}
core/surface/server.c

所以 *grpc_client_channel_filter* 就要到 *grpc_client_channel_filter* 相关的代码中查看。

{% highlight c %}
static void init_channel_elem(grpc_exec_ctx *exec_ctx,
                              grpc_channel_element *elem,
                              grpc_channel_element_args *args) {
  // channel data 拷贝
  channel_data *chand = elem->channel_data;

  // 分配内存
  memset(chand, 0, sizeof(*chand));

  // 检查 args->is_last
  // 可见 client channel 顺序上是 channel 的最后一个
  GPR_ASSERT(args->is_last);
  // 检查 filter 类型
  GPR_ASSERT(elem->filter == &grpc_client_channel_filter);

  gpr_mu_init(&chand->mu_config);
  
  grpc_closure_init(&chand->on_config_changed, cc_on_config_changed, chand);
  chand->owning_stack = args->channel_stack;
  // 初始化 channel 连接状态为 GRPC_CHANNEL_IDLE
  grpc_connectivity_state_init(&chand->state_tracker, GRPC_CHANNEL_IDLE,
                               "client_channel");
  chand->interested_parties = grpc_pollset_set_create();
}
{% endhighlight %}

{:.center}
src/core/channel/client_channel.c

这样，每一个 Channel Element 都被初始化了，下面看看这个关系图。

![Channel Create](/images/2016/grpc-create-channel.png)

{:.center}
Channel Create 各元素之间的关系

### Call Stack

Call Stack 和 Channel Stack 很类似，那么就无须废话，直接看代码。

{% highlight c %}
struct grpc_call_stack {
  grpc_stream_refcount refcount;
  size_t count;
};
{% endhighlight %}

{:.center}
src/core/channel/channel_stack.h

继续看 Call Element。

{% highlight c %}
struct grpc_call_element {
  const grpc_channel_filter *filter;
  void *channel_data;
  void *call_data;
};
{% endhighlight %}

{:.center}
src/core/channel/channel_stack.h

Call Element Args 和 Channel 类似。

{% highlight c %}
typedef struct {
  grpc_call_stack *call_stack;
  const void *server_transport_data;
  grpc_call_context_element *context;
} grpc_call_element_args;
{% endhighlight %}

{:.center}
src/core/channel/channel_stack.h

在上一篇关于 [Stub](/posts/grpc-python-bind-source-code-4/) 中详细讲解了创建一个 Call，现在再回来看创建 Call 的代码。

{% highlight c %}
grpc_call *grpc_call_create(grpc_channel *channel, grpc_call *parent_call,
                            uint32_t propagation_mask,
                            grpc_completion_queue *cq,
                            const void *server_transport_data,
                            grpc_mdelem **add_initial_metadata,
                            size_t add_initial_metadata_count,
                            gpr_timespec send_deadline) {
  size_t i, j;
  grpc_channel_stack *channel_stack = grpc_channel_get_channel_stack(channel);
  grpc_exec_ctx exec_ctx = GRPC_EXEC_CTX_INIT;
  grpc_call *call;
  GPR_TIMER_BEGIN("grpc_call_create", 0);
  call = gpr_malloc(sizeof(grpc_call) + channel_stack->call_stack_size);
  memset(call, 0, sizeof(grpc_call));
  gpr_mu_init(&call->mu);
  call->channel = channel;
  // completion queue 队列也在这里使用
  call->cq = cq;
  call->parent = parent_call;
  call->is_client = server_transport_data == NULL;
  if (call->is_client) {
    // do something
  }
  call->send_deadline = send_deadline;
  // 初始化 call stack 很有意义
  grpc_call_stack_init(&exec_ctx, channel_stack, 1, destroy_call, call,
                       call->context, server_transport_data,
                       CALL_STACK_FROM_CALL(call));
  return call;
}
{% endhighlight %}

{:.center}
src/core/surface/call.c

现在把一些没有用的代码删掉，看到创建一个 Call 的时候，调用了 *grpc_call_stack_init* 方法。

{% highlight c %}
void grpc_call_stack_init(grpc_exec_ctx *exec_ctx,
                          grpc_channel_stack *channel_stack, int initial_refs,
                          grpc_iomgr_cb_func destroy, void *destroy_arg,
                          grpc_call_context_element *context,
                          const void *transport_server_data,
                          grpc_call_stack *call_stack) {
  grpc_channel_element *channel_elems = CHANNEL_ELEMS_FROM_STACK(channel_stack);
  grpc_call_element_args args;
  size_t count = channel_stack->count;
  grpc_call_element *call_elems;
  char *user_data;
  size_t i;

  call_stack->count = count;
  GRPC_STREAM_REF_INIT(&call_stack->refcount, initial_refs, destroy,
                       destroy_arg, "CALL_STACK");
  call_elems = CALL_ELEMS_FROM_STACK(call_stack);
  user_data = ((char *)call_elems) +
              ROUND_UP_TO_ALIGNMENT_SIZE(count * sizeof(grpc_call_element));

  /*
     代码意义同 Channel
  */
  for (i = 0; i < count; i++) {
    // 分别给每一个 element 初始化
    args.call_stack = call_stack;
    args.server_transport_data = transport_server_data;
    args.context = context;
    // 每个 call 注册 filter
    call_elems[i].filter = channel_elems[i].filter;
    // call_elems == channel_elems
    // 从 channel 拷贝data 到 call->channel_data
    call_elems[i].channel_data = channel_elems[i].channel_data;
    // call->data 就是 user_data
    call_elems[i].call_data = user_data;
    call_elems[i].filter->init_call_elem(exec_ctx, &call_elems[i], &args);
    user_data +=
        ROUND_UP_TO_ALIGNMENT_SIZE(call_elems[i].filter->sizeof_call_data);
  }
}
{% endhighlight %}

{:.center}
src/core/channel/channel_stack.c

再进去看 *init_call_elem* 函数。同样，这个函数每个 filter 不一样，调用的函数不一样。根据上面的代码，我们看的是 *client_channel.c*，那么也继续看这个 filter。

{% highlight python %}
static void init_call_elem(grpc_exec_ctx *exec_ctx, grpc_call_element *elem,
                           grpc_call_element_args *args) {
  grpc_subchannel_call_holder_init(elem->call_data, cc_pick_subchannel, elem,
                                   args->call_stack);
}
{% endhighlight %}

{:.center}
src/core/channel/client_channel.c

进去看 *grpc_subchannel_call_holder_init*。

{% highlight c %}
void grpc_subchannel_call_holder_init(
    grpc_subchannel_call_holder *holder,
    grpc_subchannel_call_holder_pick_subchannel pick_subchannel,
    void *pick_subchannel_arg, grpc_call_stack *owning_call) {
  // holder 是 elem->call_data
  // pick_subchannel 是 cc_pick_subchannel
  // pick_subchannel_arg 是 elem
  // owning_call 是 args->call_stack
  gpr_atm_rel_store(&holder->subchannel_call, 0);
  holder->pick_subchannel = pick_subchannel;
  holder->pick_subchannel_arg = pick_subchannel_arg;
  gpr_mu_init(&holder->mu);
  holder->connected_subchannel = NULL;
  holder->waiting_ops = NULL;
  holder->waiting_ops_count = 0;
  holder->waiting_ops_capacity = 0;
  holder->creation_phase = GRPC_SUBCHANNEL_CALL_HOLDER_NOT_CREATING;
  holder->owning_call = owning_call;
}
{% endhighlight %}

{:.center}
src/core/channel/subchannel_call_holder.c

这样每个 Call Element 也被初始化了，大致的概念如下。

![Create Call](/images/2016/grpc-create-call.png)

{:.center}

Call Create 各元素之间的关系

其中 cc_pick_subchannel 是 代码在 *subchannel_call_holder.c* 中。

{% highlight c %}
static int cc_pick_subchannel(grpc_exec_ctx *exec_ctx, void *elemp,
                              grpc_metadata_batch *initial_metadata,
                              grpc_connected_subchannel **connected_subchannel,
                              grpc_closure *on_ready) {
  grpc_call_element *elem = elemp;
  channel_data *chand = elem->channel_data;
  call_data *calld = elem->call_data;
  continue_picking_args *cpa;
  grpc_closure *closure;

  GPR_ASSERT(connected_subchannel);

  gpr_mu_lock(&chand->mu_config);
  if (initial_metadata == NULL) {
    if (chand->lb_policy != NULL) {
      grpc_lb_policy_cancel_pick(exec_ctx, chand->lb_policy,
                                 connected_subchannel);
    }
    for (closure = chand->waiting_for_config_closures.head; closure != NULL;
         closure = grpc_closure_next(closure)) {
      cpa = closure->cb_arg;
      if (cpa->connected_subchannel == connected_subchannel) {
        cpa->connected_subchannel = NULL;
        grpc_exec_ctx_enqueue(exec_ctx, cpa->on_ready, false, NULL);
      }
    }
    gpr_mu_unlock(&chand->mu_config);
    return 1;
  }
  if (chand->lb_policy != NULL) {
    grpc_lb_policy *lb_policy = chand->lb_policy;
    int r;
    GRPC_LB_POLICY_REF(lb_policy, "cc_pick_subchannel");
    gpr_mu_unlock(&chand->mu_config);
    r = grpc_lb_policy_pick(exec_ctx, lb_policy, calld->pollset,
                            initial_metadata, connected_subchannel, on_ready);
    GRPC_LB_POLICY_UNREF(exec_ctx, lb_policy, "cc_pick_subchannel");
    return r;
  }
  if (chand->resolver != NULL && !chand->started_resolving) {
    chand->started_resolving = 1;
    GRPC_CHANNEL_STACK_REF(chand->owning_stack, "resolver");
    grpc_resolver_next(exec_ctx, chand->resolver,
                       &chand->incoming_configuration,
                       &chand->on_config_changed);
  }
  cpa = gpr_malloc(sizeof(*cpa));
  cpa->initial_metadata = initial_metadata;
  cpa->connected_subchannel = connected_subchannel;
  cpa->on_ready = on_ready;
  cpa->elem = elem;
  grpc_closure_init(&cpa->closure, continue_picking, cpa);
  grpc_closure_list_add(&chand->waiting_for_config_closures, &cpa->closure, 1);
  gpr_mu_unlock(&chand->mu_config);
  return 0;
}
{% endhighlight %}

{:.center}
src/core/channel/client_channel.c

### Filter?

现在看了大多数的概念之后，我们还是主要来关注 *client_channel.c*。之前调用的是。

    elem->filter->start_transport_stream_op
    
在 *client_channel.c* 这里，代码如下。

{% highlight c %}
static void cc_start_transport_stream_op(grpc_exec_ctx *exec_ctx,
                                         grpc_call_element *elem,
                                         grpc_transport_stream_op *op) {
  GRPC_CALL_LOG_OP(GPR_INFO, elem, op);
  grpc_subchannel_call_holder_perform_op(exec_ctx, elem->call_data, op);
}
{% endhighlight %}

{:.center}
src/core/channel/client_channel.c

到了关键的 *grpc_subchannel_call_holder_perform_op* 函数。

{% highlight c %}
void grpc_subchannel_call_holder_perform_op(grpc_exec_ctx *exec_ctx,
                                            grpc_subchannel_call_holder *holder,
                                            grpc_transport_stream_op *op) {
  /* try to (atomically) get the call */
  grpc_subchannel_call *call = GET_CALL(holder);
  GPR_TIMER_BEGIN("grpc_subchannel_call_holder_perform_op", 0);
  if (call == CANCELLED_CALL) {
    grpc_transport_stream_op_finish_with_failure(exec_ctx, op);
    GPR_TIMER_END("grpc_subchannel_call_holder_perform_op", 0);
    return;
  }
  if (call != NULL) {
    grpc_subchannel_call_process_op(exec_ctx, call, op);
    GPR_TIMER_END("grpc_subchannel_call_holder_perform_op", 0);
    return;
  }
  /* we failed; lock and figure out what to do */
  gpr_mu_lock(&holder->mu);
retry:
  /* need to recheck that another thread hasn't set the call */
  call = GET_CALL(holder);
  if (call == CANCELLED_CALL) {
    gpr_mu_unlock(&holder->mu);
    grpc_transport_stream_op_finish_with_failure(exec_ctx, op);
    GPR_TIMER_END("grpc_subchannel_call_holder_perform_op", 0);
    return;
  }
  if (call != NULL) {
    gpr_mu_unlock(&holder->mu);
    grpc_subchannel_call_process_op(exec_ctx, call, op);
    GPR_TIMER_END("grpc_subchannel_call_holder_perform_op", 0);
    return;
  }
  /* if this is a cancellation, then we can raise our cancelled flag */
  if (op->cancel_with_status != GRPC_STATUS_OK) {
    if (!gpr_atm_rel_cas(&holder->subchannel_call, 0, 1)) {
      goto retry;
    } else {
      switch (holder->creation_phase) {
        case GRPC_SUBCHANNEL_CALL_HOLDER_NOT_CREATING:
          fail_locked(exec_ctx, holder);
          break;
        case GRPC_SUBCHANNEL_CALL_HOLDER_PICKING_SUBCHANNEL:
          holder->pick_subchannel(exec_ctx, holder->pick_subchannel_arg, NULL,
                                  &holder->connected_subchannel, NULL);
          break;
      }
      gpr_mu_unlock(&holder->mu);
      grpc_transport_stream_op_finish_with_failure(exec_ctx, op);
      GPR_TIMER_END("grpc_subchannel_call_holder_perform_op", 0);
      return;
    }
  }
  /* if we don't have a subchannel, try to get one */
  if (holder->creation_phase == GRPC_SUBCHANNEL_CALL_HOLDER_NOT_CREATING &&
      holder->connected_subchannel == NULL &&
      op->send_initial_metadata != NULL) {
    holder->creation_phase = GRPC_SUBCHANNEL_CALL_HOLDER_PICKING_SUBCHANNEL;
    grpc_closure_init(&holder->next_step, subchannel_ready, holder);
    GRPC_CALL_STACK_REF(holder->owning_call, "pick_subchannel");
    if (holder->pick_subchannel(
            exec_ctx, holder->pick_subchannel_arg, op->send_initial_metadata,
            &holder->connected_subchannel, &holder->next_step)) {
      holder->creation_phase = GRPC_SUBCHANNEL_CALL_HOLDER_NOT_CREATING;
      GRPC_CALL_STACK_UNREF(exec_ctx, holder->owning_call, "pick_subchannel");
    }
  }
  /* if we've got a subchannel, then let's ask it to create a call */
  if (holder->creation_phase == GRPC_SUBCHANNEL_CALL_HOLDER_NOT_CREATING &&
      holder->connected_subchannel != NULL) {
    gpr_atm_rel_store(
        &holder->subchannel_call,
        (gpr_atm)(uintptr_t)grpc_connected_subchannel_create_call(
            exec_ctx, holder->connected_subchannel, holder->pollset));
    retry_waiting_locked(exec_ctx, holder);
    goto retry;
  }
  /* nothing to be done but wait */
  add_waiting_locked(holder, op);
  gpr_mu_unlock(&holder->mu);
  GPR_TIMER_END("grpc_subchannel_call_holder_perform_op", 0);
}
{% endhighlight %}

{:.center}
core/src/channel/subchannel_call_holder.c

其中执行的函数为 *grpc_subchannel_call_process_op*，可以再了解这个函数。

{% highlight c %}
void grpc_subchannel_call_process_op(grpc_exec_ctx *exec_ctx,
                                     grpc_subchannel_call *call,
                                     grpc_transport_stream_op *op) {
  grpc_call_stack *call_stack = SUBCHANNEL_CALL_TO_CALL_STACK(call);
  grpc_call_element *top_elem = grpc_call_stack_element(call_stack, 0);
  // 可以看到还是从 call_element 的 filtre 调用 start_transport_stream_op
  // top_elem = first call stack element
  top_elem->filter->start_transport_stream_op(exec_ctx, top_elem, op);
}
{% endhighlight %}

{:.center}
src/core/client_config/subchannel.c

然后看 *grpc_connected_subchannel_create_call* 这个函数。

{% highlight c %}
grpc_subchannel_call *grpc_connected_subchannel_create_call(
    grpc_exec_ctx *exec_ctx, grpc_connected_subchannel *con,
    grpc_pollset *pollset) {
  grpc_channel_stack *chanstk = CHANNEL_STACK_FROM_CONNECTION(con);
  grpc_subchannel_call *call =
      gpr_malloc(sizeof(grpc_subchannel_call) + chanstk->call_stack_size);
  grpc_call_stack *callstk = SUBCHANNEL_CALL_TO_CALL_STACK(call);
  // call->connection !
  call->connection = con;
  GRPC_CONNECTED_SUBCHANNEL_REF(con, "subchannel_call");
  grpc_call_stack_init(exec_ctx, chanstk, 1, subchannel_call_destroy, call,
                       NULL, NULL, callstk);
  grpc_call_stack_set_pollset(exec_ctx, callstk, pollset);
  return call;
}
{% endhighlight %}

{:.center}
src/core/client_config/subchannel.c

上面的代码逻辑是，先从 holder 获得一个 call，如果没有 subchannel，尝试获得一个，如果有了，则创建一个 call，然后 goto retry。

Retry 的逻辑是，获得一个 call 对象，调用 *grpc_subchannel_call_process_op* 方法处理。在函数中拿到一个 call element，调用 call element 的 filter 的 *start_transport_stream_op* 函数。

### Compress Filter

在创建 Channel 的时候创建了各种 Filter，在创建 Call 的时候也同时映射了 Channel 的 Filter，所以 Channel 有多少 Filter，我们可以看 Call 的每个 filter 是如何执行。当然，这里只是挑重点的 Filter。

{% highlight c %}
static void compress_start_transport_stream_op(grpc_exec_ctx *exec_ctx,
                                               grpc_call_element *elem,
                                               grpc_transport_stream_op *op) {
  call_data *calld = elem->call_data;

  GPR_TIMER_BEGIN("compress_start_transport_stream_op", 0);

  if (op->send_initial_metadata) {
    process_send_initial_metadata(elem, op->send_initial_metadata);
  }
  if (op->send_message != NULL && !skip_compression(elem) &&
      0 == (op->send_message->flags & GRPC_WRITE_NO_COMPRESS)) {
    calld->send_op = *op;
    calld->send_length = op->send_message->length;
    calld->send_flags = op->send_message->flags;
    // 继续发送 element and data
    continue_send_message(exec_ctx, elem);
  } else {
    // 调用到栈的下一个元素
    grpc_call_next_op(exec_ctx, elem, op);
  }

  GPR_TIMER_END("compress_start_transport_stream_op", 0);
}
{% endhighlight %}

{:.center}
src/core/channel/compress_filter.c

{% highlight c %}
static void continue_send_message(grpc_exec_ctx *exec_ctx,
                                  grpc_call_element *elem) {
  call_data *calld = elem->call_data;
  // sending data
  // slice 是用来分片的
  while (grpc_byte_stream_next(exec_ctx, calld->send_op.send_message,
                               &calld->incoming_slice, ~(size_t)0,
                               &calld->got_slice)) {
    gpr_slice_buffer_add(&calld->slices, calld->incoming_slice);
    if (calld->send_length == calld->slices.length) {
      // 数据发送完毕
      finish_send_message(exec_ctx, elem);
      break;
    }
  }
}
{% endhighlight %}

{:.center}
src/core/channel/compress_filter.c

发送数据完毕后会调用 *finish_send_message*。

{% highlight c %}
static void finish_send_message(grpc_exec_ctx *exec_ctx,
                                grpc_call_element *elem) {
  call_data *calld = elem->call_data;
  int did_compress;
  gpr_slice_buffer tmp;
  gpr_slice_buffer_init(&tmp);
  did_compress =
      grpc_msg_compress(calld->compression_algorithm, &calld->slices, &tmp);
  if (did_compress) {
    gpr_slice_buffer_swap(&calld->slices, &tmp);
    calld->send_flags |= GRPC_WRITE_INTERNAL_COMPRESS;
  }
  gpr_slice_buffer_destroy(&tmp);

  grpc_slice_buffer_stream_init(&calld->replacement_stream, &calld->slices,
                                calld->send_flags);
  calld->send_op.send_message = &calld->replacement_stream.base;
  calld->post_send = calld->send_op.on_complete;
  calld->send_op.on_complete = &calld->send_done;

  // 再从栈中获取并继续执行
  grpc_call_next_op(exec_ctx, elem, &calld->send_op);
}
{% endhighlight %}

{:.center}
src/core/channel/compress_filter.c

可见，每次执行 Call 调用的时候，都是遍历 Call Stack，调用 Call Element 执行 Calle Element 的 Filter 的 Start Transport Stream OP。

### HTTP Client Filter

在 gRPC 中还有一个 connector 在 channel 文件中，每个 subchannel 创建的时候会使用。在执行 subchannel 操作的时候会调用。具体可以看 *subchannel_factory_create_subchannel*。

这里的 connector 使用了 http_client_filter。可以看到这个 filter 是这样定义的。

{% highlight c %}
const grpc_channel_filter grpc_http_client_filter = {
    hc_start_transport_op, grpc_channel_next_op, sizeof(call_data),
    init_call_elem, grpc_call_stack_ignore_set_pollset, destroy_call_elem,
    sizeof(channel_data), init_channel_elem, destroy_channel_elem,
    grpc_call_next_get_peer, "http-client"};
{% endhighlight %}

{:.center}
src/core/channel/http_client_filter.c

所以 filter->start_transport_stream_op 则是。

{% highlight c %}
static void hc_start_transport_op(grpc_exec_ctx *exec_ctx,
                                  grpc_call_element *elem,
                                  grpc_transport_stream_op *op) {
  GPR_TIMER_BEGIN("hc_start_transport_op", 0);
  GRPC_CALL_LOG_OP(GPR_INFO, elem, op);
  hc_mutate_op(elem, op);
  GPR_TIMER_END("hc_start_transport_op", 0);
  grpc_call_next_op(exec_ctx, elem, op);
}
{% endhighlight %}

{:.center}
src/core/channel/http_client_filter.c

而 *grpc_call_next_op* 则是在 Call Stack 下找到下一个 element 并执行 element->filter 的 *start_transprot_stream_op*。相当于把 Call Stack 整个 Stack 的 element->filter 都调用了一次。

{% highlight c %}
void grpc_call_next_op(grpc_exec_ctx *exec_ctx, grpc_call_element *elem,
                       grpc_transport_stream_op *op) {
  grpc_call_element *next_elem = elem + 1;
  next_elem->filter->start_transport_stream_op(exec_ctx, next_elem, op);
}
{% endhighlight%}

{:.center}
src/core/channel/channel_stack.c

由此可见，每次创建 Call 都会和 Channel 相关，Call 的调用则调用 Call Stack 上 Element 的 Filter 函数。最后每个 filter 各司其职，进行各自的操作。

上面的代码中的 *grpc_client_channel_filter* 是在传输层做的事情，所以还需要深入了解 transport 的代码和 HTTP2，那么会在之后的文章记录。

### 相关文章

1. [Basic](/posts/grpc-python-bind-source-code-1/)
2. [Server](/posts/grpc-python-bind-source-code-2/)
3. [CompletionQueue](/posts/grpc-python-bind-source-code-3/)
4. [Stub](/posts/grpc-python-bind-source-code-4/)
5. [Channel and Call](/posts/grpc-python-bind-source-code-5/)

### 有关 C Core 的笔记

1. [Notes of gRPC](https://github.com/GuoJing/book-notes/tree/master/grpc)

