---
layout:    post
title:     Python中的__all__
category:  tec
description: Python中的__all__...
tags: code python
---
今天翻到Python-China.org的这个帖子[用__all__暴露接口](http://python-china.org/topic/725)，觉得还挺有意思的，专门下了Python的源码看\_\_all\_\_的姿势。

源代码里*Python/import.c*的函数*static ini ensure_fromlist*里面可以看到和\_\_all\_\_有关的逻辑:

{% highlight c++ %}
if (PyString_AS_STRING(item)[0] == '*') {
    /* 如果import *这样 */
    PyObject *all;
    Py_DECREF(item);
    /* See if the package defines __all__ */
    if (recursive)
        continue; /* Avoid endless recursion */
    all = PyObject_GetAttrString(mod, "__all__");
    if (all == NULL)
        PyErr_Clear();
    else {
        int ret = ensure_fromlist(mod, all, buf,
                                  buflen, 1);
        Py_DECREF(all);
        if (!ret)
            return 0;
    }
    continue;
}
{% endhighlight %}

其中除了*ensure_fromlist*递归之外，最主要的就是*PyObject_GetAttrString*。可以看出，如果是import \*的话就会读\_\_all\_\_字段，然后最主要的方法是*PyObject_GetAttrString*，到后面是个递归了。我们可以看*PyObject_GetAttrString*这个方法。在*Objects/object.c*里面。去掉无用代码，实际上就走到*PyObject_GetAttr*这个方法了。

去掉一些增减计数器的方法，直接就能看到返回的结果代码：

{% highlight c++ %}
if (tp->tp_getattro != NULL)
    return (*tp->tp_getattro)(v, name);
if (tp->tp_getattr != NULL)
    return (*tp->tp_getattr)(v, PyString_AS_STRING(name));
{% endhighlight %}

然后就是这个地方。tp可以看作是某个类型吧，代码如下。

{% highlight c++%}
PyTypeObject *tp = Py_TYPE(v);
{% endhighlight %}

Py_TYPE在*Include/object.h*里。

{% highlight c++%}
#define Py_TYPE(ob) (((PyObject*)(ob))->ob_type)
{% endhighlight %}

所以*tp*可以当成比如string，就是*PyBaseString_Type*之类的。每个类型都有*tp_getattro*或*tp_getattr*方法，就看如何实现。所以看上去其实list或者tuple都可以，因为各自有自己重载的getattr，这么说，string也行吧？

{% highlight python %}
__all__ = 'ab'

def a():
    print 'this is a'

def b():
    print 'this is b'

def c():
    print 'this is c'
{% endhighlight %}

可以`import *`试试看，a、b都可以，c是不行的。

那么如果这么写：

{% highlight python %}
__all__ = 'ab'

def a():
    print 'this is a'

def b():
    print 'this is b'

def ab():
    print 'this is ab'

def c():
    print 'this is c'
{% endhighlight %}

那么`import *`可以使用ab吗？答案是**不行**的。这就要看上面的tp\_getattro代码了。这个代码在*Objects/stringobject.c*里。我们可以看到tp->tp\_getattro就是*PyObject_GenericGetAttr*。那么dig这个代码，就能知道为什么ab不行了。其实从逻辑上来想，Python的string类型想象成字符的数组也很好理解。

当然这个纯属好玩，锻炼一下自己看Python代码的能力。开发中不应该`import *`，更不应该乱把\_\_all\_\_写成str。

代码基于Python2.7.x，也许其中理解也不一定对。
