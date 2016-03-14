---
layout:    post
title:     gRPC Python 源码浅析 - 2
category:  blog
description: gRPC Python 源码
tags: gRPC Python Google Source Coding HTTP2
---
### Overview

在启动一个服务的时候，gRPC 进行了多层调用才最终启动服务，Python 只是一个语言的 wrapper，自己并不负责真正的 gRPC 的服务启动。在这里可以了解一个服务是如何起起来的。

### server.start

我们先从 Server 这一块看代码。从 server.start() 进去。

Python 这一块代码都在 grpc 项目根路径下的 *src/python/grpcio* 中。

{% highlight python %}
# 从生成的 pb2 文件看到引用路径
# from grpc.beta import implementations as beta_implementations

def server(service_implementations, options=None):
  effective_options = _EMPTY_SERVER_OPTIONS if options is None else options
  # 从 _server 中引入了 server
  return _server.server(
      service_implementations, effective_options.multi_method_implementation,
      effective_options.request_deserializers,
      effective_options.response_serializers, effective_options.thread_pool,
      effective_options.thread_pool_size, effective_options.default_timeout,
      effective_options.maximum_timeout)

{% endhighlight %}

{:.center}
grpc/beta/implementations.py

继续深入。

{% highlight python %}
# 进入到 grpc.beta._server 文件中查看
class _GRPCServicer(base.Servicer):

  def __init__(self, delegate):
    self._delegate = delegate

  def service(self, group, method, context, output_operator):
    # do something

class _Server(interfaces.Server):

  def _start(self):
    with self._lock:
      servicer = _GRPCServicer(
          _crust_implementations.servicer(
              self._implementations, self._multi_implementation, assembly_pool))

      self._end_link = _core_implementations.service_end_link(
          servicer, self._default_timeout, self._maximum_timeout)

      self._grpc_link.join_link(self._end_link)
      self._end_link.join_link(self._grpc_link)
      # link 是 grpc 中真正起作用的
      self._grpc_link.start()
      self._end_link.start()

def server(
    implementations, multi_implementation, request_deserializers,
    response_serializers, thread_pool, thread_pool_size, default_timeout,
    maximum_timeout):
  # 初始化 grpc link, 通过 service 的 service_link 创建 _ServiceLink
  grpc_link = service.service_link(request_deserializers, response_serializers)
  # 创建一个 Server 对象
  return _Server(
      implementations, multi_implementation, thread_pool,
      _DEFAULT_POOL_SIZE if thread_pool_size is None else thread_pool_size,
      _DEFAULT_TIMEOUT if default_timeout is None else default_timeout,
      _MAXIMUM_TIMEOUT if maximum_timeout is None else maximum_timeout,
      grpc_link)
{% endhighlight %}

{:.center}
grpc/beta/_server.py

我们从中可以看出，Server 真正起作用的是 link，我们再深入看一下 link。

{% highlight python %}
def service_link(request_deserializers, response_serializers):
    return _ServiceLink(request_deserializers, response_serializers)

class _ServiceLink(ServiceLink):
  def start(self):
    # 跑起一个 service
    self._relay.start()
    # 真正跑起来的是 _kernel
    return self._kernel.start()

class _Kernel(object):
  # 真正开始跑起 server 了
  def start(self):
    with self._lock:
      if self._server is None:
        # 创建一个 completion queue
        # 这个队列要注册到 service 中
        # 会有线程循环读取队列中的 envent
        self._completion_queue = _intermediary_low.CompletionQueue()
        self._server = _intermediary_low.Server(self._completion_queue)
      # logging_pool 就是线程的创建对象
      self._pool = logging_pool.pool(1)
      self._pool.submit(self._spin, self._completion_queue, self._server)
      # 仅仅开始服务
      # 队列从前面的 logging pool 创建的线程中执行
      self._server.start()
      self._server.service(None)
      self._due.add(_SERVICE)
{% endhighlight %}

{:.center}
grpc/_links/service.py

不过从上面的代码来看，Server 还是从 *_intermediary_low* 中读取，继续向下面挖。

{% highlight python %}
class Server(_types.Server):

  def __init__(self, completion_queue, args):
    args = cygrpc.ChannelArgs(
        cygrpc.ChannelArg(key, value) for key, value in args)
    # 终于到 cython 中的 Server 了
    self.server = cygrpc.Server(args)
    self.server.register_completion_queue(completion_queue.completion_queue)
    self.server_queue = completion_queue

  def start(self):
    return self.server.start()
{% endhighlight %}

{:.center}
grpc/_adapter/_intermediary_low.py

我们终于看到曙光了，我们直接打开 *_cython/_cygrpc/server.pxi* 文件看如何跑起一个 server。

{% highlight python %}

cdef class Server:
  def start(self):
    if self.is_started:
      raise ValueError("the server has already started")
    self.backup_shutdown_queue = CompletionQueue()
    self.register_completion_queue(self.backup_shutdown_queue)
    self.is_started = True
    # 终于，我们看到调用到 grpc c core 的代码了
    grpc_server_start(self.c_server)
    # Ensure the core has gotten a chance to do the start-up work
    self.backup_shutdown_queue.pluck(None, Timespec(None))
{% endhighlight %}

{:.center}
grpc/_cython/_cygrpc/server.pxi

现在可以打开 grpc 根路径里的 *src/core/surface/server.c* 看这个方法如何实现。

{% highlight c %}
void grpc_server_start(grpc_server *server) {
  listener *l;
  size_t i;
  grpc_exec_ctx exec_ctx = GRPC_EXEC_CTX_INIT;

  GRPC_API_TRACE("grpc_server_start(server=%p)", 1, (server));

  // 初始化 poolsets
  server->pollsets = gpr_malloc(sizeof(grpc_pollset *) * server->cq_count);
  for (i = 0; i < server->cq_count; i++) {
    server->pollsets[i] = grpc_cq_pollset(server->cqs[i]);
  }

  // 给每个 listeners 进行初始化
  // server->cq 就是 complete queue
  // 每个 listener 都可以 start
  for (l = server->listeners; l; l = l->next) {
    l->start(&exec_ctx, server, l->arg, server->pollsets, server->cq_count);
  }

  grpc_exec_ctx_finish(&exec_ctx);
}
{% endhighlight %}

{:.center}
src/core/surface/server.c

虽然看上去我们的 server 跑起来了，但是 listener 是怎么跑起来的，这个又是什么东西？如果我们往回看，就会发现在跑 server 之前，注册了 http2 port，实际上就是 server.pyx.pxi 文件中的 *add_http2_port* 方法。

{% highlight python %}
def add_http2_port(self, address,
    ServerCredentials server_credentials=None):
    if isinstance(address, bytes):
      pass
    elif isinstance(address, basestring):
      address = address.encode()
    else:
      raise TypeError("expected address to be a str or bytes")
    self.references.append(address)
    # 在这里注册了 listener
    if server_credentials is not None:
      self.references.append(server_credentials)
      # 代码在 src/core/surface/server_secure_chttp2.c
      return grpc_server_add_secure_http2_port(
          self.c_server, address, server_credentials.c_credentials)
    else:
      # 代码在 src/core/security/server_chttp2.c
      return grpc_server_add_insecure_http2_port(self.c_server, address)
{% endhighlight %}

{:.center}
grpc/_cython/_cygrpc/server.pxi

我们可以搜索 *grpc_server_add_insecure_http2_port* 函数，找到定义。

{% highlight c %}
int grpc_server_add_insecure_http2_port(grpc_server *server, const char *addr) {
  grpc_resolved_addresses *resolved = NULL;
  grpc_tcp_server *tcp = NULL;
  size_t i;
  unsigned count = 0;
  int port_num = -1;
  int port_temp;
  grpc_exec_ctx exec_ctx = GRPC_EXEC_CTX_INIT;
  // ....
  grpc_resolved_addresses_destroy(resolved);

  /* 注册 listener */
  grpc_server_add_listener(&exec_ctx, server, tcp, start, destroy);
  goto done;

done:
  grpc_exec_ctx_finish(&exec_ctx);
  return port_num;
}

{% endhighlight %}

{:.center}
src/core/surface/server_chttp2.c

可以看到里面调用了 *grpc_server_add_listener*。至于什么时候 add port，当然是我们在 Python 代码一开始就绑定了端口，再 start 的了。

### 线程池

可以看到 gRPC server 还有很多参数，最重要的是还支持线程池，实现线程池非常简单[^1]。

{% highlight python %}
from concurrent.futures import ThreadPoolExecutor

pool = ThreadPoolExecutor(max_workers=GRPC_POOL_MAX_WORKER)
    server = hello_pb2.beta_create_HelloService_server(
        ServerImpl(), pool=pool, pool_size=GRPC_POOL_SIZE,
        default_timeout=30, maximum_timeout=60)
{% endhighlight %}

{:.center}
sample.py

就可以看到服务器上请求多的时候，开启了线程池，不过鉴于 Python 有 GIL，性能提升暂时未测试。但可以看到，暂时我们的 Server 这一端就跑起来了。

线程池在代码里有很大的用，在之后的代码解析中会更深入的挖掘。

[^1]: 但是没有文档，只能从代码里看，找到灵感的是 logging_pool。

### 相关文章

1. [Basic](/posts/grpc-python-bind-source-code-1/)
2. [Server](/posts/grpc-python-bind-source-code-2/)
3. [CompletionQueue](/posts/grpc-python-bind-source-code-3/)
4. [Stub](/posts/grpc-python-bind-source-code-4/)
5. [Channel](/posts/grpc-python-bind-source-code-5/)

### 有关 C Core 的笔记

1. [Notes of gRPC](https://github.com/GuoJing/book-notes/tree/master/grpc)
