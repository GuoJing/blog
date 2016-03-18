---
layout:    post
title:     gRPC C Core 源码浅析 - TCP Server
category:  blog
description: gRPC Python 源码
tags: gRPC Python Google Source Coding HTTP2 C Core
---
### Overview

在 [gRPC Python 源码浅析 - Server](/posts/grpc-python-bind-source-code-2/) 中了解了 gRPC Python 绑定是如何调用 C Core 代码启动一个 server 的，现在深入的了解 C Core 是如何启动一个 Server 的。

在这之前，大概有一个图可以帮助我们了解。

{:.center}
![gRPC C Core Server](/images/2016/grpc-c-core-server.png){:style="max-width: 550px"}

{:.center}
Server 启动大概步骤

从之前知道 server.start 最终是调用了 server->listener->start() 方法。所以还是从这里开始挖。

{% highlight c %}
static void start(grpc_exec_ctx *exec_ctx, grpc_server *server, void *tcpp,
                  grpc_pollset **pollsets, size_t pollset_count) {
  grpc_tcp_server *tcp = tcpp;
  // 打开 tcp server
  // 这里的 new_transport 是 on_accept_cb 参数
  grpc_tcp_server_start(exec_ctx, tcp, pollsets, pollset_count, new_transport,
                        server);
}
{% endhighlight %}

{:.center}
src/core/surface/server_chttp2.c

所以知道 server start 方法，最终调用了 TCP Server 的 start 方法。而其中最重要的就是 *grpc_tcp_server_start*。

### TCP Server Start

这里就直接看 *grpc_tcp_server_start* 方法。

{% highlight c %}
void grpc_tcp_server_start(grpc_exec_ctx *exec_ctx, grpc_tcp_server *s,
                           grpc_pollset **pollsets, size_t pollset_count,
                           grpc_tcp_server_cb on_accept_cb,
                           void *on_accept_cb_arg) {
  size_t i;
  // s 是 tcp server
  grpc_tcp_listener *sp;
  GPR_ASSERT(on_accept_cb);
  gpr_mu_lock(&s->mu);
  GPR_ASSERT(!s->on_accept_cb);
  GPR_ASSERT(s->active_ports == 0);
  // 注册 tcp server on accept callback
  s->on_accept_cb = on_accept_cb;
  // 注册 tcp server on accept callback 参数
  s->on_accept_cb_arg = on_accept_cb_arg;
  s->pollsets = pollsets;
  s->pollset_count = pollset_count;
  // 循环 grpc tcp server 的 listener
  for (sp = s->head; sp; sp = sp->next) {
    for (i = 0; i < pollset_count; i++) {
      // 创建 pollset 的描述符
      // 这个 pollset 在 iomgr/pollset.c 中
      grpc_pollset_add_fd(exec_ctx, pollsets[i], sp->emfd);
    }
    // 注册每个 listener 的 read closure callback 和 参数
    // on_read 方法在当前代码下
    // sp 是当前的 tcp listener
    // 也就是说每次处理完就调用
    // on_read
    sp->read_closure.cb = on_read;
    sp->read_closure.cb_arg = sp;
    // 创建一个 on_read 之后和描述符之间的调用
    grpc_fd_notify_on_read(exec_ctx, sp->emfd, &sp->read_closure);
    s->active_ports++;
  }
  gpr_mu_unlock(&s->mu);
}
{% endhighlight %}

{:.center}
src/core/iomgr/tcp_server_posix.c

{% highlight c %}
void grpc_pollset_add_fd(grpc_exec_ctx *exec_ctx, grpc_pollset *pollset,
                         grpc_fd *fd) {
  gpr_mu_lock(&pollset->mu);
  // iomgr/pollset_posix.c grpc_pollset_vtable
  pollset->vtable->add_fd(exec_ctx, pollset, fd, 1);
#ifndef NDEBUG
  gpr_mu_lock(&pollset->mu);
  gpr_mu_unlock(&pollset->mu);
#endif
}
{% endhighlight %}

{:.center}
src/core/iomgr/pollset_posix.c

可以看看 *grpc_fd_notify_on_read* 方法。

{% highlight c %}
void grpc_fd_notify_on_read(grpc_exec_ctx *exec_ctx, grpc_fd *fd,
                            grpc_closure *closure) {
  gpr_mu_lock(&fd->mu);
  /*
     这里的 fd 是 sp->emfd
     也就是 grpc_tcp_listener->emfd
     closure 就是 grpc_tcp_listener->read_closure
     这个 read closure callback 就是 on_read 函数
  */
  notify_on_locked(exec_ctx, fd, &fd->read_closure, closure);
  gpr_mu_unlock(&fd->mu);
}
{% endhighlight %}

{:.center}
src/iomgr/fd_posfix.c

接下来调用了 *notify_on_locked*。

{% highlight c %}
static void notify_on_locked(grpc_exec_ctx *exec_ctx, grpc_fd *fd,
                             grpc_closure **st, grpc_closure *closure) {
  if (*st == CLOSURE_NOT_READY) {
    // fd 是 sp->emfd
    // 如果 not ready 状态
    // 切换 closure 到 waiting 状态
    *st = closure;
  } else if (*st == CLOSURE_READY) {
    // 如果状态是 ready 则执行 closure
    *st = CLOSURE_NOT_READY;
    grpc_exec_ctx_enqueue(exec_ctx, closure, !fd->shutdown, NULL);
    maybe_wake_one_watcher_locked(fd);
  } else {
    abort();
  }
}
{% endhighlight %}

{:.center}
src/iomgr/fd_posfix.c

可以大概理解为 TCP Server Start 之后，tcp server 注册了 *on_accept_cb* 方法，每个 TCP listener 注册了 *on_read* 方法。并且由底层 pollset 和 fd notify 来调度。而 *on_accept_cb* 是 *new_transport*。

### on_read

{% highlight c %}
static void on_read(grpc_exec_ctx *exec_ctx, void *arg, bool success) {
  grpc_tcp_listener *sp = arg;
  grpc_tcp_server_acceptor acceptor = {sp->server, sp->port_index,
                                       sp->fd_index};
  grpc_fd *fdobj;
  size_t i;

  if (!success) {
    goto error;
  }

  for (;;) {
    struct sockaddr_storage addr;
    socklen_t addrlen = sizeof(addr);
    char *addr_str;
    char *name;
    int fd = grpc_accept4(sp->fd, (struct sockaddr *)&addr, &addrlen, 1, 1);
    if (fd < 0) {
      switch (errno) {
        case EINTR:
          continue;
        case EAGAIN:
          grpc_fd_notify_on_read(exec_ctx, sp->emfd, &sp->read_closure);
          return;
        default:
          goto error;
      }
    }

    grpc_set_socket_no_sigpipe_if_possible(fd);

    addr_str = grpc_sockaddr_to_uri((struct sockaddr *)&addr);
    gpr_asprintf(&name, "tcp-server-connection:%s", addr_str);

    fdobj = grpc_fd_create(fd, name);

    for (i = 0; i < sp->server->pollset_count; i++) {
      grpc_pollset_add_fd(exec_ctx, sp->server->pollsets[i], fdobj);
    }

    // tcp listener 调用 server 的 on_accept_cb 方法
    // 这个方法可以看到在前面是 new transport
    sp->server->on_accept_cb(
        exec_ctx, sp->server->on_accept_cb_arg,
        grpc_tcp_create(fdobj, GRPC_TCP_DEFAULT_READ_SLICE_SIZE, addr_str),
        &acceptor);

    gpr_free(name);
    gpr_free(addr_str);
  }

error:
  gpr_mu_lock(&sp->server->mu);
  if (0 == --sp->server->active_ports) {
    gpr_mu_unlock(&sp->server->mu);
    deactivated_all_ports(exec_ctx, sp->server);
  } else {
    gpr_mu_unlock(&sp->server->mu);
  }
}
{% endhighlight %}

{:.center}
src/iomgr/tcp_server_posfix.c

可见 *on_read* 也是走到了 *server->on_accept_cb* 也就是说是 *new_transport* 方法。

### new_transport

当有数据传输，会调用 *on_read* 和 *new_transport* 方法，最后调用 *grpc_chttp2_transport_start_reading*。

{% highlight c %}
static void new_transport(grpc_exec_ctx *exec_ctx, void *server,
                          grpc_endpoint *tcp,
                          grpc_tcp_server_acceptor *acceptor) {
  // 创建 transport 对象
  grpc_transport *transport = grpc_create_chttp2_transport(
      exec_ctx, grpc_server_get_channel_args(server), tcp, 0);
  // 初始化一些参数
  setup_transport(exec_ctx, server, transport);
  // 开始读取
  grpc_chttp2_transport_start_reading(exec_ctx, transport, NULL, 0);
}
{% endhighlight %}

{:.center}
src/surface/server_chttp2.c

{% highlight c %}
void grpc_chttp2_transport_start_reading(grpc_exec_ctx *exec_ctx,
                                         grpc_transport *transport,
                                         gpr_slice *slices, size_t nslices) {
  grpc_chttp2_transport *t = (grpc_chttp2_transport *)transport;
  REF_TRANSPORT(t, "recv_data"); /* matches unref inside recv_data */
  gpr_slice_buffer_addn(&t->read_buffer, slices, nslices);
  // 接收数据
  // recv_data 函数接收了 frame 数据
  // 这个函数中最重要的是 grpc_chttp2_perform_read 这个函数
  // grpc_chttp2_perform_read 这个函数调用了 init_frame_parser
  // 然后调用了 init_header_frame_parser
  // 最后走到 grpc_chttp2_parsing_accept_stream
  // 就会调用到高级的 set_accept_stream_fn 这个函数
  // 最后就走到了 accept_stream
  recv_data(exec_ctx, t, 1);
}
{% endhighlight %}

{:.center}
src/transport/chttp2_transport.c

在调用 *grpc_create_chttp2_transport* 这个函数的时候，创建了一个 http2 transport 对象，并对这个对象进行了初始化。

{% highlight c %}
grpc_transport *grpc_create_chttp2_transport(
    grpc_exec_ctx *exec_ctx, const grpc_channel_args *channel_args,
    grpc_endpoint *ep, int is_client) {
  grpc_chttp2_transport *t = gpr_malloc(sizeof(grpc_chttp2_transport));
  init_transport(exec_ctx, t, channel_args, ep, is_client != 0);
  return &t->base;
}
{% endhighlight %}

{:.center}
src/transport/chttp2_transport.c

地方除了初始化内存分配以外，还调用了 *init_transport* 来初始化 transport，这一块的代码在后面传输层的地方再看。

初始化完成后，调用了 *setup_transport* 方法。

{% highlight c %}
static void setup_transport(grpc_exec_ctx *exec_ctx, void *server,
                            grpc_transport *transport) {
  static grpc_channel_filter const *extra_filters[] = {
      &grpc_http_server_filter};
  grpc_server_setup_transport(exec_ctx, server, transport, extra_filters,
                              GPR_ARRAY_SIZE(extra_filters),
                              grpc_server_get_channel_args(server));
}
{% endhighlight %}

{:.center}
src/core/surface/server_chttp2.c

其中增加了一个新的 Filter 为 *grpc_http_server_filter*，需要看一下 *grpc_server_setup_transport*。

{% highlight c %}
void grpc_server_setup_transport(grpc_exec_ctx *exec_ctx, grpc_server *s,
                                 grpc_transport *transport,
                                 grpc_channel_filter const **extra_filters,
                                 size_t num_extra_filters,
                                 const grpc_channel_args *args) {
  // 先计算 filters 的数量
  size_t num_filters = s->channel_filter_count + num_extra_filters + 1;
  grpc_channel_filter const **filters =
      gpr_malloc(sizeof(grpc_channel_filter *) * num_filters);
  size_t i;
  size_t num_registered_methods;
  size_t alloc;
  registered_method *rm;
  channel_registered_method *crm;
  grpc_channel *channel;
  channel_data *chand;
  grpc_mdstr *host;
  grpc_mdstr *method;
  uint32_t hash;
  size_t slots;
  uint32_t probes;
  uint32_t max_probes = 0;
  grpc_transport_op op;

  // filters 等于 server 的 channel_filters
  for (i = 0; i < s->channel_filter_count; i++) {
    filters[i] = s->channel_filters[i];
  }
  
  // 继续增加附加的 filter
  // 从之前的代码来看是
  // grpc_http_server_filter
  for (; i < s->channel_filter_count + num_extra_filters; i++) {
    filters[i] = extra_filters[i - s->channel_filter_count];
  }
  
  // 最后再增加一个 grpc_conncted_channel_filter
  filters[i] = &grpc_connected_channel_filter;

  // 循环遍历 server 的 completion queue
  for (i = 0; i < s->cq_count; i++) {
    memset(&op, 0, sizeof(op));
    // grpc_transport_op 绑定 server 端的每一个 completion
    op.bind_pollset = grpc_cq_pollset(s->cqs[i]);
    grpc_transport_perform_op(exec_ctx, transport, &op);
  }

  // 通过 filters 创建 channel 对象
  channel = grpc_channel_create_from_filters(exec_ctx, NULL, filters,
                                             num_filters, args, 0);
  // 从 channel stack 中拿到 channel element 的 channel data
  // channel data 是一个链表 维护 server 上所有 channels
  chand = (channel_data *)grpc_channel_stack_element(
              grpc_channel_get_channel_stack(channel), 0)->channel_data;
  // 初始化 channel data
  chand->server = s;
  server_ref(s);
  chand->channel = channel;

  num_registered_methods = 0;
  // 循环遍历在 server 上注册的方法
  // 初始化的时候是在 python binding 的 cython 中注册
  for (rm = s->registered_methods; rm; rm = rm->next) {
    num_registered_methods++;
  }
  // 初始化一个查找表 这样就能快速的找到注册的方法
  if (num_registered_methods > 0) {
    slots = 2 * num_registered_methods;
    alloc = sizeof(channel_registered_method) * slots;
    chand->registered_methods = gpr_malloc(alloc);
    memset(chand->registered_methods, 0, alloc);
    for (rm = s->registered_methods; rm; rm = rm->next) {
      host = rm->host ? grpc_mdstr_from_string(rm->host) : NULL;
      method = grpc_mdstr_from_string(rm->method);
      hash = GRPC_MDSTR_KV_HASH(host ? host->hash : 0, method->hash);
      for (probes = 0; chand->registered_methods[(hash + probes) % slots]
                               .server_registered_method != NULL;
           probes++)
        ;
      if (probes > max_probes) max_probes = probes;
      crm = &chand->registered_methods[(hash + probes) % slots];
      crm->server_registered_method = rm;
      crm->host = host;
      crm->method = method;
    }
    GPR_ASSERT(slots <= UINT32_MAX);
    chand->registered_method_slots = (uint32_t)slots;
    chand->registered_method_max_probes = max_probes;
  }

  // channel 绑定 transport
  grpc_connected_channel_bind_transport(grpc_channel_get_channel_stack(channel),
                                        transport);

  // 链表化
  gpr_mu_lock(&s->mu_global);
  chand->next = &s->root_channel_data;
  chand->prev = chand->next->prev;
  chand->next->prev = chand->prev->next = chand;
  gpr_mu_unlock(&s->mu_global);

  gpr_free((void *)filters);

  // 初始化 channel 的连接状态
  GRPC_CHANNEL_INTERNAL_REF(channel, "connectivity");
  memset(&op, 0, sizeof(op));
  // transport op 绑定方法
  op.set_accept_stream = true;
  // accept_stream 方法
  op.set_accept_stream_fn = accept_stream;
  // accept_stream 的 user_data
  op.set_accept_stream_user_data = chand;
  // 修改 op 的状态
  op.on_connectivity_state_change = &chand->channel_connectivity_changed;
  op.connectivity_state = &chand->connectivity_state;
  op.disconnect = gpr_atm_acq_load(&s->shutdown_flag) != 0;
  // 执行 grpc_transport_perform_op
  // transport->vtable->perform_op
  grpc_transport_perform_op(exec_ctx, transport, &op);
}
{% endhighlight %}

{:.center}
src/core/surface/server.c

从上可以知道，一个操作的 *accept_stream* 已经定义好。

{% highlight c %}
static void accept_stream(grpc_exec_ctx *exec_ctx, void *cd,
                          grpc_transport *transport,
                          const void *transport_server_data) {
  channel_data *chand = cd;
  // 服务端创建一个 call 对象
  // 如果有 transport_server_data 则说明是一个 server call
  grpc_call *call =
      grpc_call_create(chand->channel, NULL, 0, NULL, transport_server_data,
                       NULL, 0, gpr_inf_future(GPR_CLOCK_MONOTONIC));
  // 获取一个 call element
  grpc_call_element *elem =
      grpc_call_stack_element(grpc_call_get_call_stack(call), 0);
  // 初始化 call data
  call_data *calld = elem->call_data;
  grpc_op op;
  memset(&op, 0, sizeof(op));
  // 初始化一个 grpc op
  op.op = GRPC_OP_RECV_INITIAL_METADATA;
  op.data.recv_initial_metadata = &calld->initial_metadata;
  grpc_closure_init(&calld->got_initial_metadata, got_initial_metadata, elem);
  // 处理 call 调用
  grpc_call_start_batch_and_execute(exec_ctx, call, &op, 1,
                                    &calld->got_initial_metadata);
}
{% endhighlight %}

{:.center}
src/core/surface/server.c

上面代码在接收流的时候调用，其中 op 是一个 *grpc_op*，会走到 *grpc_call_start_batch_and_execute*。虽然之前在 [Channel and Call](/posts/grpc-python-bind-source-code-5/) 中看了这个代码，现在我们要更深入的了解这个代码。

{% highlight c %}
// grpc_call_start_batch_and_execute 实际上就是调用 call_start_batch
// 之前的 op.op 是 GRPC_OP_RECV_INITIAL_METADATA

static grpc_call_error call_start_batch(grpc_exec_ctx *exec_ctx,
                                        grpc_call *call, const grpc_op *ops,
                                        size_t nops, void *notify_tag,
                                        int is_notify_tag_closure) {
  grpc_transport_stream_op stream_op;
  size_t i;
  // do something ...
  // 开始操作
  for (i = 0; i < nops; i++) {
    op = &ops[i];
    if (op->reserved != NULL) {
      error = GRPC_CALL_ERROR;
      goto done_with_error;
    }
    switch (op->op) {
      case GRPC_OP_SEND_INITIAL_METADATA:
        // ..
      case GRPC_OP_RECV_INITIAL_METADATA:
        // 看这个 case
        // 错误

        if (op->flags != 0) {
          error = GRPC_CALL_ERROR_INVALID_FLAGS;
          goto done_with_error;
        }

        // 错误
        if (call->received_initial_metadata) {
          error = GRPC_CALL_ERROR_TOO_MANY_OPERATIONS;
          goto done_with_error;
        }

        // 初始化 stream op
        // op->data.recv_initial_metadata 为 got_initial_metadata
        call->received_initial_metadata = 1;
        call->buffered_metadata[0] = op->data.recv_initial_metadata;
        grpc_closure_init(&call->receiving_initial_metadata_ready,
                          receiving_initial_metadata_ready, bctl);
        bctl->recv_initial_metadata = 1;
        stream_op.recv_initial_metadata =
            &call->metadata_batch[1 /* is_receiving */][0 /* is_trailing */];
        stream_op.recv_initial_metadata_ready =
            &call->receiving_initial_metadata_ready;
        num_completion_callbacks_needed++;
        break;
    }
  }

  // do something
  
  // excute_op 就是从 call 获得 call element
  // 循环调用 call stack 上的 filter 的 start_transport_stream_op
  execute_op(exec_ctx, call, &stream_op);

done:
  // done

done_with_error:
  // dome with error
  goto done;
}

{% endhighlight %}

{:.center}
src/core/surface/call.c

可以看到最后执行到 *execute_op* 函数，这个函数只是调用 *call->elem->filter->start_transport_stream_op*。但之前服务注册的 *grpc_op* 的 *recv_initial_metadata* 为 *calld->initial_metadata*。再往回看就能看到 *call_data* 注册绑定的 channel 和 transport。

{% highlight c %}
// op.set_accept_stream_fn = accept_stream;
if (op->set_accept_stream) {
    t->channel_callback.accept_stream = op->set_accept_stream_fn;
    t->channel_callback.accept_stream_user_data =
        op->set_accept_stream_user_data;
}
{% endhighlight %}

{:.center}
src/core/transport/chttp2_transport.c

在处理到函数 *grpc_chttp2_parsing_accept_stream* 的时候，会调用。

{% highlight c %}
grpc_chttp2_stream_parsing *grpc_chttp2_parsing_accept_stream(
    grpc_exec_ctx *exec_ctx, grpc_chttp2_transport_parsing *transport_parsing,
    uint32_t id) {
  grpc_chttp2_stream *accepting;
  grpc_chttp2_transport *t = TRANSPORT_FROM_PARSING(transport_parsing);
  GPR_ASSERT(t->accepting_stream == NULL);
  t->accepting_stream = &accepting;
  // t 为 transport ...
  // t->channel_callback.accept_stream
  t->channel_callback.accept_stream(exec_ctx,
                                    t->channel_callback.accept_stream_user_data,
                                    &t->base, (void *)(uintptr_t)id);
  t->accepting_stream = NULL;
  return &accepting->parsing;
}
{% endhighlight %}

{:.center}
src/core/transport/chttp2_transport.c

上述代码最终会走到 *got_initial_metadata* 这个方法会调用 *start_new_rpc*。*start_new_rpc* 之后会调用 *finish_start_new_rpc*，调用完成后。会继续走到 *begin_call*。

{% highlight c %}
static void begin_call(grpc_exec_ctx *exec_ctx, grpc_server *server,
                       call_data *calld, requested_call *rc) {
  grpc_op ops[1];
  grpc_op *op = ops;

  memset(ops, 0, sizeof(ops));

  // 当 metada 被读取之后马上被调用
  // 插入到 completion queue
  grpc_call_set_completion_queue(exec_ctx, calld->call, rc->cq_bound_to_call);
  grpc_closure_init(&rc->publish, publish_registered_or_batch, rc);
  *rc->call = calld->call;
  calld->cq_new = rc->cq_for_notification;

  switch (rc->type) {
    case BATCH_CALL:
      cpstr(&rc->data.batch.details->host,
            &rc->data.batch.details->host_capacity, calld->host);
      cpstr(&rc->data.batch.details->method,
            &rc->data.batch.details->method_capacity, calld->path);
      rc->data.batch.details->deadline = calld->deadline;
      break;
    case REGISTERED_CALL:
      *rc->data.registered.deadline = calld->deadline;
      if (rc->data.registered.optional_payload) {
        op->op = GRPC_OP_RECV_MESSAGE;
        op->data.recv_message = rc->data.registered.optional_payload;
        op++;
      }
      break;
    default:
      GPR_UNREACHABLE_CODE(return );
  }

  grpc_call_start_batch_and_execute(exec_ctx, calld->call, ops,
                                    (size_t)(op - ops), &rc->publish);
}
{% endhighlight %}

{:.center}
src/core/surface/server.c

上面就是将一个 call 放入到一个 CompletionQueue 中。等待 Server 端循环读取 CompletionQueue。

### 相关文章

1. [Basic](/posts/grpc-python-bind-source-code-1/)
2. [Server](/posts/grpc-python-bind-source-code-2/)
3. [CompletionQueue](/posts/grpc-python-bind-source-code-3/)
4. [Stub](/posts/grpc-python-bind-source-code-4/)
5. [Channel and Call](/posts/grpc-python-bind-source-code-5/)

### 有关 C Core 的笔记

1. [Notes of gRPC](https://github.com/GuoJing/book-notes/tree/master/grpc)
