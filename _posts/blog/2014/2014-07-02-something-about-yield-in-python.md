---
layout:    post
title:     Python yield
category:  blog
description: Python YIELD及其相关
tags: yield PyEval_EvalFrameEx stack
---
最近在新公司里工作，有时候需要面试，但我之前没有面试过，为了防止扼杀了人才，我时时刻刻提醒自己要理解别人的代码，充分做好homework再评价，以免误人子弟，又没有招到好的人才，这就比较麻烦了。

话说最近遇到的一位同学，特别喜欢用yield，普通函数也使用yield，显得特别高级。yield关键词在Python中可是相当的高级，我自己平时大部分时间是不使用yield的，毕竟没有遇到什么特别需要使用的场景，所以不是很了解，于是就狠心下来了解一下yield如何实现。

----

小六同学简述了一下Python的Generator，具体在这里：

* [Python Generator](http://wolege.ca/tech/2014/05/17/yield/){:target="_blank"}
* [更加进阶的 Generator](http://wolege.ca/tech/2014/05/18/more-yield/){:target="_blank"}

我这里不会详细的说Generator到底怎么使用，我是在想，yield如何实现这样功能的，说的更清楚一点，Python是如何实现一个Generator，并且，如何保存函数上下文并且返回呢？

可以先从Python代码出发（Python的C代码我简称CPython）可以粗略的想象的一下，如果有一个Generator，代码如下：

{% highlight python %}
def gen():
    count = 0
    while count < 10:
        count += 1
        print 'call here'
        yield count
{% endhighlight %}

知道，函数并没有真正的执行，这个函数只是返回了一个Generator，也就是说如果我创建一个Generator如下：

{% highlight python %}
f = gen()
{% endhighlight %}

代码在这里，实际上只是创建了一个Generator，并没有真正的执行。也就是说f现在是一个Generator，而不是返回值。那么使用f.next()的时候，函数才会真正的执行。当执行到yield之后，虽然使用起来和return一样，f.next()等于return了一个值，但是这个时候，Python把函数的上下文保存了起来，直到下一次调用next()才会继续执行。

举个例子，如果我要遍历100万个单词，传统方法我可能要把100万个单词全部放到内存中去，而使用Generator之后，我取一个单词，如果暂时不需要单词，那么这个函数的上下文被保存在内存中了，直到下次调用才会再把数据拿回来。这有一个好处是，如果处理大数据或流式的数据，不需要一次性全部读出来，但是可以很自然的处理整个逻辑[^1]。

[^1]: 如果是普通的逻辑，比如1+1和读数据库，实际上没有太大的使用yield的必要。

----

简单的说明了一下yield使用之后，回到问题的关键所在。我很好奇，Python如何保存上下文，大量使用yield会有什么不好的地方吗？于是为了在面试别人提出问题的时候，我自己也能够心里有数，我特意看了Python的代码，以下我就简称为CPython。

**这里的分析仅仅是我自己的思考，可能有误解甚至错误。**

在这里，有两篇文章特别重要：

* [Python’s Innards: Interpreter Stacks](http://tech.blog.aknin.name/2010/07/22/pythons-innards-interpreter-stacks/)
* [Python’s Innards: Hello, ceval.c!](http://tech.blog.aknin.name/2010/09/02/pythons-innards-hello-ceval-c-2/)

这两篇文章都是讲解CPython中*PyEval_EvalFrameEx*的作用，第一篇讲的是内部的堆栈（Stack）的实现，第二篇详细的讲解了*PyEval_EvalFrameEx*。这里我简单的说一下这两个重点，可能理解有偏差，最好能自己去了解原文。

### 堆栈（Stack）###

堆栈（Stack）是计算机里最常用的数据结构，这里我就假装大家都知道，并且使用起来非常灵活。那么在Python中，有三个堆栈结构，Call Stack、Value Stack和Block Stack。

**Call Stack**，也被称作调用栈，是用于存储子程序信息的一类栈，别称执行栈（execution stack）、控制栈（control stack）、运行时栈（run-time stack）与机器栈（machine stack），在英语中亦经常简称为“栈”（“the stack”）。

{:.center}
![call stack](/images/2014/callstack.png){:style="max-width:400px"}

{:.center}
Call Stack

**Value Stack**，在Python中需要操作对象的时候用来操作内部对象时使用，比如说有Python的操作码（opcode）BINARY_SUBTRACT，这个操作码的作用是从栈中弹出两个值，在它们身上使用*PyNumber\_Subtract*方法，然后设置新的top值。每个Frame都有一个Value Stack。

**Block Stack**，基本上是在for、try、while里使用的堆栈，并且是一个有长度的Stack，所以执行循环次数过多的时候，会有deepest之类的报错。

### Frame ###

了解之后可以看看Frame这个东西，以我的理解，每个Call Stack里都有一些Frame，每个Frame都对应着Value Stack。Frame之间还有很多其他的关系，比如会有指向前一个Frame的指针，但这里就不需要深入了解了。只要大概知道Frame的作用就行。

所以，每个Frame都相当于一段背后执行的代码，并且每个Frame都恰好指向一个Code Object。所以当Python保存上下文时，在调用栈中可以很轻松的保存函数的执行的信息，包括地址，Frame的指针以及一些Value。

----

### PyEval_EvalFrameEx ###

如果我们要执行一个表达式，实际上会翻译成Python的操作码，也就是opcode，举例说明，假设我们有这么个一个函数。

{% highlight python %}
def a():
    b = 1+1
    return b
{% endhighlight %}

那么可以通过以下方法看Python的操作码：

{% highlight python %}
from dis import dis
dis(a)
{% endhighlight %}

可以看到输出如下：

    0 LOAD_CONST               2 (2)
    3 STORE_FAST               0 (b)
    6 LOAD_FAST                0 (b)
    9 RETURN_VALUE

无需了解特定的含义，但其实已经很明显的知道是什么意思了。那么其中的LOAD_CONST就是操作码。所以回到关键的*PyEval\_EvalFrameEx*，这个函数就是执行操作码的一个函数，例如LOAD\_CONST。

所以简单的来看，这个函数代码如下。

{% highlight c++ %}
PyEval_EvalFrameEx(PyFrameObject *f, int throwflag)
{
    /* variable declaration and initialization stuff */
    for (;;) {
        /* do periodic housekeeping once in a few opcodes */
        opcode = NEXTOP();
        if (HAS_ARG(opcode)) oparg = NEXTARG();
        switch (opcode) {
            case YIELD_VALUE:
                retval = POP();
                f->f_stacktop = stack_pointer;
                why = WHY_YIELD;
                goto fast_yield;
            /* lots of more complex opcode implementations */
            default:
                /* become rather unhappy */
        }
        /* handle exceptions or runtime errors, if any */
    }
    /* we are finished, pop the frame stack */
    tstate->frame = f->f_back;
    return retval;
}
{% endhighlight %}

也就是说，如果执行了yield命令，那么就会生成YIELD_VALUE操作码，也就是会被该函数执行到case YIELD\_VALUE中，于是我们就可以了解是如何进行Frame的操作了。

----

再次回到Python代码，如下：

{% highlight python %}
def gen():
    count = 0
    while count < 10:
        count += 1
        print 'call here'
        yield count
{% endhighlight %}

我们看一下机器码：

     0 LOAD_CONST               1 (0)
     3 STORE_FAST               0 (count)

     6 SETUP_LOOP              36 (to 45)
     9 LOAD_FAST                0 (count)
    12 LOAD_CONST               2 (10)
    15 COMPARE_OP               0 (<)
    18 POP_JUMP_IF_FALSE       44

    21 LOAD_FAST                0 (count)
    24 LOAD_CONST               3 (1)
    27 INPLACE_ADD
    28 STORE_FAST               0 (count)

    31 LOAD_CONST               4 ('call here')
    34 PRINT_ITEM
    35 PRINT_NEWLINE

    36 LOAD_FAST                0 (count)
    39 YIELD_VALUE
    40 POP_TOP
    41 JUMP_ABSOLUTE            9
    44 POP_BLOCK
    45 LOAD_CONST               0 (None)
    48 RETURN_VALUE

我们大概了解了机器码，确认其最终会使用YIELD_VALUE这个操作码。所以先想象Generator Object首先会操作自己的Frame，而操作的方法就是通过PyEval\_EvalFrameEx函数来执行。

为了确认，同样创建一个Generator，如下：

{% highlight python %}
f = gen()
{% endhighlight %}

仔细的深入了解，这个时候做了什么操作？实际上在CPython中，有一个[Object/genobject.c](http://hg.python.org/cpython/file/b3f4616b9a94/Objects/genobject.c)，这个类是Python中Generator的实现，可以看看，当f=gen()的时候，实际上调用了以下代码。

{% highlight c++ %}
PyObject *
PyGen_New(PyFrameObject *f)
{
    PyGenObject *gen = PyObject_GC_New(PyGenObject, &PyGen_Type);
    if (gen == NULL) {
        Py_DECREF(f);
        return NULL;
    }
    gen->gi_frame = f;
    Py_INCREF(f->f_code);
    gen->gi_code = (PyObject *)(f->f_code);
    gen->gi_running = 0;
    gen->gi_weakreflist = NULL;
    _PyObject_GC_TRACK(gen);
    return (PyObject *)gen;
}
{% endhighlight %}

这个代码很简单，就是创建了一个PyGenObject，注册了一个GC之类的就不说了，总得来说没有做什么事情。其中使用了一个*PyFrameObject*对象的实例作为参数，将其相关的信息例如f_code传给Generator对象，暂时可以想象为使用了之前的运行时的Frame并把相关信息给了Generator Object之类的吧。之后，Generator就有了自己的Frame成员。

----

在创建之后，可以看看代码，我们平时使用的Generator主要的接口是使用next和send，其实next和send的函数差不多，都是使用了*gen_send_ex*，仅仅是参数有区别。

{% highlight c++ %}
static PyObject *
gen_send(PyGenObject *gen, PyObject *arg)
{
    return gen_send_ex(gen, arg, 0);
}

static PyObject *
gen_iternext(PyGenObject *gen)
{
    return gen_send_ex(gen, NULL, 0);
}
{% endhighlight %}

可以看到，唯一的区别就是send传递了参数，而next没有传递参数。这一点在小六的文章里也简略的带过。好吧，看函数*gen_send_ex*，在里面我*print*了一些日志，方便查看。

{% highlight c++ %}
static PyObject *
gen_send_ex(PyGenObject *gen, PyObject *arg, int exc)
{
    PyThreadState *tstate = PyThreadState_GET();
    /* 获取Frame */
    PyFrameObject *f = gen->gi_frame;
    PyObject *result;

    if (gen->gi_running) {
        fprintf(stderr, "gi init\n");
        PyErr_SetString(PyExc_ValueError,
                        "generator already executing");
        return NULL;
    }
    if (f==NULL || f->f_stacktop == NULL) {
        fprintf(stderr, "check stack\n");
        /* Only set exception if called from send() */
        if (arg && !exc)
            PyErr_SetNone(PyExc_StopIteration);
        return NULL;
    }

    if (f->f_lasti == -1) {
        fprintf(stderr, "f->f_lasti\n");
        /* 如果Generator初始化并且send第一个值不是None */
        if (arg && arg != Py_None) {
            fprintf(stderr, "something here\n");
            PyErr_SetString(PyExc_TypeError,
                            "can't send non-None value to a "
                            "just-started generator");
            return NULL;
        }
    } else {
        /* 把参数arg push到frame的value stack中 */
        fprintf(stderr, "frame\n");
        if(arg) {
            fprintf(stderr, "with arg\n");
        }
        result = arg ? arg : Py_None;
        Py_INCREF(result);
        *(f->f_stacktop++) = result;
    }

    fprintf(stderr, "here\n");
    Py_XINCREF(tstate->frame);
    assert(f->f_back == NULL);
    f->f_back = tstate->frame;

    gen->gi_running = 1;
    /* 从Frame中取得yield的值 */
    result = PyEval_EvalFrameEx(f, exc);
    gen->gi_running = 0;

    assert(f->f_back == tstate->frame);
    Py_CLEAR(f->f_back);

    if (result == Py_None && f->f_stacktop == NULL) {
        fprintf(stderr, "here2\n");
        Py_DECREF(result);
        result = NULL;
        /* Set exception if not called by gen_iternext() */
        if (arg)
            PyErr_SetNone(PyExc_StopIteration);
    }

    if (!result || f->f_stacktop == NULL) {
        fprintf(stderr, "here3\n");
        /* generator can't be rerun, so release the frame */
        Py_DECREF(f);
        gen->gi_frame = NULL;
    }
    fprintf(stderr, "return result\n");
    return result;
}
{% endhighlight %}

所以，这个时候我调用f.next()的时候，会出现什么情况呢？

    f.next()

    f->f_lasti
    here
    call here
    return result
    1

好吧，可以看到，首先会print一个f->f_lasti[^2]，前面提到的两篇文章中就说明了这一点，这里简单的说一下f\_lasti是一个最后执行的代码的一个offset，默认是-1，这里可以看到一个新创建的Generator必然offset是-1，所以会进到这个地方，但是又没有arg参数，所以函数就继续了。

[^2]: an integer offset into the bytecode of the last instructions executed.

然后走到*here*，仔细看这里就最后使用了PyEval\_EvalFrameEx这个东西。从前面来看，PyEval\_EvalFrameEx是一个Python的操作码（opcode）执行的一个大的循环，最终执行了YIELD\_VALUE，实际上是fast\_yield。具体的实现可以看ceval.c，我也没有细看。

这个时候，Generator操作的是自己的Frame对象，可以简单的当作是一段一段的执行代码，虽然我们不需要仔细的了解Python是如何操作的，只要我们有这个想象就可以了。并且从Generator Object初始化代码中可以了解，Generator Object自身有一个gi_frame成员，这就是Generator里常用的Frame。

所以，这个时候执行到了gen函数里的print call here，那么就输出了call here，这点很容易理解。当执行到这里了之后，遇见了yield关键字，ok，这个时候PyEval_EvalFrameEx执行了fast\_yield，gi\_frame并没有清空，然后返回了result，这里的result的值是一个PyIntObject。

这个时候Generator已经交出了代码的控制权，返回给了Python虚拟机，所以顺序就变成了return result->1这样。实际上可以想象，Generator就是一个代码运行的一个控制器，其操作的就是内部的Frame。

当第二次使用f.next()的时候，输出如下：

    frame
    here
    call here
    return result
    2

可以看到，这个时候Frame已经不是空了，因为已经执行了部分的gen的代码，可以想象一下gi\_frame有这么一个指针[^3]，停在了刚才yield那个地方，当调用next的时候，函数继续从刚才暂停的地方继续，从刚才暂停的堆栈里继续下去，然后又一次遇到了PyEval_EvalFrameEx，然后函数又继续运行，运行到下一个yield关键字之后，又交出了控制权，返回了result结果，于是变成了return result->2这样。

我个人简单的理解，有了Generator，有了自己的Frame，然后自己的Frame执行操作，最后使用完毕，再销毁Frame。send函数也同理，只不过是将传递的参数首先压入了Frame里的Value Stack罢了。

[^3]: Generator对象自身的。

----

在最终销毁一个Generator对象时，执行代码如下：

{% highlight c++ %}
static void
gen_dealloc(PyGenObject *gen)
{
    PyObject *self = (PyObject *) gen;

    _PyObject_GC_UNTRACK(gen);

    if (gen->gi_weakreflist != NULL)
        PyObject_ClearWeakRefs(self);

    _PyObject_GC_TRACK(self);

    if (gen->gi_frame != NULL && gen->gi_frame->f_stacktop != NULL) {
        /* Generator暂停了, 所以可以关闭 */
        Py_TYPE(gen)->tp_del(self);
        if (self->ob_refcnt > 0)
            /* 如果引用计数大于0，就复活这个对象 */
            return;
    }

    _PyObject_GC_UNTRACK(self);
    Py_CLEAR(gen->gi_frame);
    Py_CLEAR(gen->gi_code);
    PyObject_GC_Del(gen);
}
{% endhighlight %}

其中*Py_TYPE(gen)->tp_del(self);*是调用了Generator对象结构体中的*gen_del*函数，最终又会走到*gen_close*。

{% highlight c++ %}
static PyObject *
gen_close(PyGenObject *gen, PyObject *args)
{
    PyObject *retval;
    PyErr_SetNone(PyExc_GeneratorExit);
    retval = gen_send_ex(gen, Py_None, 1);
    if (retval) {
        Py_DECREF(retval);
        PyErr_SetString(PyExc_RuntimeError,
                        "generator ignored GeneratorExit");
        return NULL;
    }
    if (PyErr_ExceptionMatches(PyExc_StopIteration)
        || PyErr_ExceptionMatches(PyExc_GeneratorExit))
    {
        PyErr_Clear();          /* ignore these errors */
        Py_INCREF(Py_None);
        return Py_None;
    }
    return NULL;
}
{% endhighlight %}

再看看，最后还是调用了*gen_send_ex*。

----

大概yield的实现就是这么理解吧，其实有很多细节的部分还没有解释清楚，因为我自己也不是很深的了解编程语言这种东西。我会慢慢更新，查漏补缺，再说像我这种垃圾水平，或者有什么改三观的改变也也有可能。

所以我觉得疯狂使用yield，一是没必要，因为不是所有情况下使用yield都是好理解的，另外就是我们的程序中，很多函数只调用一次也许就不再第二次调用了，如果大量的写yield，会存储过多的上下文，如果不考虑好如何回收内存的话，可能会有内存泄漏的问题。