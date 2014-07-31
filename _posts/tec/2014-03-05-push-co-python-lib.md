---
layout:    post
title:     PUSH.co
category:  tec
description: Push.co...
tags: code push co python lib
---
今天尝试了一下Push这个App，真是老土，其实我一直都不知道这玩意儿，下了之后用了用，觉得还不错，就随手写了一个包，这样就可以自己Push了。用起来很简单，但不知道这种模式未来能不能成，反正先占个坑吧。代码在[Github](https://github.com/GuoJing/push.co)上。

![pushcoapi](/images/2014/push.cox2.png)

也可以直接加入这个Push.co的lib[频道](http://push.co/a/0Pn0FOk6FqjQ)。保证没有无节操推送。

**安装**

{% highlight python %}
pip install pushcoapi
{% endhighlight %}

**验证**

{% highlight python %}
def auth():
    from pushcoapi.authorize import Authorize
    auth = Authorize(api_key, api_secret, redirect_url)
    url = auth.get_auth_url()
    print('1. Go to link below')
    print('2. Click Allow')
    print('3. Copy the authorization code.')
    print(url)
    code = input('Enter the authorization code here: ')
    data = auth.get_access_token(code)
    print(data)
    access_token = data.get('access_token')
    data = auth.check_access_token(access_token)
    print(data)
    return access_token
{% endhighlight %}

**订阅**

{% highlight python %}
def subscription(access_token):
    from pushcoapi.subscription import Subscription
    s = Subscription(access_token)
    print(s.gets())
{% endhighlight %}

**推送**

{% highlight python %}
def push():
    from pushcoapi.push import Push
    p = Push(api_key, api_secret)
    x, y = ('39.9026266648', '116.4012871818')
    ret = p.push_message('Hello, this is a '
                         'message from demo')
    ret = p.push_web('Hello, this is a web',
                     'http://guojing.me')
    ret = p.push_map('Hello, this is a map', x, y)
{% endhighlight %}
