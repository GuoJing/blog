---
layout:    post
title:     树莓派+Dropbox
category:  tec
description: Raspberry Pi + Dropbox Sync...
tags: code life raspberry dropbox sync
---
最近买了Raspberry在家做主机玩。其实很土，Raspberry在厂里很火的时候，我都没有一起玩一把，可却过了一年多最后才买了Raspberry。说实话，其实是Google Glass让我震惊了一把，并不是说技术有多难，或者多难实现，只是突然明白原来马上穿戴提升人类技能和认知的时代马上就要来临了。更是后知后觉的发现，互联网又会成为类似下一个电信商的地位，迟早会成为基本平台。当然，这种技术不是新的，Google Glass实现使用的硬件也是很普通的硬件，并不是什么高科技，而各类传感器LED什么的更是在大街上像菜市场一样，唾手可得，但之前制约硬件的互联网基本数据现在已经成熟，又有一个或若干个新渠道被挖掘出来了，这不得不说又是一个美好的时代。

所以其实想在家实现一个智能的控制系统，这个想法还是起步，并不成熟。但像我这样的屌丝用的是小区宽带，所以并无法从外面通过IP访问到我的PI，于是只好通过Dropbox这样的东西来实现。Dropbox的好处是比较稳定，而且任何一个可以访问互联网的设备都可以在Dropbox上面增加和修改文件，任何对文件的操作都有记录并且可以保存和回滚。所以我选择了Raspberry Pi + Drobox的方案。

不过之前也选择了很多其他的方案，除了换ADSL或者办独立IP，如果以后有能力了可以考虑，而小区宽带一口气办了两年，也不该浪费。方案比如有用Git来实现，或者自己搭一个服务器。自己搭服务器就太浪费了，本来就是想在自己家做一个小的数据控中心，再搭服务器不是白瞎么。然后用Git来实现的话，每次还得提交和push，太麻烦，我想做到的事情仅仅是在固定的文件夹目录下面写一个command.sh，写完之后就完事了。Dropbox能够自动帮我同步到PI里，然后执行，然后删掉。

听上去很容易，而且Dropbox还有SDK和命令行版的包，可惜，**Dropbox的工具并不支持Raspberry PI，因为它不支持ARM结构**，很可惜。所以我用了Dropbox的Python SDK自己实现了一个简单Dropbox客户端，会监控文件的修改并同步。当然，这里面还有很多小的问题，但实现我的需求就是牛刀了。

[Download the Code from Github](https://github.com/GuoJing/Drop2PI)

为什么自己实现呢，其实当时搜了很多相关的解决方案，我并不是一个勤快的人，能用现成的开源的东西自然就用现成的了，可惜没有好的解决方案，而且网上大部分人都在找如何同步Raspberry PI和Dropbox，最后实在是没办法，才又自己写了。实在是无奈之举。

在使用之前，需要到[Dropbox Develop Page](https://www.dropbox.com/developers/apps)去申请一个APP，没错，我们需要写一个APP来实现这个功能。这个包的依赖有Watchdog和Dropbox Python SDK。

下载代码之后：

{% highlight bash %}
cp config.py.tmp config.py
{% endhighlight %}

在config里写上APP_KEY，APP_SECRET以及ACCESS_TYPE。TOKEN_FILE和PATH_TO_WATCH不用管。但PATH_TO_WATCH是你同步的目录，Watchdog会监控这个目录。

然后：

{% highlight python %}
python auth.py
{% endhighlight %}

脚本会让你去一个url认证，认证完了之后按回车。如果写了token文件，那么就是认证成功了。

然后运行：

{% highlight python %}
python watching.py
{% endhighlight %}

就可以了。当然我自己还有一些自用的脚本，比如在PI上有个crontab会一直读文件，然后执行，执行完毕后又写log文件到PATH_TO_WATCH，最后当我写了command命令之后，执行完毕，PI又会写一个log文件传回到Dropbox里，我还能看到日志。

我自己是使用了开机执行，树莓派只要通电就可以启动，所以就算断电也没问题。当然在PI上还有一个crontab在处理这个命令队列，并写回日志到Dropbox。这个系统在我家跑了几天，暂时还没有什么问题。

不过也有一些已知的问题需要解决，因为我没有push服务器，所以Dropbox上文件的删除什么的，是不知道的。所以在脚本里会每隔一段时间去检查是否文件被删除了。而且，每次对文件的操作，比如增加、修改、删除、移动，都会执行完成之后马上下载最新的服务器版本，因为如果你改了文件a，其实b在服务器上也已经改了，如果这个时候你再改b，就把服务器上的覆盖掉了。那是不好的，所以修改了a之后，会下载b重新覆盖b，需要保证服务器上永远是最新的版本。所以这个时候会出现很多问题，比如修改了a，下载b，b修改就被覆盖了。比如没有运行这个框架，那么修改了一个文件a，不会被监控，然后运行之后，会从服务器上下载最新的版本覆盖。又比如同时修改和删除文件，修改了之后，触发了事件，删除的文件又被从服务器上下载下来了。总之，不是一个多任务的系统。

Dropbox在这一点是通过文件的版本号来控制的，我本地要尽量简单，可以到哪都运行，依赖的包越少越好，不要使用数据库什么的，所以没办法记录，但同步的问题是会解决的，比如触发了一个事件就到事件队列里，其他的事件等候，等等。

现在，在手机上写一个脚本，家里的PI就可以执行了，以后还会有一些机器人，电源控制的东西，要开灯要关灯要监控家里的录像，完全可以写文件在Dropbox里实现。如果有一天我有钱了弄了一个固定IP，就更简单。

有时候想想很激动，我带着我的UP，它知道今天的天气很热，而我的心情又不是很好，当我要到家的时候，我家的PI会问我，主人，看上去你今天心情不好，要不要来根冰棍？

多么激动人心。

[Download the Code from Github](https://github.com/GuoJing/Drop2PI)
