---
layout:    post
title:     gRPC Python 源码浅析 - Stub
category:  blog
description: gRPC Python 源码
tags: gRPC Python Google Source Coding HTTP2 CompletionQueue
---
### Overview

Server 端相关的代码看完之后，统一的对 Server 部分有了了解，包括 Server 和 CompletionQueue。由于实用主义，不继续从内核这一块继续深入 gRPC 代码了，先从 Client 这边来看，当有了整体的印象之后，再深入 gRPC
 C 核心代码。
 
### Stub
 
gRPC 自动生成代码之后，会有 stub 代码，stub 可以简单的想象成方法和对象的一个封装，一个映射，其实本身并不做什么事情。也就是说，可以当成是序列化之后的代码级别的入口，并不是一个客户端。

假设客户端调用一个服务端的方法，以下方法就是相当于：

    stub.Touch()
    
那么就相当于在网络上有个序列化之后的调用方法（不是这个格式，只是举例说明）。

    <Ticket method="Touch" id="xxxx">

这里也可以看出，一个 Call 的调用，其实是一个 Ticket 的传输。

由于每个 stub 是根据 protobuf 生成的，所以格式也不同，所以这里就不把 stub 生成之后的代码拿出来了，直接看生成的 pb2 文件，可以知道是调用了 dynamic_stub 这个方法。

{% highlight python %}
def dynamic_stub(channel, service, cardinalities, options=None):
  effective_options = StubOptions() if options is None else options
  return _stub.dynamic_stub(
      channel._intermediary_low_channel, effective_options.host, service,
      cardinalities, effective_options.metadata_transformer,
      effective_options.request_serializers,
      effective_options.response_deserializers, effective_options.thread_pool,
      effective_options.thread_pool_size)
{% endhighlight %}

{:.center}
grpc/beta/implementations.py

这里的代码很简单，只是从更低层的 *_stub* 来创建一个 *dynamic_stub*，可见 gRPC 代码的层数还真的挺多的，这一点有点不太习惯。anyway，继续往下看。

{% highlight python %}
def dynamic_stub(
    channel, host, service, cardinalities, metadata_transformer,
    request_serializers, response_deserializers, thread_pool,
    thread_pool_size):
  # 创建一个聚合的对象
  # 这里包含 end_link 和 grpc_link
  # 同时也包含 stub 和 stub_assembly_manager
  return _assemble(
      channel, host, metadata_transformer, request_serializers,
      response_deserializers, thread_pool, thread_pool_size,
      _dynamic_stub_creator(service, cardinalities))
{% endhighlight %}

{:.center}
grpc/beta/_stub.py

从上面的代码可见 *dynamic_stub* 创建的是一个聚合的类，里面做了很多的事情。

{% highlight python %}
def _assemble(
    channel, host, metadata_transformer, request_serializers,
    response_deserializers, thread_pool, thread_pool_size, stub_creator):
  # end_link and grpc_link here
  end_link = _core_implementations.invocation_end_link()
  grpc_link = invocation.invocation_link(
      channel, host, metadata_transformer, request_serializers,
      response_deserializers)
  # add stub manager
  stub_assembly_manager = _StubAssemblyManager(
      thread_pool, thread_pool_size, end_link, grpc_link, stub_creator)
  # stub 从 stub manager up 方法返回
  stub = stub_assembly_manager.up()
  return _AutoIntermediary(
      stub_assembly_manager.up, stub_assembly_manager.down, stub)
{% endhighlight %}

{:.center}
grpc/beta/_stub.py

这个时候可以继续进入 *_AutoIntermediary* 类，发现这个类并没有做什么。但是其中的 *_up* 和 *_done* 是很有用的，这里的 *_up* 和 *_down* 分别是 *stub_assembly_manager.up* 和 *stub_assembly_manager.down*，其中的 *delegate* 参数是 stub。

{% highlight python %}
class _StubAssemblyManager(object):

  def __init__(
      self, thread_pool, thread_pool_size, end_link, grpc_link, stub_creator):
    self._thread_pool = thread_pool
    self._pool_size = thread_pool_size
    self._end_link = end_link
    self._grpc_link = grpc_link
    self._stub_creator = stub_creator
    self._own_pool = None

  def up(self):
    if self._thread_pool is None:
      self._own_pool = logging_pool.pool(
          _DEFAULT_POOL_SIZE if self._pool_size is None else self._pool_size)
      assembly_pool = self._own_pool
    else:
      assembly_pool = self._thread_pool
    self._end_link.join_link(self._grpc_link)
    self._grpc_link.join_link(self._end_link)
    # 这里和 server 类似，start link
    self._end_link.start()
    self._grpc_link.start()
    return self._stub_creator(self._end_link, assembly_pool)

  def down(self):
    self._end_link.stop(0).wait()
    self._grpc_link.stop()
    self._end_link.join_link(utilities.NULL_LINK)
    self._grpc_link.join_link(utilities.NULL_LINK)
    # 等待所有的线程结束
    if self._own_pool is not None:
      self._own_pool.shutdown(wait=True)
      self._own_pool = None
{% endhighlight %}

{:.center}
grpc/implementations/_stub.py

可见这个类最终还是回到了 link 的使用。所以还是需要回头分别看这两个 link 的作用。

1. end_link = _core_implementations.invocation_end_link
2. grpc_link = invocation.invocation_link

### end_link

end_link 代码使用了 *invocation_end_link*，代码如下。

{% highlight python %}
def invocation_end_link():
  return _end.serviceless_end_link()

{% endhighlight %}

{:.center}
grpc/framework/core/implementations.py

废话不多说。

{% highlight python %}
def serviceless_end_link():
  return _End(None)

class _End(End):

def start(self):
    with self._lock:
      if self._cycle is not None:
        raise ValueError('Tried to start a not-stopped End!')
      else:
        # 初始化一个 cycle，传入一个线程 pool
        self._cycle = _Cycle(logging_pool.pool(1))

  def stop(self, grace):
    # 结束 link
{% endhighlight %}

{:.center}
grpc/framework/core/_end.py

这里的代码里使用了 *Cycle*, Cycle 主要只是一个线程池的管理类，没有太多的意义。我们需要主要来看，base.End 的定义。

{% highlight python %}
class End(object):
  """Common type for entry-point objects on both sides of an operation."""
  __metaclass__ = abc.ABCMeta

  @abc.abstractmethod
  def start(self):
    # 开启服务
    raise NotImplementedError()

  @abc.abstractmethod
  def stop(self, grace):
    # 关闭服务
    # 只要调用了这个方法，就会拒绝来自服务端的操作请求。但是底层还会继续执行，直到超时。
    # grace
    # 一个以秒为单位参数作为 timeout
    # returns
    # 返回一个 threading.Event 告诉外部这些操作已经完全结束
    raise NotImplementedError()
{% endhighlight %}

{:.center}
grpc/framework/interfaces/base/base.py

### grpc_link

grpc_link 是更重要的部分，这部分是和 gRPC 进行调用和通信。

{% highlight python %}
def invocation_link(
    channel, host, metadata_transformer, request_serializers,
    response_deserializers):
    # 可以看出这里是比较重要的
    # channel 是用来给 link 使用的通道
    # host 是实现 RPCS 时候需要的和服务端通信的目标地址
    # metadata_transformer 一个 callable 传输 metadata
    # request_serializers 序列化 request
    # response_deserializers 反序列化 response
  return _InvocationLink(
      channel, host, metadata_transformer, request_serializers,
      response_deserializers)
{% endhighlight %}

{:.center}
grpc/_links/invocation.py

深入看 *_InvocationLink*。

{% highlight python %}
class _InvocationLink(InvocationLink):

  def __init__(
      self, channel, host, metadata_transformer, request_serializers,
      response_deserializers):
    self._relay = relay.relay(None)
    # 应该不陌生，创建一个 _kernel 对象来管理和处理调用
    self._kernel = _Kernel(
        channel, host,
        _IDENTITY if metadata_transformer is None else metadata_transformer,
        {} if request_serializers is None else request_serializers,
        {} if response_deserializers is None else response_deserializers,
        self._relay)

  def _start(self):
    self._relay.start()
    self._kernel.start()
    return self

  def _stop(self):
    self._kernel.stop()
    self._relay.stop()
{% endhighlight %}

{:.center}
grpc/_links/invocation.py

这里依旧可以到 _Kernel 的代码中去看。

{% highlight python %}
class _Kernel(object):
  def _on_write_event(self, operation_id, unused_event, rpc_state):
    # do something on write event

  def _on_read_event(self, operation_id, event, rpc_state):
    # do something on read event

  # ...
  def _invoke(
      self, operation_id, group, method, initial_metadata, payload, termination,
      timeout, allowance, options):
      # invoke
      
  def start(self):
    # 同样使用了 completion queue 并注册了线程调用执行 _spin 方法
    with self._lock:
      self._completion_queue = _intermediary_low.CompletionQueue()
      self._pool = logging_pool.pool(1)
      self._pool.submit(self._spin, self._completion_queue)

  def stop(self):
    # 结束
    with self._lock:
      if not self._rpc_states:
        self._completion_queue.stop()
      self._completion_queue = None
      pool = self._pool
    pool.shutdown(wait=True)

{% endhighlight %}

{:.center}
grpc/_links/invocation.py

到这里，就知道 grpc link 是在做什么事情了，一样通过 CompletionQueue 获取来自服务端的信息并且处理。当然，其中的 invoke 函数也非常的重要，需要在后面解释。

### _DynamicStub

看完了两个 link 的具体实现之后，再回到 Stub。在 *dynamic_stub* 方法中，通过 *_dynamic_stub_creator* 创建 stub。

{% highlight python %}
def _dynamic_stub_creator(service, cardinalities):
  def create_dynamic_stub(end_link, invocation_pool):
    return _crust_implementations.dynamic_stub(
        end_link, service, cardinalities, invocation_pool)
  return create_dynamic_stub
{% endhighlight %}

{:.center}
grpc/implementations/_stub.py

去看 *_crust_implementations.dynamic_stub* 方法。可见直接使用了 *_DynamicStub* 类。

{% highlight python %}
class _DynamicStub(face.DynamicStub):
  def __init__(self, end, group, cardinalities, pool):
    self._end = end
    self._group = group
    self._cardinalities = cardinalities
    self._pool = pool

  def __getattr__(self, attr):
    method_cardinality = self._cardinalities.get(attr)
    # 如果客户端服务端双方都不是 stream 流
    # 那么返回的就是这个对象
    # 我们也就先只看这部分代码深入了解
    if method_cardinality is cardinality.Cardinality.UNARY_UNARY:
      return _UnaryUnaryMultiCallable(self._end, self._group, attr, self._pool)
    elif method_cardinality is cardinality.Cardinality.UNARY_STREAM:
      return _UnaryStreamMultiCallable(self._end, self._group, attr, self._pool)
    elif method_cardinality is cardinality.Cardinality.STREAM_UNARY:
      return _StreamUnaryMultiCallable(self._end, self._group, attr, self._pool)
    elif method_cardinality is cardinality.Cardinality.STREAM_STREAM:
      return _StreamStreamMultiCallable(
          self._end, self._group, attr, self._pool)
    else:
      raise AttributeError('_DynamicStub object has no attribute "%s"!' % attr)
{% endhighlight %}

如何找到我们的类型？还是从外面的代码找到线索。

{% highlight python %}
channel = implementations.insecure_channel(self.host, self.port)
stub = jedi_pb2.beta_create_JediService_stub(channel)
import pdb
pdb.set_trace()
# 在这里设置断点来找
stub.SayHello()
{% endhighlight %}

{:.center}
sample.py

如果设置断点，就会发现进入了 *grpc/beta/_stub.py* 的 *__getattr__* 方法。最后发现是一个 *_UnaryUnaryMultiCallable* 类型。

只看 *_UnaryUnaryMultiCallable* 的话，找到这个类就知道在做什么了。

{% highlight python %}
class _UnaryUnaryMultiCallable(face.UnaryUnaryMultiCallable):

  def __init__(self, end, group, method, pool):
    self._end = end
    self._group = group
    self._method = method
    self._pool = pool

  def __call__(
      self, request, timeout, metadata=None, with_call=False,
      protocol_options=None):
    # 嗯。。。还要继续看下去。。。
    return _calls.blocking_unary_unary(
        self._end, self._group, self._method, timeout, with_call,
        protocol_options, metadata, request)
{% endhighlight %}

{:.center}
grpc/framework/crust/implementations.py

{% highlight python %}
def blocking_unary_unary(
    end, group, method, timeout, with_call, protocol_options, initial_metadata,
    payload):
  rendezvous, unused_operation_context, unused_outcome = _invoke(
      end, group, method, timeout, protocol_options, initial_metadata, payload,
      True)
  if with_call:
    return next(rendezvous), rendezvous
  else:
    return next(rendezvous)
{% endhighlight %}

{:.center}
grpc/framework/crust/_calls.py

终于，找到了最重要的代码。

{% highlight python %}
def _invoke(
    end, group, method, timeout, protocol_options, initial_metadata, payload,
    complete):
  rendezvous = _control.Rendezvous(None, None)
  subscription = utilities.full_subscription(
      rendezvous, _control.protocol_receiver(rendezvous))
  # 这是最重要的代码
  operation_context, operator = end.operate(
      group, method, subscription, timeout, protocol_options=protocol_options,
      initial_metadata=initial_metadata, payload=payload,
      completion=_EMPTY_COMPLETION if complete else None)
  rendezvous.set_operator_and_context(operator, operation_context)
  outcome = operation_context.add_termination_callback(rendezvous.set_outcome)
  if outcome is not None:
    rendezvous.set_outcome(outcome)
  return rendezvous, operation_context, outcome
{% endhighlight %}

{:.center}
grpc/framework/crust/_calls.py

这个函数很明显是实现了调用，其他的就不再继续具体的分析，直接看最重要的一部分，end.operate。这里的 end 是前面传进来的，gRPC 调用的深度都很深，所以再一个个往回看。

这个 end 也是从 *_UnaryUnaryMultiCallable* 传进来的。而这个 end 是来自 *_DynamicStub* 的。也就是来自 *dynamic_stub* 的。

{% highlight python %}
# 再回来看这部分代码

def _dynamic_stub_creator(service, cardinalities):
  def create_dynamic_stub(end_link, invocation_pool):
    return _crust_implementations.dynamic_stub(
        end_link, service, cardinalities, invocation_pool)
  # 创建了一个 dynamic stub creator
  # 这个 creator 在 dynamic stub 中使用
  return create_dynamic_stub

def dynamic_stub(
    channel, host, service, cardinalities, metadata_transformer,
    request_serializers, response_deserializers, thread_pool,
    thread_pool_size):
  # _dynamic_stub_creator 创建了一个 creator
  # 创建的 creator 传入到了 _StubAssemblyManager
  return _assemble(
      channel, host, metadata_transformer, request_serializers,
      response_deserializers, thread_pool, thread_pool_size,
      _dynamic_stub_creator(service, cardinalities))
{% endhighlight %}

{:.center}
grpc/beta/_stub.py

这个 end 的初始化是来自，*dynamic_stub*函数的，可以看到通过 *_assemble* 进入了 *_StubAssemblyManager*，作为最后一个参数。所以可以发现，*_StubAssemblyManager* up 的时候初始化了 *stub_creator*。也就是说，*creator* 的 *end* 就是 *end_link*。

所以回到 end 代码去看 operate 函数。

{% highlight python %}
def operate(
    self, group, method, subscription, timeout, initial_metadata=None,
    payload=None, completion=None, protocol_options=None):
    """See base.End.operate for specification."""
    operation_id = uuid.uuid4()
    with self._lock:
      if self._cycle is None or self._cycle.grace:
        raise ValueError('Can\'t operate on stopped or stopping End!')
      termination_action = self._termination_action(operation_id)
      # 实现 operate
      operation = _operation.invocation_operate(
          operation_id, group, method, subscription, timeout, protocol_options,
          initial_metadata, payload, completion, self._mate.accept_ticket,
          termination_action, self._cycle.pool)
      self._cycle.operations[operation_id] = operation
      return operation.context, operation.operator
{% endhighlight %}

{:.center}
grpc/framework/core/_end.py

继续挖下去。

{% highlight python %}
def invocation_operate(
    operation_id, group, method, subscription, timeout, protocol_options,
    initial_metadata, payload, completion, ticket_sink, termination_action,
    pool):
  # 实现各种 manager
  lock = threading.Lock()
  with lock:
    termination_manager = _termination.invocation_termination_manager(
        termination_action, pool)
    transmission_manager = _transmission.TransmissionManager(
        operation_id, ticket_sink, lock, pool, termination_manager)
    expiration_manager = _expiration.invocation_expiration_manager(
        timeout, lock, termination_manager, transmission_manager)
    protocol_manager = _protocol.invocation_protocol_manager(
        subscription, lock, pool, termination_manager, transmission_manager,
        expiration_manager)
    operation_context = _context.OperationContext(
        lock, termination_manager, transmission_manager, expiration_manager)
    emission_manager = _emission.EmissionManager(
        lock, termination_manager, transmission_manager, expiration_manager)
    ingestion_manager = _ingestion.invocation_ingestion_manager(
        subscription, lock, pool, termination_manager, transmission_manager,
        expiration_manager, protocol_manager)
    reception_manager = _reception.ReceptionManager(
        termination_manager, transmission_manager, expiration_manager,
        protocol_manager, ingestion_manager)

    termination_manager.set_expiration_manager(expiration_manager)
    transmission_manager.set_expiration_manager(expiration_manager)
    emission_manager.set_ingestion_manager(ingestion_manager)

    # KICK
    transmission_manager.kick_off(
        group, method, timeout, protocol_options, initial_metadata, payload,
        completion, None)
{% endhighlight %}

{:.center}
grpc/framework/core/_operation.py

到 KICK 函数，就是终于要从客户端传输数据到服务端了。但在这之前，还是先看看 *transmission_manager* 吧。

{% highlight python %}
def kick_off(
    self, group, method, timeout, protocol_options, initial_metadata,
    payload, completion, allowance):
    """See _interfaces.TransmissionManager.kickoff for specification."""
    # TODO(nathaniel): Support other subscriptions.
    subscription = links.Ticket.Subscription.FULL
    terminal_metadata, code, message, termination = _explode_completion(
        completion)
    self._remote_allowance = 1 if payload is None else 0
    protocol = links.Protocol(links.Protocol.Kind.CALL_OPTION, protocol_options)
    # 初始化一个 Ticket
    # Ticket 是传输中很重要的类，也是基本类
    ticket = links.Ticket(
        self._operation_id, 0, group, method, subscription, timeout, allowance,
        initial_metadata, payload, terminal_metadata, code, message,
        termination, protocol)
    self._lowest_unused_sequence_number = 1
    # 开始 transmit
    self._transmit(ticket)
{% endhighlight %}

{:.center}
grpc/framework/core/_transmission.py

可以看到 transmit 函数。

{% highlight python %}
  def _transmit(self, ticket):
    def transmit(ticket):
      while True:
        # 循环获取 outcome
        # 类似于获得数据
        transmission_outcome = callable_util.call_logging_exceptions(
            self._ticket_sink, _TRANSMISSION_EXCEPTION_LOG_MESSAGE, ticket)
        # 这里的 _ticket_sink 是外部传来的
        # 是 _InvocationLink.accept_ticket 方法
        # 相当于 _InvocationLink.accept_ticket(ticket)
        if transmission_outcome.exception is None:
          with self._lock:
            if ticket.termination is links.Ticket.Termination.COMPLETION:
              # 如果获得了 outcome 则调用 complete 方法
              self._termination_manager.transmission_complete()
            ticket = self._next_ticket()
            if ticket is None:
              self._transmitting = False
              return
        else:
          with self._lock:
            self._abort = _ABORTED_NO_NOTIFY
            if self._termination_manager.outcome is None:
              self._termination_manager.abort(_TRANSMISSION_FAILURE_OUTCOME)
              self._expiration_manager.terminate()
            return
    # 创建一个新线程来处理
    self._pool.submit(callable_util.with_exceptions_logged(
        transmit, _constants.INTERNAL_ERROR_LOG_MESSAGE), ticket)
    self._transmitting = True
{% endhighlight %}

{:.center}
grpc/framework/core/_transmission.py

这里代码写的比较隐晦，首先，subumit 创建了一个新线程。*callable_utils.with_exceptions_logged* 加上参数 transmit 以及 LOG MESSAGE 之后，实际上是创建了一个调用的方法。也就是说这个函数创建了一个方法，然后这个方法和方法的参数 ticket 放入新的线程去处理。最后走到了前面说的 *grpc_link* 中。

{% highlight python %}
def accept_ticket(self, ticket):
    """See links.Link.accept_ticket for specification."""
    self._kernel.add_ticket(ticket)
{% endhighlight %}

{:.center}
grpc/_links/_transmission.py

再看 *_kernel.add_ticket*。

{% highlight python %}
  def add_ticket(self, ticket):
    with self._lock:
      if ticket.sequence_number == 0:
        if self._completion_queue is None:
          logging.error('Received invocation ticket %s after stop!', ticket)
        else:
          if (ticket.protocol is not None and
              ticket.protocol.kind is links.Protocol.Kind.CALL_OPTION):
            grpc_call_options = ticket.protocol.value
          else:
            grpc_call_options = None
          # 又回到了很重要的 _invoke 函数
          self._invoke(
              ticket.operation_id, ticket.group, ticket.method,
              ticket.initial_metadata, ticket.payload, ticket.termination,
              ticket.timeout, ticket.allowance, grpc_call_options)
      else:
        rpc_state = self._rpc_states.get(ticket.operation_id)
        if rpc_state is not None:
          self._advance(
              ticket.operation_id, rpc_state, ticket.payload,
              ticket.termination, ticket.allowance)
{% endhighlight %}

{% highlight python %}
class _Kernel(object):
  def _on_write_event(self, operation_id, unused_event, rpc_state):
    # do something on write event

  def _on_read_event(self, operation_id, event, rpc_state):
    # do something on read event

  # ...
  def _invoke(
      self, operation_id, group, method, initial_metadata, payload, termination,
      timeout, allowance, options):
      # 现在可以来看看 invoke 实现了什么
      # 创建了一个底层的 Call 对象
      call = _intermediary_low.Call(
        self._channel, self._completion_queue, '/%s/%s' % (group, method),
        self._host, time.time() + timeout)
      if options is not None and options.credentials is not None:
          call.set_credentials(options.credentials._low_credentials)
      if transformed_initial_metadata is not None:
          for metadata_key, metadata_value in transformed_initial_metadata:
              call.add_metadata(metadata_key, metadata_value)
      call.invoke(self._completion_queue, operation_id, operation_id)
{% endhighlight %}

{:.center}
grpc/_links/invocation.py

### 创建 Call 对象

直接走到 _low 代码来看。

{% highlight python %}
class Call(object):

  def __init__(self, channel, completion_queue, method, host, deadline):
    # 到这里基本上就真相大白了
    # Call 使用了 channel 的 _internal 的 create_call 方法
    # 也就是 cython 中 channel.pxd.pxi 的 create_call 方法
    self._internal = channel._internal.create_call(
        completion_queue._internal, method, host, deadline)
    self._metadata = []
{% endhighlight %}

{:.center}
grpc/_adapter/_intermediary_low.py

{% highlight python %}
  def create_call(self, Call parent, int flags,
                  CompletionQueue queue not None,
                  method, host, Timespec deadline not None):
    if queue.is_shutting_down:
      raise ValueError("queue must not be shutting down or shutdown")
    if isinstance(method, bytes):
      pass
    elif isinstance(method, basestring):
      method = method.encode()
    else:
      raise TypeError("expected method to be str or bytes")
    cdef char *host_c_string = NULL
    if host is None:
      pass
    elif isinstance(host, bytes):
      host_c_string = host
    elif isinstance(host, basestring):
      host = host.encode()
      host_c_string = host
    else:
      raise TypeError("expected host to be str, bytes, or None")
    cdef Call operation_call = Call()
    operation_call.references = [self, method, host, queue]
    cdef grpc_call *parent_call = NULL
    if parent is not None:
      parent_call = parent.c_call
    # 真正调用 grpc c core 的地方
    operation_call.c_call = grpc_channel_create_call(
        self.c_channel, parent_call, flags,
        queue.c_completion_queue, method, host_c_string, deadline.c_time,
        NULL)
    return operation_call
{% endhighlight %}

{:.center}
grpc/_cython/channel.pyx.pxi

走过千山万水，终于找到调用 gRPC C Core 的地方。

{% highlight c %}
grpc_call *grpc_channel_create_call(grpc_channel *channel,
                                    grpc_call *parent_call,
                                    uint32_t propagation_mask,
                                    grpc_completion_queue *cq,
                                    const char *method, const char *host,
                                    gpr_timespec deadline, void *reserved) {
  // 还是继续深入调用其他函数中。。。
  return grpc_channel_create_call_internal(
      channel, parent_call, propagation_mask, cq,
      grpc_mdelem_from_metadata_strings(GRPC_MDSTR_PATH,
                                        grpc_mdstr_from_string(method)),
      host ? grpc_mdelem_from_metadata_strings(GRPC_MDSTR_AUTHORITY,
                                               grpc_mdstr_from_string(host))
           : NULL,
      deadline);
}
{% endhighlight %}

{:.center}
src/core/surface/channel.c

gRPC 代码可真够深的。

{% highlight c %}
static grpc_call *grpc_channel_create_call_internal(
    grpc_channel *channel, grpc_call *parent_call, uint32_t propagation_mask,
    grpc_completion_queue *cq, grpc_mdelem *path_mdelem,
    grpc_mdelem *authority_mdelem, gpr_timespec deadline) {
  grpc_mdelem *send_metadata[2];
  size_t num_metadata = 0;

  GPR_ASSERT(channel->is_client);

  send_metadata[num_metadata++] = path_mdelem;
  if (authority_mdelem != NULL) {
    send_metadata[num_metadata++] = authority_mdelem;
  } else if (channel->default_authority != NULL) {
    send_metadata[num_metadata++] = GRPC_MDELEM_REF(channel->default_authority);
  }
  // 走到这里了
  return grpc_call_create(channel, parent_call, propagation_mask, cq, NULL,
                          send_metadata, num_metadata, deadline);
}
{% endhighlight %}

{:.center}
src/core/surface/channel.c

*grpc_call_create* 函数来自 Call 代码。

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
  grpc_call_stack_init(&exec_ctx, channel_stack, 1, destroy_call, call,
                       call->context, server_transport_data,
                       CALL_STACK_FROM_CALL(call));
  if (cq != NULL) {
    // cq 不为空
    grpc_call_stack_set_pollset(&exec_ctx, CALL_STACK_FROM_CALL(call),
                                grpc_cq_pollset(cq));
  }
  if (parent_call != NULL) {
    // do something ...
}
  if (gpr_time_cmp(send_deadline, gpr_inf_future(send_deadline.clock_type)) !=
      0) {
    set_deadline_alarm(&exec_ctx, call, send_deadline);
  }
  grpc_exec_ctx_finish(&exec_ctx);
  GPR_TIMER_END("grpc_call_create", 0);
  return call;
}
{% endhighlight %}

{:.center}
src/core/surface/call.c

可以看见一个 Call 注册了一个 CompletionQueue，并把自己的 cq (CompletionQueue) 成员设置为 CompletionQueue。在今后的执行就能知道是从哪个 CompletionQueue 来，回到哪个 CompletionQueue。其中 *grpc_call_stack_set_pollset* 相当于执行了将 call data 写入到 pollset。

{% highlight c %}
void grpc_call_stack_set_pollset(grpc_exec_ctx *exec_ctx,
                                 grpc_call_stack *call_stack,
                                 grpc_pollset *pollset) {
  size_t count = call_stack->count;
  grpc_call_element *call_elems;
  char *user_data;
  size_t i;

  call_elems = CALL_ELEMS_FROM_STACK(call_stack);
  user_data = ((char *)call_elems) +
              ROUND_UP_TO_ALIGNMENT_SIZE(count * sizeof(grpc_call_element));

  /* init per-filter data */
  for (i = 0; i < count; i++) {
    // 每一个 call element 的 filter 设置 cq 的 pollset
    // call element filter 等于是 grpc_channel_filter
    // set_pollset 是用来初始化每个 call data 的
    call_elems[i].filter->set_pollset(exec_ctx, &call_elems[i], pollset);
    user_data +=
        ROUND_UP_TO_ALIGNMENT_SIZE(call_elems[i].filter->sizeof_call_data);
  }
}
{% endhighlight %}

{:.center}
src/core/channel/channel_stack.c

### Call method

到此为止，创建了一个 Call 对象。并且知道了最终代码会走到 *invocation.py* 的 *_invoke* 的方法，现在再回头看这个方法。

{% highlight python %}
def _invoke(
      self, operation_id, group, method, initial_metadata, payload, termination,
      timeout, allowance, options):
    if termination is links.Ticket.Termination.COMPLETION:
      high_write = _HighWrite.CLOSED
    elif termination is None:
      high_write = _HighWrite.OPEN
    else:
      return

    transformed_initial_metadata = self._metadata_transformer(initial_metadata)
    request_serializer = self._request_serializers.get(
        (group, method), _IDENTITY)
    response_deserializer = self._response_deserializers.get(
        (group, method), _IDENTITY)
    # 创建一个 call 对象
    call = _intermediary_low.Call(
        self._channel, self._completion_queue, '/%s/%s' % (group, method),
        self._host, time.time() + timeout)
    if options is not None and options.credentials is not None:
      call.set_credentials(options.credentials._low_credentials)
    if transformed_initial_metadata is not None:
      for metadata_key, metadata_value in transformed_initial_metadata:
        call.add_metadata(metadata_key, metadata_value)
    # 实现 call invoke
    call.invoke(self._completion_queue, operation_id, operation_id)
    # 如果 payload 为空
    if payload is None:
      if high_write is _HighWrite.CLOSED:
        # call 结束
        call.complete(operation_id)
        low_write = _LowWrite.CLOSED
        due = set((_METADATA, _COMPLETE, _FINISH,))
      else:
        low_write = _LowWrite.OPEN
        due = set((_METADATA, _FINISH,))
    else:
      if options is not None and options.disable_compression:
        flags = _intermediary_low.WriteFlags.WRITE_NO_COMPRESS
      else:
        flags = 0
      # call 写入, 使用 request 序列化方法来写入 payload
      call.write(request_serializer(payload), operation_id, flags)
      low_write = _LowWrite.ACTIVE
      due = set((_WRITE, _METADATA, _FINISH,))
    context = _Context()
    # rpc 请求
    self._rpc_states[operation_id] = _RPCState(
        call, request_serializer, response_deserializer, 1,
        _Read.AWAITING_METADATA, 1 if allowance is None else (1 + allowance),
        high_write, low_write, due, context)
    protocol = links.Protocol(links.Protocol.Kind.INVOCATION_CONTEXT, context)
    ticket = links.Ticket(
        operation_id, 0, None, None, None, None, None, None, None, None, None,
        None, None, protocol)
    self._relay.add_value(ticket)
{% endhighlight %}

{:.center}
grpc/_links/invocation.py

这里 call.invoke 方法和 call.write 方法如下所示。

{% highlight python %}
class Call(object):
  """Adapter from old _low.Call interface to new _low.Call."""

  def __init__(self, channel, completion_queue, method, host, deadline):
    self._internal = channel._internal.create_call(
        completion_queue._internal, method, host, deadline)
    self._metadata = []

  @staticmethod
  def _from_internal(internal):
    call = Call.__new__(Call)
    call._internal = internal
    call._metadata = []
    return call

  def invoke(self, completion_queue, metadata_tag, finish_tag):
    err = self._internal.start_batch([
          _types.OpArgs.send_initial_metadata(self._metadata)
      ], _IGNORE_ME_TAG)
    if err != _types.CallError.OK:
      return err
    err = self._internal.start_batch([
          _types.OpArgs.recv_initial_metadata()
      ], _TagAdapter(metadata_tag, Event.Kind.METADATA_ACCEPTED))
    if err != _types.CallError.OK:
      return err
    err = self._internal.start_batch([
          _types.OpArgs.recv_status_on_client()
      ], _TagAdapter(finish_tag, Event.Kind.FINISH))
    return err

  def write(self, message, tag, flags):
    return self._internal.start_batch([
          _types.OpArgs.send_message(message, flags)
      ], _TagAdapter(tag, Event.Kind.WRITE_ACCEPTED))

  def complete(self, tag):
    return self._internal.start_batch([
          _types.OpArgs.send_close_from_client()
      ], _TagAdapter(tag, Event.Kind.COMPLETE_ACCEPTED))

  def accept(self, completion_queue, tag):
    return self._internal.start_batch([
          _types.OpArgs.recv_close_on_server()
      ], _TagAdapter(tag, Event.Kind.FINISH))
{% endhighlight %}

{:.center}
grpc/_adapter/_intermediary_low.py

而其中的 *_internal* 如下。

{% highlight python %}
class Call(_types.Call):

  def __init__(self, call):
    self.call = call

  def start_batch(self, ops, tag):
    translated_ops = []
    for op in ops:
      if op.type == _types.OpType.SEND_INITIAL_METADATA:
        translated_op = cygrpc.operation_send_initial_metadata(
            cygrpc.Metadata(
                cygrpc.Metadatum(key, value)
                for key, value in op.initial_metadata))
      elif op.type == _types.OpType.SEND_MESSAGE:
        translated_op = cygrpc.operation_send_message(op.message)
      elif op.type == _types.OpType.SEND_CLOSE_FROM_CLIENT:
        translated_op = cygrpc.operation_send_close_from_client()
      elif op.type == _types.OpType.SEND_STATUS_FROM_SERVER:
        translated_op = cygrpc.operation_send_status_from_server(
            cygrpc.Metadata(
                cygrpc.Metadatum(key, value)
                for key, value in op.trailing_metadata),
            op.status.code,
            op.status.details)
      elif op.type == _types.OpType.RECV_INITIAL_METADATA:
        translated_op = cygrpc.operation_receive_initial_metadata()
      elif op.type == _types.OpType.RECV_MESSAGE:
        translated_op = cygrpc.operation_receive_message()
      elif op.type == _types.OpType.RECV_STATUS_ON_CLIENT:
        translated_op = cygrpc.operation_receive_status_on_client()
      elif op.type == _types.OpType.RECV_CLOSE_ON_SERVER:
        translated_op = cygrpc.operation_receive_close_on_server()
      else:
        raise ValueError('unexpected operation type {}'.format(op.type))
      translated_ops.append(translated_op)
    # 调用 c core 里 call 的代码 start_batch 进行 rpc 请求
    return self.call.start_batch(cygrpc.Operations(translated_ops), tag)
{% endhighlight %}

{:.center}
grpc/_adapter/_low.py

而代码中的 start_batch 则是调用了 _low.Call 的 start_batch，这里就走入到 cygrpc 中了。

现在可以看出 call.write 最后就调用了 *operation_send_message*。

{% highlight python %}
def operation_send_message(data):
  cdef Operation op = Operation()
  op.c_op.type = GRPC_OP_SEND_MESSAGE
  byte_buffer = ByteBuffer(data)
  # send message
  op.c_op.data.send_message = byte_buffer.c_byte_buffer
  op.references.append(byte_buffer)
  op.is_valid = True
  return op
{% endhighlight %}

{:.center}
grpc/_cython/records.pyx.pxi

处理完成后，批量的进行处理，执行 *self.call.start_batch(cygrpc.Operations(translated_ops), tag)* 方法。

{% highlight python %}
cdef class Call:

  def __cinit__(self):
    # Create an *empty* call
    self.c_call = NULL
    self.references = []

  def start_batch(self, operations, tag):
    if not self.is_valid:
      raise ValueError("invalid call object cannot be used from Python")
    cdef Operations cy_operations = Operations(operations)
    cdef OperationTag operation_tag = OperationTag(tag)
    operation_tag.operation_call = self
    operation_tag.batch_operations = cy_operations
    cpython.Py_INCREF(operation_tag)
    # 调用 grpc_call_start_batch
    return grpc_call_start_batch(
        self.c_call, cy_operations.c_ops, cy_operations.c_nops,
        <cpython.PyObject *>operation_tag, NULL)
{% endhighlight %}

{:.center}
grpc/_cython/_cygrpc/call.pyx.pxi


终于。

{% highlight c %}
grpc_call_error grpc_call_start_batch(grpc_call *call, const grpc_op *ops,
                                      size_t nops, void *tag, void *reserved) {
  grpc_exec_ctx exec_ctx = GRPC_EXEC_CTX_INIT;
  grpc_call_error err;

  GRPC_API_TRACE(
      "grpc_call_start_batch(call=%p, ops=%p, nops=%lu, tag=%p, reserved=%p)",
      5, (call, ops, (unsigned long)nops, tag, reserved));

  if (reserved != NULL) {
    err = GRPC_CALL_ERROR;
  } else {
    err = call_start_batch(&exec_ctx, call, ops, nops, tag, 0);
  }

  grpc_exec_ctx_finish(&exec_ctx);
  return err;
}
{% endhighlight %}

调用了 *call_start_batch*，代码如下。

{% highlight c %}
static grpc_call_error call_start_batch(grpc_exec_ctx *exec_ctx,
                                        grpc_call *call, const grpc_op *ops,
                                        size_t nops, void *notify_tag,
                                        int is_notify_tag_closure) {
  grpc_transport_stream_op stream_op;
  size_t i;
  const grpc_op *op;
  batch_control *bctl;
  int num_completion_callbacks_needed = 1;
  grpc_call_error error = GRPC_CALL_OK;

  GPR_TIMER_BEGIN("grpc_call_start_batch", 0);

  GRPC_CALL_LOG_BATCH(GPR_INFO, call, ops, nops, notify_tag);

  memset(&stream_op, 0, sizeof(stream_op));

  /* TODO(ctiller): this feels like it could be made lock-free */
  gpr_mu_lock(&call->mu);
  bctl = allocate_batch_control(call);
  memset(bctl, 0, sizeof(*bctl));
  bctl->call = call;
  bctl->notify_tag = notify_tag;
  bctl->is_notify_tag_closure = (uint8_t)(is_notify_tag_closure != 0);

  if (nops == 0) {
    GRPC_CALL_INTERNAL_REF(call, "completion");
    bctl->success = 1;
    if (!is_notify_tag_closure) {
      grpc_cq_begin_op(call->cq, notify_tag);
    }
    gpr_mu_unlock(&call->mu);
    post_batch_completion(exec_ctx, bctl);
    error = GRPC_CALL_OK;
    goto done;
  }

  /* rewrite batch ops into a transport op */
  for (i = 0; i < nops; i++) {
    op = &ops[i];
    if (op->reserved != NULL) {
      error = GRPC_CALL_ERROR;
      goto done_with_error;
    }
    switch (op->op) {
      case GRPC_OP_SEND_INITIAL_METADATA:
        /* Flag validation: currently allow no flags */
        if (op->flags != 0) {
          error = GRPC_CALL_ERROR_INVALID_FLAGS;
          goto done_with_error;
        }
        if (call->sent_initial_metadata) {
          error = GRPC_CALL_ERROR_TOO_MANY_OPERATIONS;
          goto done_with_error;
        }
        if (op->data.send_initial_metadata.count > INT_MAX) {
          error = GRPC_CALL_ERROR_INVALID_METADATA;
          goto done_with_error;
        }
        bctl->send_initial_metadata = 1;
        call->sent_initial_metadata = 1;
        if (!prepare_application_metadata(
                call, (int)op->data.send_initial_metadata.count,
                op->data.send_initial_metadata.metadata, 0, call->is_client)) {
          error = GRPC_CALL_ERROR_INVALID_METADATA;
          goto done_with_error;
        }
        /* TODO(ctiller): just make these the same variable? */
        call->metadata_batch[0][0].deadline = call->send_deadline;
        stream_op.send_initial_metadata =
            &call->metadata_batch[0 /* is_receiving */][0 /* is_trailing */];
        break;
      case GRPC_OP_SEND_MESSAGE:
        if (!are_write_flags_valid(op->flags)) {
          error = GRPC_CALL_ERROR_INVALID_FLAGS;
          goto done_with_error;
        }
        if (op->data.send_message == NULL) {
          error = GRPC_CALL_ERROR_INVALID_MESSAGE;
          goto done_with_error;
        }
        if (call->sending_message) {
          error = GRPC_CALL_ERROR_TOO_MANY_OPERATIONS;
          goto done_with_error;
        }
        bctl->send_message = 1;
        call->sending_message = 1;
        grpc_slice_buffer_stream_init(
            &call->sending_stream,
            &op->data.send_message->data.raw.slice_buffer, op->flags);
        stream_op.send_message = &call->sending_stream.base;
        break;
      case GRPC_OP_SEND_CLOSE_FROM_CLIENT:
        /* Flag validation: currently allow no flags */
        if (op->flags != 0) {
          error = GRPC_CALL_ERROR_INVALID_FLAGS;
          goto done_with_error;
        }
        if (!call->is_client) {
          error = GRPC_CALL_ERROR_NOT_ON_SERVER;
          goto done_with_error;
        }
        if (call->sent_final_op) {
          error = GRPC_CALL_ERROR_TOO_MANY_OPERATIONS;
          goto done_with_error;
        }
        bctl->send_final_op = 1;
        call->sent_final_op = 1;
        stream_op.send_trailing_metadata =
            &call->metadata_batch[0 /* is_receiving */][1 /* is_trailing */];
        break;
      case GRPC_OP_SEND_STATUS_FROM_SERVER:
        /* Flag validation: currently allow no flags */
        if (op->flags != 0) {
          error = GRPC_CALL_ERROR_INVALID_FLAGS;
          goto done_with_error;
        }
        if (call->is_client) {
          error = GRPC_CALL_ERROR_NOT_ON_CLIENT;
          goto done_with_error;
        }
        if (call->sent_final_op) {
          error = GRPC_CALL_ERROR_TOO_MANY_OPERATIONS;
          goto done_with_error;
        }
        if (op->data.send_status_from_server.trailing_metadata_count >
            INT_MAX) {
          error = GRPC_CALL_ERROR_INVALID_METADATA;
          goto done_with_error;
        }
        bctl->send_final_op = 1;
        call->sent_final_op = 1;
        call->send_extra_metadata_count = 1;
        call->send_extra_metadata[0].md = grpc_channel_get_reffed_status_elem(
            call->channel, op->data.send_status_from_server.status);
        if (op->data.send_status_from_server.status_details != NULL) {
          call->send_extra_metadata[1].md = grpc_mdelem_from_metadata_strings(
              GRPC_MDSTR_GRPC_MESSAGE,
              grpc_mdstr_from_string(
                  op->data.send_status_from_server.status_details));
          call->send_extra_metadata_count++;
          set_status_details(
              call, STATUS_FROM_API_OVERRIDE,
              GRPC_MDSTR_REF(call->send_extra_metadata[1].md->value));
        }
        set_status_code(call, STATUS_FROM_API_OVERRIDE,
                        (uint32_t)op->data.send_status_from_server.status);
        if (!prepare_application_metadata(
                call,
                (int)op->data.send_status_from_server.trailing_metadata_count,
                op->data.send_status_from_server.trailing_metadata, 1, 1)) {
          error = GRPC_CALL_ERROR_INVALID_METADATA;
          goto done_with_error;
        }
        stream_op.send_trailing_metadata =
            &call->metadata_batch[0 /* is_receiving */][1 /* is_trailing */];
        break;
      case GRPC_OP_RECV_INITIAL_METADATA:
        /* Flag validation: currently allow no flags */
        if (op->flags != 0) {
          error = GRPC_CALL_ERROR_INVALID_FLAGS;
          goto done_with_error;
        }
        if (call->received_initial_metadata) {
          error = GRPC_CALL_ERROR_TOO_MANY_OPERATIONS;
          goto done_with_error;
        }
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
      case GRPC_OP_RECV_MESSAGE:
        /* Flag validation: currently allow no flags */
        if (op->flags != 0) {
          error = GRPC_CALL_ERROR_INVALID_FLAGS;
          goto done_with_error;
        }
        if (call->receiving_message) {
          error = GRPC_CALL_ERROR_TOO_MANY_OPERATIONS;
          goto done_with_error;
        }
        call->receiving_message = 1;
        bctl->recv_message = 1;
        call->receiving_buffer = op->data.recv_message;
        stream_op.recv_message = &call->receiving_stream;
        grpc_closure_init(&call->receiving_stream_ready, receiving_stream_ready,
                          bctl);
        stream_op.recv_message_ready = &call->receiving_stream_ready;
        num_completion_callbacks_needed++;
        break;
      case GRPC_OP_RECV_STATUS_ON_CLIENT:
        /* Flag validation: currently allow no flags */
        if (op->flags != 0) {
          error = GRPC_CALL_ERROR_INVALID_FLAGS;
          goto done_with_error;
        }
        if (!call->is_client) {
          error = GRPC_CALL_ERROR_NOT_ON_SERVER;
          goto done_with_error;
        }
        if (call->received_final_op) {
          error = GRPC_CALL_ERROR_TOO_MANY_OPERATIONS;
          goto done_with_error;
        }
        call->received_final_op = 1;
        call->buffered_metadata[1] =
            op->data.recv_status_on_client.trailing_metadata;
        call->final_op.client.status = op->data.recv_status_on_client.status;
        call->final_op.client.status_details =
            op->data.recv_status_on_client.status_details;
        call->final_op.client.status_details_capacity =
            op->data.recv_status_on_client.status_details_capacity;
        bctl->recv_final_op = 1;
        stream_op.recv_trailing_metadata =
            &call->metadata_batch[1 /* is_receiving */][1 /* is_trailing */];
        break;
      case GRPC_OP_RECV_CLOSE_ON_SERVER:
        /* Flag validation: currently allow no flags */
        if (op->flags != 0) {
          error = GRPC_CALL_ERROR_INVALID_FLAGS;
          goto done_with_error;
        }
        if (call->is_client) {
          error = GRPC_CALL_ERROR_NOT_ON_CLIENT;
          goto done_with_error;
        }
        if (call->received_final_op) {
          error = GRPC_CALL_ERROR_TOO_MANY_OPERATIONS;
          goto done_with_error;
        }
        call->received_final_op = 1;
        call->final_op.server.cancelled =
            op->data.recv_close_on_server.cancelled;
        bctl->recv_final_op = 1;
        stream_op.recv_trailing_metadata =
            &call->metadata_batch[1 /* is_receiving */][1 /* is_trailing */];
        break;
    }
  }

  GRPC_CALL_INTERNAL_REF(call, "completion");
  if (!is_notify_tag_closure) {
    grpc_cq_begin_op(call->cq, notify_tag);
  }
  gpr_ref_init(&bctl->steps_to_complete, num_completion_callbacks_needed);

  stream_op.context = call->context;
  grpc_closure_init(&bctl->finish_batch, finish_batch, bctl);
  stream_op.on_complete = &bctl->finish_batch;
  gpr_mu_unlock(&call->mu);

  execute_op(exec_ctx, call, &stream_op);

done:
  GPR_TIMER_END("grpc_call_start_batch", 0);
  return error;

done_with_error:
  /* reverse any mutations that occured */
  if (bctl->send_initial_metadata) {
    call->sent_initial_metadata = 0;
    grpc_metadata_batch_clear(&call->metadata_batch[0][0]);
  }
  if (bctl->send_message) {
    call->sending_message = 0;
    grpc_byte_stream_destroy(exec_ctx, &call->sending_stream.base);
  }
  if (bctl->send_final_op) {
    call->sent_final_op = 0;
    grpc_metadata_batch_clear(&call->metadata_batch[0][1]);
  }
  if (bctl->recv_initial_metadata) {
    call->received_initial_metadata = 0;
  }
  if (bctl->recv_message) {
    call->receiving_message = 0;
  }
  if (bctl->recv_final_op) {
    call->received_final_op = 0;
  }
  gpr_mu_unlock(&call->mu);
  goto done;
}
{% endhighlight %}

{:.center}
src/core/sureface/call.c

中间就是巨大的 switch，最后都会走到 execute_op。

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
src/core/sureface/call.c

最后，到达了 *start_transport_stream_op*。

暂时，可以当做在这里进行了传输，接下来具体分析是如何实现传输的，但在这之前，还需要了解 Channel Stack 和 Call Stack。以及 Channel 的创建流程。

### 相关文章

1. [Basic](/posts/grpc-python-bind-source-code-1/)
2. [Server](/posts/grpc-python-bind-source-code-2/)
3. [CompletionQueue](/posts/grpc-python-bind-source-code-3/)
4. [Stub](/posts/grpc-python-bind-source-code-4/)
5. [Channel](/posts/grpc-python-bind-source-code-5/)

### 有关 C Core 的笔记

1. [Notes of gRPC](https://github.com/GuoJing/book-notes/tree/master/grpc)

