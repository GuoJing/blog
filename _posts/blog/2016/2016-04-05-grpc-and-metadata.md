---
layout:    post
title:     gRPC and Metadata
category:  blog
description: gRPC Python 源码
tags: gRPC Python Google Source Coding HTTP2 Metadata
---

### Overview

最近使用 gRPC 遇到了一个这样的问题。大部分情况，gRPC 内容使用 protobuf 作为基本元素来传输。所以当我们需要实现一些特殊的功能，例如 HTTP1 里的 ETag，就必须得写死一些东西在 protobuf 里。代码不是很美观，而且 protobuf 修改起来非常麻烦，可能要重新编译客户端和服务端。所以我们在找是否有一种方式，可以实现类似 HTTP1 的 Header。

### Metadata

在 gRPC 中，有 metadata[^1] 可以实现这样的功能，但是大部分的文档只是写了如何从客户端发往服务端，但是并不知道如何从服务端发往客户端。但直觉上我认为是可以的，毕竟 HTTP2 是可以进行双向通信的，所以既然客户端可以发往服务端，服务端也可以发到客户端。

[^1]: gRPC 自己实现了 HTTP2 协议，并不是浏览器里的 HTTP2，这个概念要想明白。

之前也是看了很多代码，gRPC 代码写的比较隐晦，而且网上也没有相关的这方面的资料，光看代码还是有很多遗漏，后来在[邮件组](https://groups.google.com/forum/#!topic/grpc-io/U57gjPTVvcY)里和工程师讨论了一下，最终解决了这个问题。在解决这个问题的同时，又加强了一些概念。这里就不再详细分析各个概念是什么了，主要展示代码当做笔记，代码是 Python 实现。

### Example

server protobuf 文件

{% highlight python %}
message Empty {
}

message TouchResponse {
    StatusCode status_code = 1;
    string hostname        = 2;
}

service JediService {
    rpc Touch(Empty) returns (TouchResponse);
}

{% endhighlight %}

server 实现

{% highlight python %}

class JediServiceImpl(jedi_pb2.BetaJediServiceServicer):

    def touch(self, request, context):
        # just return hostname
        hostname = platform.node()
        return common_pb2.TouchResponse(status_code=common_pb2.OK,
                                        hostname=hostname)
{% endhighlight %}

运行一个 server

{% highlight python %}
def run():
    r = dsnparse.parse(GRPC_DSN)
    host = r.host
    port = r.port
    pool = ThreadPoolExecutor(max_workers=GRPC_POOL_MAX_WORKER)
    server = jedi_pb2.beta_create_JediService_server(
        JediServiceImpl(), pool=pool, pool_size=GRPC_POOL_SIZE,
        default_timeout=30, maximum_timeout=60)
    server.add_insecure_port('%s:%s' % (host, port))
    print 'server starting at %s:%s ...' % (host, port)
    server.start()
{% endhighlight %}

### Send metadata

发送请求的时候带上 metadata 非常简单，stub 提供了这个方法。

{% highlight python %}
request = common_pb2.Empty()
# 直接可以使用 metadata 参数
response = self.stub.Touch(request, _TIMEOUT_SECONDS, metadata=metadata)
{% endhighlight %}

这样在 server 端就可以获取到 metadata。

{% highlight python %}
class JediServiceImpl(jedi_pb2.BetaJediServiceServicer):

    def touch(self, request, context):
        # just return hostname
        hostname = platform.node()
        # get metadata from client
        metadata = context.invocation_metadata()
        return common_pb2.TouchResponse(status_code=common_pb2.OK,
                                        hostname=hostname)
{% endhighlight %}

到这里就非常简单。

### Get metadata

如果要从 Server 端获取 metadata，那么需要进行一些改动，每种语言实现的不同，Python 这一块，只要传了 `with_call=True`，就可以获得一个 Call 对象。这个 Call 对象很重要。

{% highlight python %}
request = common_pb2.Empty()
response, call = self.stub.Touch(request, _TIMEOUT_SECONDS, metadata=metadata, with_call=True)
# I can receive here
# but how to send from server?
for i in call.initial_metadata():
    print i
for i in call.terminal_metadata():
    print i
return response
{% endhighlight %}

上面的代码就从 server 端获取了 metadata。那么在 server 端如何发 metadata 呢？ server 端的 context 提供这个方法。

{% highlight python %}
class JediServiceImpl(jedi_pb2.BetaJediServiceServicer):

    def touch(self, request, context):
        # just return hostname
        hostname = platform.node()
        # get metadata from client
        metadata = context.invocation_metadata()
        # set metadata
        mt = [('a', '1'), ('b', '2')]
        context.initial_metadata(mt)
        # or context.terminal_metadata(mt)
        return common_pb2.TouchResponse(status_code=common_pb2.OK,
                                        hostname=hostname)
{% endhighlight %}

这样在客户端就可以收到来自服务端的 metadata 了。

### 相关概念

本来我还想继续分析这些概念在 gRPC 中扮演什么角色，但觉得实在有些过于复杂，其实我自己也在每天重塑 gRPC 的各个类之间的关系，加上 gRPC 也没有官方的文档，所以看起来有时候像迷失在森林中的感觉，不过这个需求也加强了以下两个概念的重要性。

* Call
* Context

这些概念会在以后的笔记中记录。
