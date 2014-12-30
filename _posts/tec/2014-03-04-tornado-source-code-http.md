---
layout:    post
title:     Tornado - HTTP
category:  tec
description: Tornado源码解析 HTTP...
tags: code tornado 源码解析
---
这几天简单的看了一下tornado的源码，就当是学习学习，其实网上已经有很多这方面的内容了，但都说的不是很仔细，有时候就是一个教程，讲讲tornado，socket之类的玩意儿。然后举例说几个函数使用就完了。我习惯一个一个看到函数，甚至到最后的字节，否则不明白还是不明白。所以是从一个一个文件到一个一个函数，如果打开了tornado源码，跟着一步一步的走下去，应该会比较清楚。

{:.center}
![tornado](/images/2014/tornado.png){:style="max-width:600px"}

{:.center}
Tornado全局

### IOLoop ###

大概了解了一下，画了一下简单的图，这就是tornado的模型，其实不同于普通的python web框架，tornado的模型挺有意思的。在tornado里，主要负责调度的是IOLoop这个东西，主要可以从tornado/ioloop.py这个文件来看，从class IOLoop来看。看到是继承了Configurable，这个东西的主要作用是根据不同的平台，选择调度的方式，比如Linux就是epoll，而BSD如Mac OS就是kqueue，剩下的走select。而IOLoop这个东西本身只是一个Interface，主要由子类实现。

实际上看，IOLoop里，主要用的是PollIOLoop里面的start方法，这个方法的作用就是一直监听socket。基本上整个模型就是，IOLoop监听socket，一旦有READ、WRITE和ERROR，就调用相应的handle event的方法。而所有的操作，都只是对IOLoop这个东西增加handler。比如GET一个页面，实际上就增加了一个handler，然后就返回。

### HTTP ###

那么从http这边来看，可以看tornado/web.py，看到application的listen方法，实际上调用的是tornado/httpserver.py的listen，然后又是tcpserver的listen，这里有意思的是使用了add\_sockets，里面调用了方法add\_accept\_handler，这个在netutils.py这个文件中，再仔细进去看，就会发现其实实际上用了IOLoop.add_handler的方法，那么这一块就明朗了，因为IOLoop是单例模式。add\_handler就相当于注册了handler，然后一旦监听的socket有事件，就从handler里取出数据并执行。

回过头来再看add\_accept\_handler的方法做了什么，因为重要的是执行完毕，需要调用callback，然后要处理数据并生成request对象。里面io\_loop.add\_handler里的callback方法实际上就是\_handle\_connection（跳过内联函数），查看代码，最后走到了handle\_stream，这个玩意儿在httpserver.py里实现了，其callback就是self.request_callback，那这个东西就是tornado.web.Application instance。

### IOStream ###

回到handle_stream，可以看到如何处理并生成request的。直接看httpserver.py里的handle\_stream函数，那就简单了，里面直接用了HTTPConnection这个类，在它的init方法里，会走到\_on\_headers，然后可以看到method, uri, data以及request如何生成的了。

看完上面之后，继续走下去，走到的是self.stream.read_bytes，实际上是在验证stream内容是否合法，最后调用callback，这个方法的第二个参数就是callback，也就是\_on\_request\_body，然后又回来看看，这里是实际上生成request的地方，生成完毕后就会调用self.request\_callback了，然后就回到了tornado.web.Application的instance了。然后实际上走到了\_\_call\_\_方法，注释也有写。接下来就是handler的东西了。

对如何生成request感兴趣的同学可以详细看\_try\_inline\_read()这个方法，更主要的是\_read\_to\_buffer和read\_from\_fd。

    chunk = self.socket.recv(self.read_chunk_size)

### SO ###

所以来看，基本上就是Application.listen就是注册了socket和handler，IOLoop一直监听socket事件，这两个东西完全分开，所以在demo里面看的到两个class的实例没有什么关系。当socket有事件之后，IOLoop负责调度到具体的handler，这个hanlder就是你写Application.add_handler里的玩意儿。然后执行了里面的\_execute，走到了\_when\_complete，然后其中执行了callback，callback实际上是self.\_execute\_method，就是get，post之类的方法了。

基本上这个框架的基础就是这样了。

### AND ###

* [Tornado - Websocket](/tornado-source-code-websocket/)
