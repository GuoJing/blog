---
layout:    post
title:     gRPC Python 源码浅析 - CompletionQueue
category:  blog
description: gRPC Python 源码
tags: gRPC Python Google Source Coding HTTP2 CompletionQueue
---
### Overview

在了解 Server 是如何启动的之后，可以看看在 Server 启动后最重要的另一个主要负责任务的代码，这一部分代码就是 CompletionQueue。相对而言，CompletionQueue 会相对简单一点。

### CompletionQueue

CompletionQueue 对创建服务方外面来说是透明的，所以我们在实例化一个 server 对象的时候，并不需要手动的指定 CompletionQueue，我们可以在代码中找到。

{% highlight python %}
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
      self._grpc_link.start()
      self._end_link.start()
{% endhighlight %}

{:.center}
grpc/beta/_service.py

还是找到 *_Server* 中真正 *_start* 的方法，进入到 *_link* 中去。

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
      # 这里是一行非常重要的代码
      # 注册了 completion_queue 和 server 的线程逻辑
      # 当 complete queue 获得 event 之后
      # 会回来调用 self._spin 函数
      self._pool.submit(self._spin, self._completion_queue, self._server)
      # 仅仅开始服务
      # 队列从前面的 logging pool 创建的线程中执行
      self._server.start()
      self._server.service(None)
      self._due.add(_SERVICE)
{% endhighlight %}

{:.center}
grpc/_links/service.py

到这里，我们可以看到内部创建了一个 CompletionQueue，不看 Server 如何实现，直接进入到 Queue 去研究。

{% highlight python %}
class CompletionQueue(object):
  """Adapter from old _low.CompletionQueue interface to new _low.CompletionQueue."""
  def __init__(self):
    # 可以从 grpc 里的很多代码看到
    # _internal 都是调用稍微底层的
    # 实现
    self._internal = _low.CompletionQueue()

  def get(self, deadline=None):
    # self._internal.next
    # 这里调用了 _internal 的 next
    # 是比较重要的
    return result_ev

  def stop(self):
    self._internal.shutdown()
{% endhighlight %}

{:.center}
grpc/_adapter/_intermediary_low.py

和 Sever 一样，Queue 也有一个更加底层的 Queue 实现。继续挖。

{% highlight python %}
class CompletionQueue(_types.CompletionQueue):

  def __init__(self):
    self.completion_queue = cygrpc.CompletionQueue()

  def next(self, deadline=float('+inf')):
    # 这里从 queue 的 poll 中获得一个 event，就是这里了
    raw_event = self.completion_queue.poll(cygrpc.Timespec(deadline))
{% endhighlight %}

{:.center}
grpc/_adapter/_low.py

终于，可以直接看 CompletionQueue 的 C Core 代码了。可见上面代码中的 *next* 函数是非常重要的，而这个 *next* 函数直接进入到 cython 中了，所以需要继续挖进去。

{% highlight python %}
cdef class CompletionQueue:

  def __cinit__(self):
    # 创建一个 completion_queue
    self.c_completion_queue = grpc_completion_queue_create(NULL)
    self.is_shutting_down = False
    self.is_shutdown = False
    self.pluck_condition = threading.Condition()
    self.num_plucking = 0
    self.num_polling = 0

  cdef _interpret_event(self, grpc_event event):
    # 检查 event 类型
    cdef OperationTag tag = None
    cdef object user_tag = None
    cdef Call operation_call = None
    cdef CallDetails request_call_details = None
    cdef Metadata request_metadata = None
    cdef Operations batch_operations = None
    # 如果 event 是 Timeout 和 Shutdown
    if event.type == GRPC_QUEUE_TIMEOUT:
      return Event(
          event.type, False, None, None, None, None, False, None)
    # codes ...

  def poll(self, Timespec deadline=None):
    # check codes
    with self.pluck_condition:
      assert self.num_plucking == 0, 'cannot simultaneously pluck and poll'
      self.num_polling += 1
    with nogil:
      # 从这里可以看到获取队列的下一个元素
      event = grpc_completion_queue_next(
          self.c_completion_queue, c_deadline, NULL)
    with self.pluck_condition:
      self.num_polling -= 1
    return self._interpret_event(event)

  def shutdown(self):
    grpc_completion_queue_shutdown(self.c_completion_queue)
    self.is_shutting_down = True

  def clear(self):
    if not self.is_shutting_down:
      raise ValueError('queue must be shutting down to be cleared')
    while self.poll().type != GRPC_QUEUE_SHUTDOWN:
      pass
{% endhighlight %}

{:.center}
grpc/_cython/_cygrpc/completion_queue.pyx.pxi

### CompletionQueue 数据结构

在创建 CompletionQueue 之前，需要了解 CompletionQueue C 的结构。

{% highlight c %}
struct grpc_completion_queue {
  /** owned by pollset */
  gpr_mu *mu;
  /** completed events */
  grpc_cq_completion completed_head;
  grpc_cq_completion *completed_tail;
  /** Number of pending events (+1 if we're not shutdown) */
  gpr_refcount pending_events;
  /** Once owning_refs drops to zero, we will destroy the cq */
  gpr_refcount owning_refs;
  /** 0 initially, 1 once we've begun shutting down */
  int shutdown;
  int shutdown_called;
  int is_server_cq;
  int num_pluckers;
  plucker pluckers[GRPC_MAX_COMPLETION_QUEUE_PLUCKERS];
  grpc_closure pollset_shutdown_done;

#ifndef NDEBUG
  void **outstanding_tags;
  size_t outstanding_tag_count;
  size_t outstanding_tag_capacity;
#endif

  grpc_completion_queue *next_free;
};
{% endhighlight %}

{:.center}
src/core/surface/completion_queue.c

其中还有 *grpc_cq_completion*，是队列中的每一个元素。

{% highlight c %}
typedef struct grpc_cq_completion {
  /** user supplied tag */
  void *tag;
  /** done callback - called when this queue element is no longer
      needed by the completion queue */
  void (*done)(grpc_exec_ctx *exec_ctx, void *done_arg,
               struct grpc_cq_completion *c);
  void *done_arg;
  /** next pointer; low bit is used to indicate success or not */
  uintptr_t next;
} grpc_cq_completion;
{% endhighlight %}

{:.center}
src/core/surface/completion_queue.h

注意，每一个 *grpc_cq_completion* 都包含一个函数指针，done，还有一个 done_arg 指针。所以每个 *grpc_cq_completion* 都可以调用自己的 done 方法。

### 创建 CompletionQueue

创建 CompletionQueue 的 C 代码如下。

{% highlight c %}
grpc_completion_queue *grpc_completion_queue_create(void *reserved) {
  // 初始化 completion queue
  grpc_completion_queue *cc;
  GPR_ASSERT(!reserved);

  gpr_mu_lock(&g_freelist_mu);
  if (g_freelist == NULL) {
    gpr_mu_unlock(&g_freelist_mu);

    cc = gpr_malloc(sizeof(grpc_completion_queue) + grpc_pollset_size());
    grpc_pollset_init(POLLSET_FROM_CQ(cc), &cc->mu);
#ifndef NDEBUG
    cc->outstanding_tags = NULL;
    cc->outstanding_tag_capacity = 0;
#endif
  } else {
    cc = g_freelist;
    g_freelist = g_freelist->next_free;
    gpr_mu_unlock(&g_freelist_mu);
  }

  gpr_ref_init(&cc->pending_events, 1);
  // 初始化 complete queue 成员
  gpr_ref_init(&cc->owning_refs, 2);
  cc->completed_tail = &cc->completed_head;
  cc->completed_head.next = (uintptr_t)cc->completed_tail;
  cc->shutdown = 0;
  cc->shutdown_called = 0;
  cc->is_server_cq = 0;
  cc->num_pluckers = 0;
#ifndef NDEBUG
  cc->outstanding_tag_count = 0;
#endif
  grpc_closure_init(&cc->pollset_shutdown_done, on_pollset_shutdown_done, cc);

  GPR_TIMER_END("grpc_completion_queue_create", 0);

  return cc;
}
{% endhighlight %}

{:.center}
src/core/surface/completion_queue.c

CompletionQueue 中还有一些重要的方法，一个一个来看。

### CompletionQueue Poll

了解了 CompletionQueue 对象之后，再回顾代码来看，可见一直在通过 Queue 在获取 Event 。这个时候 *grpc_completion_queue_next* 的代码是很核心的。

{% highlight c %}
grpc_event grpc_completion_queue_next(grpc_completion_queue *cc,
                                      gpr_timespec deadline, void *reserved) {
  grpc_event ret;
  grpc_pollset_worker *worker = NULL;
  int first_loop = 1;
  gpr_timespec now;
  deadline = gpr_convert_clock_type(deadline, GPR_CLOCK_MONOTONIC);

  // for 循环获得 completion queue 下一个元素
  gpr_mu_lock(cc->mu);
  for (;;) {
    // 如果没有结束
    if (cc->completed_tail != &cc->completed_head) {
      grpc_cq_completion *c = (grpc_cq_completion *)cc->completed_head.next;
      cc->completed_head.next = c->next & ~(uintptr_t)1;
      if (c == cc->completed_tail) {
        cc->completed_tail = &cc->completed_head;
      }
      gpr_mu_unlock(cc->mu);
      ret.type = GRPC_OP_COMPLETE;
      ret.success = c->next & 1u;
      ret.tag = c->tag;
      // 调用 cq completion 的 done 方法
      c->done(&exec_ctx, c->done_arg, c);
      break;
    }
    // shutdown 的情况
    if (cc->shutdown) {
      gpr_mu_unlock(cc->mu);
      memset(&ret, 0, sizeof(ret));
      ret.type = GRPC_QUEUE_SHUTDOWN;
      break;
    }
    // timeout 的情况
    now = gpr_now(GPR_CLOCK_MONOTONIC);
    if (!first_loop && gpr_time_cmp(now, deadline) >= 0) {
      gpr_mu_unlock(cc->mu);
      memset(&ret, 0, sizeof(ret));
      ret.type = GRPC_QUEUE_TIMEOUT;
      break;
    }
  }
{% endhighlight %}

{:.center}
src/core/surface/completion_queue.c

所以可以看出，CompletionQueue 是在一直等待并获取一个元素。关键问题来了，一直获取元素，如何返回给 grpcio 处理呢？其实很简单。

{% highlight python %}
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
      # 这里是一行非常重要的代码
      # 注册了 completion_queue 和 server 的线程逻辑
      # 当 complete queue 获得 event 之后
      # 会回来调用 self._spin 函数
      self._pool.submit(self._spin, self._completion_queue, self._server)
      # 仅仅开始服务
      # 队列从前面的 logging pool 创建的线程中执行
      self._server.start()
      self._server.service(None)
      self._due.add(_SERVICE)
{% endhighlight %}

{:.center}
grpc/_links/service.py

上面特别指出了是一行非常重要的代码 *_pool.submit* ，执行的函数是 self._spin。直接看看这个函数。

{% highlight python %}
  def _spin(self, completion_queue, server):
    # 在子线程中循环处理 completion queue 的 event
    while True:
      event = completion_queue.get(None)
      with self._lock:
        if event.kind is _STOP:
          self._due.remove(_STOP)
        elif event.kind is _READ:
          self._on_read_event(event)
        elif event.kind is _WRITE:
          self._on_write_event(event)
        elif event.kind is _COMPLETE:
          _no_longer_due(
              _COMPLETE, self._rpc_states.get(event.tag), event.tag,
              self._rpc_states)
        elif event.kind is _intermediary_low.Event.Kind.FINISH:
          self._on_finish_event(event)
        elif event.kind is _SERVICE:
          if self._server is None:
            self._due.remove(_SERVICE)
          else:
            self._on_service_acceptance_event(event, server)
        else:
          logging.error('Illegal event! %s', (event,))

        if not self._due and not self._rpc_states:
          completion_queue.stop()
          return
{% endhighlight %}

{:.center}
grpc/_links/service.py

到现在，绕了这么多弯，终于看到 CompletionQueue 是如何处理的了，为什么不一开始就直接说调用了 *self._spin* 呢？其实深入了解也是很重要的，通过深入到 C 代码中，才能知道 event 是一个什么东西。最后再总结一下。

{:.center}
![gRPC Stack](/images/2016/grpc-completion-queue.png){:style="max-width: 600px"}

{:.center}
CompletionQueue 大致流程图

大概就是这么一个流程，所以 CompletionQueue 是一个 Server 端的处理队列。

那么数据是怎么进入到 CompletionQueue 的，就看 [gRPC C Core - Server](/posts/grpc-c-core-source-code-1/) 这篇。

### 相关文章

1. [Basic](/posts/grpc-python-bind-source-code-1/)
2. [Server](/posts/grpc-python-bind-source-code-2/)
3. [CompletionQueue](/posts/grpc-python-bind-source-code-3/)
4. [Stub](/posts/grpc-python-bind-source-code-4/)
5. [Channel and Call](/posts/grpc-python-bind-source-code-5/)
6. [TCP Server](/posts/grpc-c-core-source-code-1/)

### 有关 C Core 的笔记

1. [Notes of gRPC](https://github.com/GuoJing/book-notes/tree/master/grpc)
