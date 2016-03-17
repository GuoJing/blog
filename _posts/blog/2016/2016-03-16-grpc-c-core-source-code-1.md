---
layout:    post
title:     gRPC C Core 源码浅析 - Server
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

### TCP Server Start

Server 启动的方法很简单，又是调用了底层的部分，但是 start 之后如何和客户端通信的，需要再深入了解。

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
  grpc_transport *transport = grpc_create_chttp2_transport(
      exec_ctx, grpc_server_get_channel_args(server), tcp, 0);
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
  recv_data(exec_ctx, t, 1);
}
{% endhighlight %}

{:.center}
src/transport/chttp2_transport.c

TODO: coming soon

### 相关文章

1. [Basic](/posts/grpc-python-bind-source-code-1/)
2. [Server](/posts/grpc-python-bind-source-code-2/)
3. [CompletionQueue](/posts/grpc-python-bind-source-code-3/)
4. [Stub](/posts/grpc-python-bind-source-code-4/)
5. [Channel and Call](/posts/grpc-python-bind-source-code-5/)

### 有关 C Core 的笔记

1. [Notes of gRPC](https://github.com/GuoJing/book-notes/tree/master/grpc)
