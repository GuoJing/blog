---
layout:    post
title:     gRPC Python 源码浅析 - Basic
category:  blog
description: gRPC Python 源码
tags: gRPC Python Google Source Coding HTTP2
---
### Overview

此部分代码的基于 git log **3a4b903bf0554051d4a6523d3d252773c1c80495** 分析。

最近在新公司的新项目需要进行一些服务化的开发，在服务化的过程中遇到了一些问题，也解决了一些问题。在这其中，项目的选型是使用了 gRPC。gRPC 是一个高性能的 rpc 框架，由 Google 开发。在这里记录下我使用 gRPC 得到的收益和遇到的问题。

早期在做服务化选型的时候，我们其实有多种考虑，大概有这几种想法。

1. HTTP
2. Thrift
3. gRPC

### Which one?

早期规划的时候，HTTP 是我们最优先考虑的协议。只是，在考虑大量内部调用的时候，特别是彼此调用特别多的情况下，怕有性能问题，请求过多 HTTP 本身会有握手的性能开销，相比之下，更希望服务能做到在 TCP 这一层，能减少开销就减少开销。所以后来考虑使用 Thrift。

相比之下 Thrift 的性能相当强悍，毕竟直接是 raw socket。但直接做网络开发，对开发要求会比 HTTP 要更高，TCP 需要开发能够考虑连接情况，合适的时候创建和断开，如果过于随意，有可能导致连接维护困难，在这一点上 HTTP 本身使用起来相当简单。移动端上使用相比 HTTP，需要解决更多的问题。

其实早期 gRPC 并不是我的首选，第一是这个项目国内并没有多少人趟这个坑，所以怕没有同行可以交流经验，第二是 Google 虽然内部使用了大量的 gRPC 作为内部通信，但开源出来的时间并不久，这里面还打包了 Protobuf。

不过考虑到有 Google 背书，我个人还是比较喜欢这个选型的。虽然略微激进，但我个人还是很激动的。gRPC 基于 HTTP2，性能比 HTTP 好很多，几乎有一倍的提升，传输层上面不是 text 这样的文本，而是 binary。HTTP Header 默认压缩，可以减少数据量。

除此之外，HTTP2 还是服务和客户端双向通道，天然的可以做一些推送的事情，移动端开发更有优势，Google 本身在 gRPC 项目中也提到一大部分情况也是为了移动端开发所准备的。

不仅如此，gRPC 还可以双向使用流的形式收发信息，对大文件大文本的业务有不错的支持。

### HTTP2

gRPC 基于 HTTP2，所以需要先了解 HTTP2 的特性。HTTP2 可以直接看相关的 RCF，下面是几个链接，相关的重点我会重点介绍。

1. [HTML](http://http2.github.io/http2-spec/index.html)
2. [TEXT](http://http2.github.io/http2-spec/index.txt)
3. [ALNP RCF](http://http2.github.io/http2-spec/index.txt)

HTTP2 相比 HTTP1/1.1 有很多的改进，最主要的几个点在。

1. 二进制分帧
2. 首部压缩
3. 多路复用
4. 请求优先级
5. 服务器推送

每个稍微解释一下的话就是：

1. 使用 binary 进行传输，HTTP2 会将消息分成更小的 frame，使用二进制编码格式，header 封装到 HEADER frame 里，body 封装到 DATA frame，通信在一个连接中完成。双向传输
2. 封装成 frame 之后可以对首部进行压缩，减少数据传输量，例如 Cookie 等信息
3. 多路复用允许单一的通道发起多次请求，而且是可以双向传输
4. 可以给每个请求设置优先级，请求之间是可以有顺序和关系的
5. 因为双向传输，服务器可以向客户端进行推送，当然客户端还可以通过返回 RST_STREAM 帧拒绝和取消推送

### gRPC

可见 HTTP2 有这么多好用简单的功能，gRPC 天生就有相当多的优势。当然现在 HTTP2 还不是主流，实现 HTTP2 的服务器并不多，浏览器支持也参差不齐，所以 gRPC 自己实现了 HTTP2 客户端和服务端[^1]。以下是一些基本的 gRPC 文档。

1. [gRPC doc](https://github.com/grpc/grpc/tree/master/doc)
2. [gRPC over HTTP2](https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md)
3. [gRPC load and balance](https://github.com/grpc/grpc/blob/master/doc/load-balancing.md)
4. [gRPC Status Code](https://github.com/grpc/grpc/blob/master/doc/statuscodes.md)

gRPC 是一个支持多语言的 rpc 框架，但支持的方式稍有不同。Java 和 GO 是独立的项目，叫 gRPC-Java 和 gRPC-go，从底层直接用同一语言实现了 gRPC 的全部。其他语言，如 Python、PHP、Ruby 等，使用了 gRPC C Core 代码。相当于在语言层面上只是一个 wrapper，核心还是 C 语言实现。

由于我们第一个服务化的项目使用的是 Python，所以这篇文章更多的是浅析 Python binding 的 gRPC 源码，也会深入到 C Core 去了解 gRPC 代码。但不会涉及到 gRPC-Java 和 gRPC-go，不过我相信在原理上应该是一致的。

另外也考虑到内部服务不一定全部使用同一种语言，甚至工具也会更新迭代，今后在高性能部分，也会考虑使用更多的语言，特别是现在的特别火的也是 Google 自家的高性能语言 GO，所以以后研究 gRPC-go 也是迟早的事情。

[^1]: 不同的语言所实现的方式不一样，Java 实用 Netty，GO 原生支持，其他语言会绑定到 gRPC C Core 上。

### Protobuf

Protobuf 是 Google 的另一个项目，和 gRPC 搭配。gRPC 可以当做是实现了 HTTP2 的传输，但是不负责序列化和反序列化，只是负责把数据从一层传输到另一层，另外，gRPC 也实现了一个简单的事件队列，所以相对来说，Protobuf 负责的事情就比较简单了。

如何生成各种语言的代码，可以直接看官方的 Protobuf 介绍，我个人认为 Protobuf 比较简单，没有什么可介绍的，所以可以直接去 [官方网站](https://developers.google.com/protocol-buffers/) 看示例。

### Python Binding

由于我们第一个服务化的项目使用的是 Python，所以这里主要聊一下 Python 相关的代码，然后到 C Core 中去。

我们可以直接查看 Python 的官方 Example，[代码](https://github.com/grpc/grpc/tree/master/examples/python)。

我分析代码比较喜欢直接在代码中加注释，这样看的比较清楚。

### Server

{% highlight python %}
import time

# 通过 protobuf 生成的 pb2 文件
# 现在在样例中直接提供生成好的文件
# 但现实情况下我们需要自己使用grpc
# 来读 *.proto 文件生成代码
import helloworld_pb2

# sleep
_ONE_DAY_IN_SECONDS = 60 * 60 * 24

# 实现 Service 接口
class Greeter(helloworld_pb2.BetaGreeterServicer):

  # 实现 SayHello 接口
  # request 是定义的请求
  # context 里包含了其他
  # 的帧数据，例如 metadata
  def SayHello(self, request, context):
    return helloworld_pb2.HelloReply(message='Hello, %s!' % request.name)

# 运行一个 server
def serve():
  server = helloworld_pb2.beta_create_Greeter_server(Greeter())
  server.add_insecure_port('[::]:50051')
  server.start()
  try:
    while True:
      time.sleep(_ONE_DAY_IN_SECONDS)
  except KeyboardInterrupt:
    server.stop(0)

if __name__ == '__main__':
  serve()
{% endhighlight %}

上面的代码并不困难，就是一个跑起来的 Server，但在 gRPC Server 这一边，暂时有几个概念需要弄清楚。

1. HTTP2
1. Channel
2. CompletionQueue

HTTP2 就是我们如何起动一个实现 HTTP2 协议的的 server。

Channel 可以认为是客户端和服务端之间的通道，但是 Channel Python 这一端不能够主动的关闭，也就是我们没有办法维护这个 Channel，Channel 是可以维护自己的状态的，就是说，如果服务端断开了，客户端和服务端的 Channel 也会被断开，但是一旦服务端重启了，客户端的连接也会连上。

除此之外，Channel 状态的改变，是可以被我们利用的，服务端主动的断开了连接，客户端是可以收到断开的提醒的[^2]。但我们在这个提醒上没有办法做更多其他的事情。

CompletionQueue 是任务队列，gRPC 实现了一个简单的事件机制，队列用来传递事件，这个理解起来并不困难。我们可以简单的想象成下面这样的一个结构。

{:.center}
![gRPC Stack](/images/2016/grpc-class-stack.png)

{:.center}
大概的 gRPC Server 结构

[^2]: 也是一种帧类型。

当然，全局来看，并不只有这一个概念，还有 Stub 等概念，这个放在 Client 端再来详细的说明。

上图并不是一个流程图，只是画了一个大概的调用和运行的思路。代码栈的意思是，代码是如何层层调用最终调用到底层的，事件栈是指 gRPC 运行是一个什么样的流程。实际上 gRPC 其中的概念非常的多，接下来我们会仔细的了解各块运行的方式。

这系列文章只是一个笔记，加上个人水平有限，所以**难免有误**，希望发现错误联系我修正错误。并且，gRPC C Core 代码改动的比较频繁，所以会经常修改相关的文档。所以如果有遗漏或者变化，也比较正常。这里提供了一个看代码的方向和思路。

有任何问题都很欢迎联系我，非常感谢。

### 相关文章

1. [Basic](/posts/grpc-python-bind-source-code-1/)
2. [Server](/posts/grpc-python-bind-source-code-2/)
3. [CompletionQueue](/posts/grpc-python-bind-source-code-3/)
4. [Stub](/posts/grpc-python-bind-source-code-4/)
5. [Channel and Call](/posts/grpc-python-bind-source-code-5/)
6. [TCP Server](/posts/grpc-c-core-source-code-1/)

### 有关 C Core 的笔记

1. [Notes of gRPC](https://github.com/GuoJing/book-notes/tree/master/grpc)
