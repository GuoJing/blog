---
layout:    post
title:     Tornado - Websocket
category:  tec
description: Tornado源码解析 Websocket...
tags: code tornado 源码解析
---
上次看了Tornado整个HTTP分析之后，写了[《Tornado - HTTP》](/tec/2014/03/04/tornado-source-code-http/)觉得很有意思，之前接触的都是简单的wsgi模型，当然，是我太土太垃圾了，实在是说不出口抬不起头，又不好意思问。因为问了别人别人总是会以『这你都不知道』反驳，或者直接丢一个『什么是Websocket』之类的文档。看看代码，估计又是ws = new Websocket这种js使用。虽然我很搓，但总之这样得不到解答还是很难受的。

所以这次又看了一下tornado/websocket.py这个文件，觉得很有意思，权当了解一下Tornado的Websocket实现。当然还是从代码里走函数，走马观花。之前的[《Tornado - HTTP》](/tec/2014/03/04/tornado-source-code-http/)这里面可以看到，任何注册hanlder，最后都会执行到_execute里去，所以，好嘛，这就简单了。

不过还是先从demos/websocket/chatdemo.py去看。

这里面的Application注册了两个Handler，一个是当前页面，一个是实现Websocket的。MainHandler继承自tornado.web.RequestHandler，ChatSocketHandler继承自tornado.websocket.WebSocketHandler。嗯，但其实进去会发现tornado.websocket.WebSocketHandler也是继承自tornado.web.RequestHandler的，不过重写了很多逻辑。因为Websocket本身也是基于HTTP和socket来实现的。

所以直接走到tornado/websocket.py里的_execute方法，request怎么获得前面都说过了，就不扯了。可以看到，里面针对Websocket协议做了很多判断，比如Websocket只支持GET，并且请求必须是Upgrade而且值是websocket。然后通过header里的Sec-WebSocket-Version，找到不同的实现函数。随便选一个，比如我们可以选WebSocketProtocol13。

WebSocketProtocol13这个类继承自WebSocketProtocol，可以跑去看看，WebSocketProtocol的init方法需要传一个hanlder，从demo来看，就是ChatSocketHandler。出来看WebSocketProtocol13，执行了accept\_connection，走到了\_accept\_connection，会往stream里写入一些服务器的信息，然后执行async_callback，其中执行的方法就是handler的open方法。到这里就明白了，IOLoop监听了socket的事件，返回给handler，这一步和HTTP没有什么区别，只是实际上针对不同的协议做了不同的事情，本质差不多，在读取信息选择事件的时候，可以直接看\_handle\_message这个方法，除了响应了handler相应的方法，还针对本身socket和stream做了相应操作。比如`opcode == 0x8`，就是close操作。

使用起来很简单，主要是on\_message handle消息和on\_message向客户端发送消息。

基本上这样来看，Tornado实现Websocket也简单明了了。不过HTML 5还有SSE，这样也挺简单的呢。

### AND ###

* [《Tornado - HTTP》](/tec/2014/03/04/tornado-source-code-http/)