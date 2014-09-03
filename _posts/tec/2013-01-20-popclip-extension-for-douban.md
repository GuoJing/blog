---
layout:    post
title:     PopClip + Douban
category:  tec
description: PopClip extension for douban...
tags: popclip extension douban search 插件 开发
---
今天闲逛App Store，发现原来有一个非常好玩的App，之前也有不少同事推荐过，只是当时我没有注意，今天下载下来玩了一下，总的来说还是不错的，这个App实现的就是和iOS上面的复制粘贴一样，当选择了一段文字或者内容，可以做相应的操作。比如我选中了部分文字之后，我可以复制粘贴，甚至可以选中email，它会自动识别成email并且让你选择发送邮件。比如选中abcd@gmail.com。会出现下图这样的界面，你就可以直接用默认的邮件App发送邮件了。

{:.center}
![popclip](/images/2012/mail.png){:style="max-width: 299px"}

当然它的作用不只一点点，这个App支持插件，也就是说是开放给开发者开发的，现在有很多的App都有插件，除了Amazon、imdb、Baidu、Taobao这样的可能是自己开发的插件，也有一些比如Evernote、OmniFocus、Things这样的厂商开发的插件，非常有用。很多时候比如我想选择一段话存到Evernote里，还得复制粘贴，我希望直接就好像“管道”一样发送到Evernote里就好，现在有了这个App，确实方便很多。当然，还有很多插件等待开发和挖掘，可以访问[官方的Extension](http://pilotmoon.com/popclip/extensions/)页面下载更多的插件。

**- Develop**

PopClip插件开发很简单，今天我看了一下文档，基本上一个小时到两个小时就能够写插件，PopClip支持的开发方式很多，简单的有普通的写Config的方式，如等下我要介绍的插件，不用写脚本。也有使用语言，比如**python**，可以使用python写脚本并动态的调用url好获取url的返回值实现其他更高级的玩法。PopClip支持：

* Service：执行一个Service
* AppleScript：执行Apple Script
* Shell Script：运行一个Shell Scrip
* URL：打开一个Url
* Keypress：执行一个按键组合

所以虽然这个App很小，但是可以做的事情还是有一些的，只有想不到没有做不到。而且开发起来非常非常容易，详细的开发方式和细节可以参考文档，这里提一个非常简单的开发流程。

简易开发流程：

1. 创建一个文件夹，里面写代码
2. 至少写一个Config.plist和一个图片文件，如Douban.png
3. 把文件名改为xxx**.popclipext**，即可安装使用
4. 如果想要发布，则把上面的xxx**.popclipext**使用zip压缩，再改名为xxx**.popclipextz**即可
5. Fork[这个代码](https://github.com/pilotmoon/PopClip-Extensions)并且按照要求加入自己的代码，commit and pull request

一个非常简单的PopClip插件就开发完成了。

**- Douban**

因为它很简单，所以我今天花了大概1个小时去写了一个Douban的插件，其功能很简单，就是选中了一些文字，然后很快捷的就可以在豆瓣搜索了。不过豆瓣的搜索产品有不少，所以我分别给每个产品写了一个，如果只想搜电影的话，可以只安装电影的插件即可，如果只想搜索同城，当然只安装同城的插件即可，如下所示。

<img src="/images/2012/douban.png" style="width:383px"/>

其原理很简单，就是将http://movie.douban.com/search_text={something}里的{something}替换了选中的文字，然后打开默认浏览器即可，连脚本都不用写，简单而实用，现在我搜电影终于不用复制粘贴，再在浏览器里输入movie.douban.com，然后再搜索了。同样，插件里面还有imdb可以选用，这样联合起来查找就更简单轻松了。

如果不是在官方插件网页下载，下载之后安装会提示这是一个不可信任的插件，依旧可以安装，如果不想有这个提示并去掉对不可信的插件的提醒（也可以用于debug），**需要执行下面这行命令，并重启PopClip**。

    defaults write com.pilotmoon.popclip LoadUnsignedExtensions -bool YES

**- Last**

如果只是想自己写了自己用，当然没问题，我相信这个App还可以帮我们实现更多有意思的事情，比如发一条豆瓣广播，发一个微博之类的。非常容易。如果你想要下载豆瓣搜索的这几个插件，可以从下面的链接下载，也可以查看源代码，有任何问题可以联系我，有关文档的超链接我也贴在了下面，不仅仅方便大伙儿，也方便我查看。：）

下载：

* [插件下载](/downloads/2012/PopClip-Douban-Extension.zip)
* [源代码](https://github.com/GuoJing/PopDouban)

相关页面：

* [PopClip](http://pilotmoon.com/popclip/)
* [PopClip Extensions](http://pilotmoon.com/popclip/extensions/)
* [PopClip Develop](https://github.com/pilotmoon/PopClip-Extensions#introduction)
