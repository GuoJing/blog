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

### Create TCP Server

其中 Python 如何启动 Server 就不深入看了，鉴于前面的文章已经写过了。现在直接看 C Core 代码。注意，这个时候 Server 还没调用 Start，还是先要绑定地址和端口，还在做这一步的操作。

{% highlight c %}
int grpc_server_add_insecure_http2_port(grpc_server *server, const char *addr) {
  grpc_resolved_addresses *resolved = NULL;
  // grpc tcp server 对象
  grpc_tcp_server *tcp = NULL;
  size_t i;
  unsigned count = 0;
  int port_num = -1;
  int port_temp;
  grpc_exec_ctx exec_ctx = GRPC_EXEC_CTX_INIT;

  // 增加一个 grpc address 的绑定
  resolved = grpc_blocking_resolve_address(addr, "http");
  if (!resolved) {
    // 如果搞不定就出错啦
    goto error;
  }

  // 创建一个 tcp server
  tcp = grpc_tcp_server_create(NULL);
  GPR_ASSERT(tcp);

  // 循环绑定端口到 tcp server
  for (i = 0; i < resolved->naddrs; i++) {
    port_temp = grpc_tcp_server_add_port(
        tcp, (struct sockaddr *)&resolved->addrs[i].addr,
        resolved->addrs[i].len);
    if (port_temp > 0) {
      if (port_num == -1) {
        port_num = port_temp;
      } else {
        GPR_ASSERT(port_num == port_temp);
      }
      count++;
    }
  }
  
  // 如果没有任何绑定就报错
  if (count == 0) {
    gpr_log(GPR_ERROR, "No address added out of total %d resolved",
            resolved->naddrs);
    goto error;
  }
  
  // 检查绑定数量
  if (count != resolved->naddrs) {
    gpr_log(GPR_ERROR, "Only %d addresses added out of total %d resolved",
            count, resolved->naddrs);
  }
  
  grpc_resolved_addresses_destroy(resolved);

  // grpc server 增加一个 listener
  // 这个 listener 是 tcp 对象
  grpc_server_add_listener(&exec_ctx, server, tcp, start, destroy);
  goto done;

// 错误处理
error:
  if (resolved) {
    grpc_resolved_addresses_destroy(resolved);
  }
  if (tcp) {
    grpc_tcp_server_unref(&exec_ctx, tcp);
  }
  port_num = 0;

done:
  grpc_exec_ctx_finish(&exec_ctx);
  return port_num;
}
{% endhighlight %}

{:.center}
src/core/surface/server_chttp2.c

上面的代码不仅创建了一个 TCP Server，还给 server 添加了各种 listener。每个 listener 都是 tcp server 的实例。*grpc_tcp_server_create* 是一个重要的函数。可以进去看看这个函数在做什么。

{% highlight c %}
grpc_tcp_server *grpc_tcp_server_create(grpc_closure *shutdown_complete) {
  // 分配内存
  grpc_tcp_server *s = gpr_malloc(sizeof(grpc_tcp_server));
  // 增加引用数量
  gpr_ref_init(&s->refs, 1);
  gpr_mu_init(&s->mu);
  // 激活的端口数量
  s->active_ports = 0;
  // 注销的端口数量
  s->destroyed_ports = 0;
  // 是否正在关闭
  s->shutdown = 0;
  s->shutdown_starting.head = NULL;
  s->shutdown_starting.tail = NULL;
  s->shutdown_complete = shutdown_complete;
  // 当获得数据的时候调用的 callback 函数
  s->on_accept_cb = NULL;
  // 当获得数据的时候调用的 callback 参数
  s->on_accept_cb_arg = NULL;
  // 头部的 grpc_tcp_listener
  s->head = NULL;
  // 尾部的 grpc_tcp_listener
  s->tail = NULL;
  s->nports = 0;
  return s;
}
{% endhighlight %}

{:.center}
src/core/iomgr/tcp_server_posix.c

从上面来看就初始化了一个 tcp server。

### Bind listener

一个 Listener 的结构体如下。

{% highlight c %}
typedef struct grpc_tcp_listener grpc_tcp_listener;
struct grpc_tcp_listener {
  int fd;
  grpc_fd *emfd;
  grpc_tcp_server *server;
  union {
    uint8_t untyped[GRPC_MAX_SOCKADDR_SIZE];
    struct sockaddr sockaddr;
    struct sockaddr_un un;
  } addr;
  size_t addr_len;
  int port;
  unsigned port_index;
  unsigned fd_index;
  grpc_closure read_closure;
  grpc_closure destroyed_closure;
  struct grpc_tcp_listener *next;
  struct grpc_tcp_listener *sibling;
  int is_sibling;
};
{% endhighlight %}

{:.center}
src/core/iomgr/tcp_server_posix.c

创建 TCP Server 绑定了 listener，绑定 listener 的代码非常简单。

{% highlight c %}
void grpc_server_add_listener(
    grpc_exec_ctx *exec_ctx, grpc_server *server, void *arg,
    void (*start)(grpc_exec_ctx *exec_ctx, grpc_server *server, void *arg,
                  grpc_pollset **pollsets, size_t pollset_count),
    void (*destroy)(grpc_exec_ctx *exec_ctx, grpc_server *server, void *arg,
                    grpc_closure *on_done)) {
  // 初始化 listener
  listener *l = gpr_malloc(sizeof(listener));
  // 绑定 listener 的方法
  l->arg = arg;
  l->start = start;
  l->destroy = destroy;
  // 增加到 listener 链表中
  l->next = server->listeners;
  server->listeners = l;
}
{% endhighlight %}

{:.center}
src/core/server.c

绑定 listner 之后，server 启动时，就会调用每个 listener 的 start 方法。

### Server Start

在创建了 TCP Server 实例并绑定 listener 之后，还需要回到 server 这部分代码，最后看看是如何启动的。

{% highlight c %}
void grpc_server_start(grpc_server *server) {
  listener *l;
  size_t i;
  grpc_exec_ctx exec_ctx = GRPC_EXEC_CTX_INIT;

  server->pollsets = gpr_malloc(sizeof(grpc_pollset *) * server->cq_count);
  for (i = 0; i < server->cq_count; i++) {
    server->pollsets[i] = grpc_cq_pollset(server->cqs[i]);
  }
  
  // 每个 listener 都调用 start 函数
  for (l = server->listeners; l; l = l->next) {
    l->start(&exec_ctx, server, l->arg, server->pollsets, server->cq_count);
  }

  grpc_exec_ctx_finish(&exec_ctx);
}
{% endhighlight %}

{:.center}
src/core/surface/server.c

可以看到，server start 方法就是让 server 下的每个 tcp listener 都调用 start 方法。

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

### Server 底层实现

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
  # 开始读取
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
  # 接收数据
  recv_data(exec_ctx, t, 1);
}
{% endhighlight %}

{:.center}
src/transport/chttp2_transport.c
