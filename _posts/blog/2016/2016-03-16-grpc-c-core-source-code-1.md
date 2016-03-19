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
  // sp 是 tcp server
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

### Create Http2 Transport

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

### Setup Transport

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

### Receive Data

在创建 HTTP2 Transport 之后，就可以看 start reading 这件事了。这个函数主要是获取传输的数据。

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
  // 这个 init_frame_parser 根据不同的 frame 类型调用不同的函数
  // 举例如果是 header frame 则会走到 init_header_frame_parser
  // 最后走到 grpc_chttp2_parsing_accept_stream
  // 就会调用到高级的 t->channel_callback.accept_stream 这个函数
  // 而这个函数就是 op->set_accept_stream_fn
  // 最后这个函数就是 accept_stream
  recv_data(exec_ctx, t, 1);
}
{% endhighlight %}

{:.center}
src/transport/chttp2_transport.c

现在看看 recv_data。

{% highlight c %}
/* tcp read callback */
static void recv_data(grpc_exec_ctx *exec_ctx, void *tp, bool success) {
  size_t i;
  int keep_reading = 0;
  grpc_chttp2_transport *t = tp;
  grpc_chttp2_transport_global *transport_global = &t->global;
  grpc_chttp2_transport_parsing *transport_parsing = &t->parsing;
  grpc_chttp2_stream_global *stream_global;

  GPR_TIMER_BEGIN("recv_data", 0);

  lock(t);
  i = 0;
  GPR_ASSERT(!t->parsing_active);
  if (!t->closed) {
    t->parsing_active = 1;
    /* merge stream lists */
    grpc_chttp2_stream_map_move_into(&t->new_stream_map,
                                     &t->parsing_stream_map);
    grpc_chttp2_prepare_to_read(transport_global, transport_parsing);
    gpr_mu_unlock(&t->mu);
    GPR_TIMER_BEGIN("recv_data.parse", 0);
    // 读取并调用 grpc_chttp2_perform_read
    // 调用了 init_frame_parser
    // 调用了 init_data_frame_parser
    for (; i < t->read_buffer.count &&
               grpc_chttp2_perform_read(exec_ctx, transport_parsing,
                                        t->read_buffer.slices[i]);
         i++)
      ;
    GPR_TIMER_END("recv_data.parse", 0);
    gpr_mu_lock(&t->mu);
    /* copy parsing qbuf to global qbuf */
    gpr_slice_buffer_move_into(&t->parsing.qbuf, &t->global.qbuf);
    if (i != t->read_buffer.count) {
      unlock(exec_ctx, t);
      lock(t);
      drop_connection(exec_ctx, t);
    }
    /* merge stream lists */
    grpc_chttp2_stream_map_move_into(&t->new_stream_map,
                                     &t->parsing_stream_map);
    transport_global->concurrent_stream_count =
        (uint32_t)grpc_chttp2_stream_map_size(&t->parsing_stream_map);
    if (transport_parsing->initial_window_update != 0) {
      grpc_chttp2_stream_map_for_each(&t->parsing_stream_map,
                                      update_global_window, t);
      transport_parsing->initial_window_update = 0;
    }
    /* handle higher level things */
    grpc_chttp2_publish_reads(exec_ctx, transport_global, transport_parsing);
    t->parsing_active = 0;
    /* handle delayed transport ops (if there is one) */
    if (t->post_parsing_op) {
      grpc_transport_op *op = t->post_parsing_op;
      t->post_parsing_op = NULL;
      perform_transport_op_locked(exec_ctx, t, op);
      gpr_free(op);
    }
    /* if a stream is in the stream map, and gets cancelled, we need to ensure
     * we are not parsing before continuing the cancellation to keep things in
     * a sane state */
    while (grpc_chttp2_list_pop_closed_waiting_for_parsing(transport_global,
                                                           &stream_global)) {
      GPR_ASSERT(stream_global->in_stream_map);
      GPR_ASSERT(stream_global->write_closed);
      GPR_ASSERT(stream_global->read_closed);
      remove_stream(exec_ctx, t, stream_global->id);
      GRPC_CHTTP2_STREAM_UNREF(exec_ctx, stream_global, "chttp2");
    }
  }
  if (!success || i != t->read_buffer.count || t->closed) {
    drop_connection(exec_ctx, t);
    read_error_locked(exec_ctx, t);
  } else if (!t->closed) {
    keep_reading = 1;
    REF_TRANSPORT(t, "keep_reading");
    prevent_endpoint_shutdown(t);
  }
  gpr_slice_buffer_reset_and_unref(&t->read_buffer);
  unlock(exec_ctx, t);

  if (keep_reading) {
    grpc_endpoint_read(exec_ctx, t->ep, &t->read_buffer, &t->recv_data);
    allow_endpoint_shutdown_unlocked(exec_ctx, t);
    UNREF_TRANSPORT(exec_ctx, t, "keep_reading");
  } else {
    UNREF_TRANSPORT(exec_ctx, t, "recv_data");
  }

  GPR_TIMER_END("recv_data", 0);
}
{% endhighlight %}

{:.center}
src/transport/chttp2_transport.c

可以看看 *init_frame_parser* 函数。

{% highlight c %}
static int init_frame_parser(grpc_exec_ctx *exec_ctx,
                             grpc_chttp2_transport_parsing *transport_parsing) {
  if (transport_parsing->expect_continuation_stream_id != 0) {
    if (transport_parsing->incoming_frame_type !=
        GRPC_CHTTP2_FRAME_CONTINUATION) {
      gpr_log(GPR_ERROR, "Expected CONTINUATION frame, got frame type %02x",
              transport_parsing->incoming_frame_type);
      return 0;
    }
    if (transport_parsing->expect_continuation_stream_id !=
        transport_parsing->incoming_stream_id) {
      gpr_log(GPR_ERROR,
              "Expected CONTINUATION frame for grpc_chttp2_stream %08x, got "
              "grpc_chttp2_stream %08x",
              transport_parsing->expect_continuation_stream_id,
              transport_parsing->incoming_stream_id);
      return 0;
    }
    return init_header_frame_parser(exec_ctx, transport_parsing, 1);
  }
  // 根据不同的帧类型调用不同的函数
  switch (transport_parsing->incoming_frame_type) {
    case GRPC_CHTTP2_FRAME_DATA:
      return init_data_frame_parser(exec_ctx, transport_parsing);
    case GRPC_CHTTP2_FRAME_HEADER:
      return init_header_frame_parser(exec_ctx, transport_parsing, 0);
    case GRPC_CHTTP2_FRAME_CONTINUATION:
      gpr_log(GPR_ERROR, "Unexpected CONTINUATION frame");
      return 0;
    case GRPC_CHTTP2_FRAME_RST_STREAM:
      return init_rst_stream_parser(exec_ctx, transport_parsing);
    case GRPC_CHTTP2_FRAME_SETTINGS:
      return init_settings_frame_parser(exec_ctx, transport_parsing);
    case GRPC_CHTTP2_FRAME_WINDOW_UPDATE:
      return init_window_update_frame_parser(exec_ctx, transport_parsing);
    case GRPC_CHTTP2_FRAME_PING:
      return init_ping_parser(exec_ctx, transport_parsing);
    case GRPC_CHTTP2_FRAME_GOAWAY:
      return init_goaway_parser(exec_ctx, transport_parsing);
    default:
      gpr_log(GPR_ERROR, "Unknown frame type %02x",
              transport_parsing->incoming_frame_type);
      return init_skip_frame_parser(exec_ctx, transport_parsing, 0);
  }
}
{% endhighlight %}

{:.center}
transport/chttp2/parsing.c

假设是读的 *GRPC_CHTTP2_FRAME_DATA* 那么，调用的函数就是 *init_data_frame_parser*。

{% highlight c %}
static int init_data_frame_parser(
    grpc_exec_ctx *exec_ctx, grpc_chttp2_transport_parsing *transport_parsing) {
  grpc_chttp2_stream_parsing *stream_parsing =
      grpc_chttp2_parsing_lookup_stream(transport_parsing,
                                        transport_parsing->incoming_stream_id);
  grpc_chttp2_parse_error err = GRPC_CHTTP2_PARSE_OK;
  if (!stream_parsing || stream_parsing->received_close)
    return init_skip_frame_parser(exec_ctx, transport_parsing, 0);
  if (err == GRPC_CHTTP2_PARSE_OK) {
    err = update_incoming_window(exec_ctx, transport_parsing, stream_parsing);
  }
  if (err == GRPC_CHTTP2_PARSE_OK) {
    err = grpc_chttp2_data_parser_begin_frame(
        &stream_parsing->data_parser, transport_parsing->incoming_frame_flags);
  }
  switch (err) {
    // 如果 parse 成功
    case GRPC_CHTTP2_PARSE_OK:
      // 设置 transport_parsing stream
      transport_parsing->incoming_stream = stream_parsing;
      // 设置 parser
      transport_parsing->parser = grpc_chttp2_data_parser_parse;
      // 设置 parser_data
      transport_parsing->parser_data = &stream_parsing->data_parser;
      return 1;
    case GRPC_CHTTP2_STREAM_ERROR:
      stream_parsing->received_close = 1;
      stream_parsing->saw_rst_stream = 1;
      stream_parsing->rst_stream_reason = GRPC_CHTTP2_PROTOCOL_ERROR;
      gpr_slice_buffer_add(
          &transport_parsing->qbuf,
          grpc_chttp2_rst_stream_create(transport_parsing->incoming_stream_id,
                                        GRPC_CHTTP2_PROTOCOL_ERROR));
      return init_skip_frame_parser(exec_ctx, transport_parsing, 0);
    case GRPC_CHTTP2_CONNECTION_ERROR:
      return 0;
  }
  GPR_UNREACHABLE_CODE(return 0);
}
{% endhighlight %}

{:.center}
transport/chttp2/parsing.c

### HEAD FRAME

在 HTTP2 中， HEADER FRAME 的作用是打开一个 stream。如果 Frame 类型是 *GRPC_CHTTP2_FRAME_HEADER*，那么就走的是 *init_header_frame_parser* 函数。那么这个函数会走到 *grpc_chttp2_parsing_accept_stream* 上。

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
  // 其实这里就是
  // op->set_accept_stream_fn(op->accept_stream_user_data)
  // 而 t->channel_callback.accept_stream_user_data =
  //       op->set_accept_stream_user_data;
  t->channel_callback.accept_stream(exec_ctx,
                                    t->channel_callback.accept_stream_user_data,
                                    &t->base, (void *)(uintptr_t)id);
  t->accepting_stream = NULL;
  return &accepting->parsing;
}
{% endhighlight %}

{:.center}
src/core/transport/chttp2_transport.c

而从之前的代码可以知道 *set_accept_stream_fn* 就是 *accept stream*。

### Accept Stream

所以我们知道最终会走到 accept stream 这个函数，现在就来看看这个函数做了什么。

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

其中 op 是一个 *grpc_op*，会走到 *grpc_call_start_batch_and_execute*。虽然之前在 [Channel and Call](/posts/grpc-python-bind-source-code-5/) 中看了这个代码，现在我们要更深入的了解这个代码。

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

可以看到最后执行到 *execute_op* 函数。

{% highlight c %}
static void execute_op(grpc_exec_ctx *exec_ctx, grpc_call *call,
                       grpc_transport_stream_op *op) {
  grpc_call_element *elem;

  GPR_TIMER_BEGIN("execute_op", 0);
  elem = CALL_ELEM_FROM_CALL(call, 0);
  op->context = call->context;
  elem->filter->start_transport_stream_op(exec_ctx, elem, op);
  GPR_TIMER_END("execute_op", 0);
}
{% endhighlight %}

{:.center}
src/core/surface/call.c

这时候我们最需要知道的就是 elem->filter 是什么。就需要知道 call 是什么。call 是来自 accept stream 的，那么就是通过 *grpc_call_create* 中第一个参数 *chand->channel* 来创建。其中有 *grpc_call_stack_init*，那么就知道这个 elem 的 channel 就是 *chand->channel*。

那么看 *chand->channel* 是 *t->channel_callback.accept_stream_user_data* 。而这里的 *stream_user_data* 就是 *chand*，所以 channel 就是 *grpc_server_setup_transport* 函数创建的 channel。

### HTTP Server Filter

在 channel 初始化的时候，还有 *grpc_http_server_filter*。所以我们来看一下这个函数。

{% highlight c %}
static void init_call_elem(grpc_exec_ctx *exec_ctx, grpc_call_element *elem,
                           grpc_call_element_args *args) {
  call_data *calld = elem->call_data;
  memset(calld, 0, sizeof(*calld));
  // 绑定了 hs_on_recv 到 hs_on_recv
  grpc_closure_init(&calld->hs_on_recv, hs_on_recv, elem);
}

static void init_channel_elem(grpc_exec_ctx *exec_ctx,
                              grpc_channel_element *elem,
                              grpc_channel_element_args *args) {
  // 做了一下检查
  GPR_ASSERT(!args->is_last);
}
{% endhighlight %}

{:.center}
channel/http_server_filter.c

调用 *elem->start_transport_stream_op* 的时候，调用的是 *hs_start_transport_op*。

{% highlight c %}
static void hs_start_transport_op(grpc_exec_ctx *exec_ctx,
                                  grpc_call_element *elem,
                                  grpc_transport_stream_op *op) {
  GRPC_CALL_LOG_OP(GPR_INFO, elem, op);
  GPR_TIMER_BEGIN("hs_start_transport_op", 0);
  hs_mutate_op(elem, op);
  grpc_call_next_op(exec_ctx, elem, op);
  GPR_TIMER_END("hs_start_transport_op", 0);
}
{% endhighlight %}

{:.center}
channel/http_server_filter.c

其中又设置了 elem 的属性。

{% highlight c %}
static void hs_mutate_op(grpc_call_element *elem,
                         grpc_transport_stream_op *op) {
  call_data *calld = elem->call_data;

  if (op->send_initial_metadata != NULL && !calld->sent_status) {
    calld->sent_status = 1;
    grpc_metadata_batch_add_head(op->send_initial_metadata, &calld->status,
                                 GRPC_MDELEM_STATUS_200);
    grpc_metadata_batch_add_tail(
        op->send_initial_metadata, &calld->content_type,
        GRPC_MDELEM_CONTENT_TYPE_APPLICATION_SLASH_GRPC);
  }

  if (op->recv_initial_metadata) {
    // call_data->recv_initial_metadata 为 op->recv_initial_metadata
    // call_data->on_done_recv 为 op->recv_initial_metadata_ready
    calld->recv_initial_metadata = op->recv_initial_metadata;
    calld->on_done_recv = op->recv_initial_metadata_ready;
    op->recv_initial_metadata_ready = &calld->hs_on_recv;
  }
}
{% endhighlight %}

{:.center}
channel/http_server_filter.c


{% highlight c %}
static void hs_on_recv(grpc_exec_ctx *exec_ctx, void *user_data, bool success) {
  grpc_call_element *elem = user_data;
  call_data *calld = elem->call_data;
  if (success) {
    server_filter_args a;
    a.elem = elem;
    a.exec_ctx = exec_ctx;
    grpc_metadata_batch_filter(calld->recv_initial_metadata, server_filter, &a);
    if (calld->seen_post && calld->seen_scheme && calld->seen_te_trailers &&
        calld->seen_path && calld->seen_authority) {
        // do nothing now
    } else {
      // on error ..
      success = 0;
      grpc_call_element_send_cancel(exec_ctx, elem);
    }
  }

  // 最终调用了 on_done_recv 的 callback
  // 就是 stream_op.recv_initial_metadata_ready
  // 然后 receiving_initial_metadata_ready
  calld->on_done_recv->cb(exec_ctx, calld->on_done_recv->cb_arg, success);
}
{% endhighlight %}

{:.center}
src/core/channel/http_server_filter.c

### Connected Channel Filter

再看看还有的 *grpc_connected_channel_filter*。先看定义。

{% highlight c %}
const grpc_channel_filter grpc_connected_channel_filter = {
    con_start_transport_stream_op, con_start_transport_op, sizeof(call_data),
    init_call_elem, set_pollset, destroy_call_elem, sizeof(channel_data),
    init_channel_elem, destroy_channel_elem, con_get_peer, "connected",
};
{% endhighlight %}

{:.center}
src/core/channel/connected_channel.c

再看 *init_channel_elem*。

{% highlight c %}
static void init_channel_elem(grpc_exec_ctx *exec_ctx,
                              grpc_channel_element *elem,
                              grpc_channel_element_args *args) {
  channel_data *cd = (channel_data *)elem->channel_data;
  GPR_ASSERT(args->is_last);
  GPR_ASSERT(elem->filter == &grpc_connected_channel_filter);
  cd->transport = NULL;
}
{% endhighlight %}

{:.center}
src/core/channel/connected_channel.c

再看 *init_call_elem*。

{% highlight c %}
static void init_call_elem(grpc_exec_ctx *exec_ctx, grpc_call_element *elem,
                           grpc_call_element_args *args) {
  call_data *calld = elem->call_data;
  channel_data *chand = elem->channel_data;
  int r;

  GPR_ASSERT(elem->filter == &grpc_connected_channel_filter);
  r = grpc_transport_init_stream(
      exec_ctx, chand->transport, TRANSPORT_STREAM_FROM_CALL_DATA(calld),
      &args->call_stack->refcount, args->server_transport_data);
  GPR_ASSERT(r == 0);
}
{% endhighlight %}

{:.center}
src/core/channel/connected_channel.c

最后依旧走到 *con_start_transport_stream_op*。

{% highlight c %}
static void con_start_transport_stream_op(grpc_exec_ctx *exec_ctx,
                                          grpc_call_element *elem,
                                          grpc_transport_stream_op *op) {
  call_data *calld = elem->call_data;
  channel_data *chand = elem->channel_data;
  GPR_ASSERT(elem->filter == &grpc_connected_channel_filter);
  GRPC_CALL_LOG_OP(GPR_INFO, elem, op);

  grpc_transport_perform_stream_op(exec_ctx, chand->transport,
                                   TRANSPORT_STREAM_FROM_CALL_DATA(calld), op);
}
{% endhighlight %}

{:.center}
src/core/channel/connected_channel.c

然后，就是 *perform_stream_op_locked*。最终就走到了 *grpc_chttp2_complete_closure_step* 函数。将回调放入了 closure 列表中。

{% highlight c %}
void grpc_chttp2_complete_closure_step(grpc_exec_ctx *exec_ctx,
                                       grpc_closure **pclosure, int success) {
  grpc_closure *closure = *pclosure;
  if (closure == NULL) {
    return;
  }
  closure->final_data -= 2;
  if (!success) {
    closure->final_data |= 1;
  }
  if (closure->final_data < 2) {
    grpc_exec_ctx_enqueue(exec_ctx, closure, closure->final_data == 0, NULL);
  }
  *pclosure = NULL;
}
{% endhighlight %}

{:.center}
src/core/transport/chttp2_transport.c

Closure 对象将在后面提到。

### 相关文章

1. [Basic](/posts/grpc-python-bind-source-code-1/)
2. [Server](/posts/grpc-python-bind-source-code-2/)
3. [CompletionQueue](/posts/grpc-python-bind-source-code-3/)
4. [Stub](/posts/grpc-python-bind-source-code-4/)
5. [Channel and Call](/posts/grpc-python-bind-source-code-5/)
6. [TCP Server](/posts/grpc-c-core-source-code-1/)

### 有关 C Core 的笔记

1. [Notes of gRPC](https://github.com/GuoJing/book-notes/tree/master/grpc)
