---
layout:    post
title:     IFTTT and Home
category:   tec
description: Raspberry PI...
tags: code raspberry pi wemo switch motion philips hue 树莓派 开发
---
### Overall ###

最近在家里添置了不少智能设备，一个是Wemo的Switch和Motion，还有就是Philips的Hue了。这两个我就不过多介绍了，可以看下面的两个官网链接，Wemo Switch和Wemo Motion国内的在线App Store有售，分期无息还是相当划算的，Philips Hue就相当难买了，需要海外淘，等不少时间。

1. [Wemo](http://www.belkin.com/us/wemo)
2. [Philips Hue](https://www.meethue.com/en-US)

Wemo Switch相当于是一个Wifi插座，对于重要的东西，出门总是觉得忘了关，实在不行就用Wemo的App去关就好了，Wemo Motion是一个传感器，如果在一定范围内有人运动，就会响应，然后执行在App里设定的动作。

Philips Hue是Wifi智能灯泡，还可以变很多种颜色，灯是相当的不错，其App提供智能开关，提醒，闪耀以及定位功能。定位功能是当你回到家之后，灯会自动开，当你离开家之后，等会自动关。

除了单纯的Wemo设备以及Hue以外，还可以使用**IFTTT**去设置这些设备，相当有创意，比如用了手环测试睡眠，当发现睡眠小于8小时，Wemo Switch就打开然后泡茶；或者外面要下雨了，则打开室内的灯光并显示淡蓝色；国外的IFTTT服务也更多，比如当飞机安全降落，则家里的灯闪几下。

### Raspberry Pi ###

随着个人电脑的普及，现在更小更简单的计算机已经非常普遍了，比如说Raspberry Pi（树莓派），树莓派是一个小的装有Linux的主机，主要是ARM，非常小巧简单，一般的有两个USB扣，一个SD卡作为硬盘，还有一个电源，一个HDMI输出，当然还有RJ45网线口和一些音频口。Raspberry Pi不算贵，大概250-350之间，在家里做小型主机还是相当不错的。

我用树莓派在家监视狗的动向，相当简单，买一个一般的USB摄像头，插入到树莓派里之后，定时拍照就可以了，Linux下面很多命令都可以使用，而且最新的树莓派的ROM直接支持摄像头，即自然就有驱动了，直接看/dev/vedio0就行，不需要过多安装什么。拍照可以使用fswebcam或者motion捕捉动态都可以。不过树莓派毕竟是微型的设备，CPU什么的不能指望太多，所以拍照不能太大，大概355是比较好的，如果太大则有些会处理不完是灰色的，有的甚至会报错。motion虽然不错，但是对稍微远距离一点的像素改变的感应有些不好。

### Raspberry Pi + Philips Hue ###

因为Hue是智能设备，而且提供开放的API，就可以使用树莓派在家里做很多事情了。实际上Hue的API是本地API，买Hue的时候，会给你一个小的无线的Hub，这个Hub会与Hue的服务器通信，也作为一个本地的服务，提供对本地的API访问。如果有Hue，可以使用`http://ip/debug/clip.html`来调试API。

因为想要方便的去做Hue的开发，我写了一个Python的包可以使用，叫[pyhue](https://github.com/GuoJing/pyhue)。可以去[Github](https://github.com/GuoJing/pyhue)找到代码并且使用。使用起来相当的简单。

{% highlight python %}
from pyhue import hue
hue = Hue()
{% endhighlight %}

就可以拿到当前的Hue了，但这里需要写本地的local_config.py配置你的Hue的服务器，也可以看Hue实例化里也可以通过Hue(ip)来获得。

当然，Hue使用upnp，可以通过upnp获得Hue。

{% highlight python %}
from pyhue.upnp import get_hue
hue = get_hue()
{% endhighlight %}

这里这个包会自动通过UPNP网址来获得Hue的信息。无需额外设置。当然最好还是写config比较容易。

然后就可以使用hue对象做很多事情了：

{% highlight python %}
lights = hue.lights
for l in lights:
    l.off()
    l.on()
    l.alert()
{% endhighlight %}

### Raspberry Pi + Wemo ###

Wemo实际上也是使用UPNP的，所以可以通过收发UPNP广播来获得相应的信息。我基于ouimeaux同样写了一个python包可以方便的使用python来管理Wemo设备，ouimeaux本身是一个Wemo的python包，可以使用pip install来安装，我这里改进了一些方法，并且增加了回调。ouimeaux本身会使用gevent起一个WSGI的服务，并且服务用来接收广播，也就是说当Wemo设备变化状态的时候，服务器会收到响应。

ouimeaux可以在[这里下载](https://github.com/GuoJing/ouimeaux)，我主要增加了两个方法：

{% highlight python %}
device.on_device_updated_on
device.on_device_updated_off
registry.register(device)
{% endhighlight %}

当搜索到设备之后，可以给设备注册事件来获取事件响应，从而做相应的操作，具体可以看main.py。

获得设备后，就可以开关了：

{% highlight python %}
switch.on()
switch.off()
{% endhighlight %}

注意Switch和Motion是不同的，Motion只是用来感应，所以没有on和off方法，但必须要注册一个事件，当事件相应之后会调用WSGI服务，然后在这里你就可以做自己的处理了。

### Raspberry Pi + Wemo Motion + Philips Hue ###

由于升级到iOS7之后，Philips的Hue App的地理定位信息不能用，实际上是Access Token会莫名其妙的超时，被远程重置，测试iOS6是不会有这个问题，谁叫我尝鲜了呢，不过没办法，iOS7还可以，也不想往回刷了，于是就只好自己实现，Raspberry Pi作为主机，Wemo Motion做传感器，一旦感应到有人回家，就打开Philips Hue。

大概逻辑如下：

    if after 6 pm and someone is coming home:
        open philips hue

这里就可以使用上面说的ouimeaux以及pyhue来实现了。具体可以看我Githu上面的[homehue](https://github.com/GuoJing/homehue)代码下的main.py文件。

当然不仅仅可以实现这么简单的功能，甚至在树莓派上只要写python，就和平时写程序一样，一旦有豆瓣广播提醒或者新浪微博提醒，就闪动家里的灯，或者给机器人发送一个消息，就把家里的设备全关上，都是可以的，只有想不到的，没有做不到的。

**TIPS: 在树莓派上是搜不到UPNP的设备的，需要将/etc/hosts里的localhost以及raspberry的ip地址从127.0.0.1设置为局域网的ip，也就是局域网的设备ip，比如我的树莓派在路由器里显示的是10.0.1.85，则设置为这个ip就行**。另外对于这些设备，最好能够通过Mac地址固定ip，会更容易。

最后在树莓派上设置开机启动什么的我就不多说了，属于linux范畴的东西了，Google一下就会有了。

### Codes ###

1. [pyhue](https://github.com/GuoJing/pyhue)
2. [ouimeaux](https://github.com/GuoJing/ouimeaux)
3. [homehue](https://github.com/GuoJing/homehue)
