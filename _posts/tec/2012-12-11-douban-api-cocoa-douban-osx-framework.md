---
layout:    post
title:     Douban OS X Framework
category:  tec
description: OS X Frameowork for Douban...
tags: douban framework cocoa osx mac
---
最近有一些事情要做，虽然不是那么紧迫，但是总之是不得不做的事情。这个事情就包括所谓的季度计划。季度计划是学习Cocoa并且写一个桌面客户端，由于之前写过Cocoa程序，而且本来觉得季度计划可以用我们现有的iOS的框架就可以轻松搞定，但是发现我们现有的Object-C框架还是不支持OS X的，所以有些怅然。当然，仔细看了一下代码之后，发现其主要原因是因为引用的很多第三方的包并不支持OS X。所以为了完成季度计划，就必须重写一个支持OS X的Douban Framework，虽然我觉得以后写桌面客户端这个需求可能不大，但多多少少好歹也算是一个贡献。

这其中我稍微看了一下Dropbox的OS X的Framework，学到很多东西，其中包括打包和发布，并且如何才能轻易的让别人使用，受益匪浅。而Cocoa的MVC确实做的很彻底，写起来也没有多大的困难，但现在对我而言Cocoa还不够简单，NS开头的Class我还觉得不是很好理解为什么要这样，而且相应的方法，类方法也不知道怎么快速的查找，还得查文档，相当的不习惯。当然随着时间越来越久我会越来越深入的了解这一块，倒是不用担心。

这个版本抛弃了GData的支持，直接使用V2版本的豆瓣API，用OAuth2，走HTTPS。因为也比较简单，而且只支持了OS X 64位的编译，毕竟32位的越来越少，而Mac硬件的升级也不会再往回考虑的习惯，所以我个人觉得相当没问题。这个版本只是从iOS移植过来的版本，所以使用和iOS的没有多大差别，但是代码目录改变了，更加清晰简单，这只是第一步。更重要的是以后会有更多helper之类的类来帮助更好的更简单的去访问API，例如现在对于取到单个活动我还要自己去写http请求这件事，我觉得还是不够满意，至少model的实例化可以更智能一点，而不只是一个很裸的接口，**这个会在下一个版本去优化**。

理想中应该是这样的，例如获取单个同城活动。

	DOUEvent *event = [DOUEvent initWithRemoteID:event_id]

其中自动化的实现了http请求和异常处理，并且返回一个真正可用的实例。当然这其中还有很多要准备，还有很多要攻克，但简单一定是基本中的基本。如果你需要，可以直接fork代码，它开源。当然我是Cocoa的新手，还需要更多的经验去把代码梳理的更好，如果你不嫌弃，可以自行使用。这里推荐使用framework打包之后引用到项目内，而不是直接引用项目的project文件，因为使用起来相当简单，不用引入更多其他的库，而且也更加稳定。

* **[DoubanAPICocoa](https://github.com/GuoJing/DoubanAPICocoa)**

这里还要感谢[郭少](http://www.douban.com/people/linguo/)的帮助，然后，Happy coding with Douban.