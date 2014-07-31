---
layout:    post
title:     Heartbleed
category:  tec
description: OpenSSL心脏出血...
tags: 漏洞 OpenSSL
---
今天最火的就是OpenSSL Heartbleed Bug了吧，网上搜了一下尝试理解，看到这篇文章[《Diagnosis of the OpenSSL Heartbleed Bug》](http://blog.existentialize.com/diagnosis-of-the-openssl-heartbleed-bug.html)。我稍微翻译一下尝试理解，具体修复的[diff在这里](http://git.openssl.org/gitweb/?p=openssl.git;a=blobdiff;f=ssl/d1_both.c;h=d8bcd58df2b14818b8237bb70c979d62c7df5747;hp=f0c5962949e2046f4160eb04302a3b69585e5dcd;hb=731f431497f463f3a2a97236fe0187b11c44aead;hpb=4e6c12f3088d3ee5747ec9e16d03fc671b8f40be)，可能需要翻墙。

### 代码 ###

我们可以直接看代码：

#### <ssl/d1_both.c> ####

{% highlight c++ %}
int dtls1_process_heartbeat(SSL *s)
    {          
    unsigned char *p = &s->s3->rrec.data[0], *pl;
    unsigned short hbtype;
    unsigned int payload;
    unsigned int padding = 16; /* Use minimum padding */
{% endhighlight %}

可以看到一上来拿到的就是SSLv3的data数据，就是：

{% highlight c++ %}
unsigned char *p = &s->s3->rrec.data[0], *pl;
{% endhighlight %}

这个s3->rrec结构定义如下：

{% highlight c++ %}
typedef struct ssl3_record_st
{
    /* type of record */
    int type;
    /* How many bytes available */
    unsigned int length;
    /* read/write offset into 'buf' */
    unsigned int off;
    /* pointer to the record data */
    unsigned char *data;
    /* where the decode bytes are */
    unsigned char *input;
    /* only used with decompression - malloc()ed */
    unsigned char *comp;
    /* epoch number, needed by DTLS1 */
    unsigned long epoch;
    /* sequence number, needed by DTLS1 */
    unsigned char seq_num[8];
} SSL3_RECORD;
{% endhighlight %}

每个SSLv3记录包含一个类型（*type*）一个长度(*length*)和一个指向记录数据(*data*)的指针。然后再回头看`dtls1_process_heartbeat`函数，代码如下。

{% highlight c++ %}
/* Read type and payload length first */
hbtype = *p++;
n2s(p, payload);
pl = p;
{% endhighlight %}

SSLv3第一个字节记录了*heartbeat*类型，宏指令*n2s*的作用是从p读两个字节，并且放到*payload*里，这是*payload*的实际长度（*length*）。这里SSLv3记录的长度并没有被验证。*pl*则指向访问者提供的心跳包的数据。

继续往下走：

{% highlight c++ %}
unsigned char *buffer, *bp;
int r;

/* Allocate memory for the response, size is 1 byte
 * message type, plus 2 bytes payload length, plus
 * payload, plus padding
 */
buffer = OPENSSL_malloc(1 + 2 + payload + padding);
bp = buffer;
{% endhighlight %}

这里可以看到分配了内存数量为1+2+payload和padding。*bp*则是访问这块内存的指针。然后：

{% highlight c++ %}
/* Enter response type, length and copy payload */
*bp++ = TLS1_HB_RESPONSE;
s2n(payload, bp);
memcpy(bp, pl, payload);
{% endhighlight %}

宏指令*s2n*做了和*n2s*相反的操作，读入一个16bit长的值，然后存成双字节的值。所以*playload*的值等于请求心跳包的长度。然后从*pl*拷贝*playload*长的字节，存入新申请的*bp*数组。完成之后返回给用户。

### 漏洞 ###

既然没有检查长度，如果用户并没有足够的`playload`字节，或者*pl*只有1个字节，那么*memcpy*会把所有相同进程里SSLv3附近内存读取出来。

通常来说有两种*malloc*方法，一种是*[sbrk(2)](http://linux.die.net/man/2/sbrk)*和*[mmap(2)](http://man7.org/linux/man-pages/man2/mmap.2.html)*，如果使用*sbrk*申请内存，则堆是向上增长[^1]。所以能找到的敏感数据是有限的，但多个请求依旧可以读到数据[^2]。如果使用*mmap*，那么重要的数据很有可能可以通过*pl*指针获取[^3]。

那么这个BUG则是，如果攻击者构造一个特殊的数据包，满足*pl*只有1个字节或者*playload*没有足够字节，那么会导致memcpy把SSLv3记录之后的数据直接输出，该漏洞导致攻击者可以远程读取存在漏洞版本的*openssl*服务器内存中64K的数据。

[^1]: 向高地址增长。

[^2]: 可以重复读取64K内存，直到攻击者获取到想要的数据。

[^3]: 即便如此原作者还是收到反馈有私钥泄漏。

### 修复 ###

{% highlight c++ %}
/* Read type and payload length first */
if (1 + 2 + 16 > s->s3->rrec.length)
    return 0; /* silently discard */
hbtype = *p++;
n2s(p, payload);
if (1 + 2 + payload + 16 > s->s3->rrec.length)
    return 0; /* silently discard per RFC 6520 sec. 4 */
{% endhighlight %}

这段代码做了两件事，抛弃了长度为0的包并且确保包足够长。

下载代码：

git clone git://git.openssl.org/openssl.git

### 豆瓣 ###

当这个漏洞出来的时候，我第一时间尝试渗透豆瓣，没有成功，返回是『Connection Refused』，后来问了一下教授，反馈如下：

> 4月8日下午17:50 我们的处理手段就是禁掉了导致漏洞的 tls heartbeat 扩展（gentoo 系统可以通过调整 USE flag 来控制编译参数）来 workaround 漏洞的。4月9日 gentoo 社区发布了 openssl-1.0.1g 后我们做了升级， tls heartbeat 扩展继续禁用。等什么时候明确需要这个扩展的时候再考虑打开。

实际上如果不需要使用TLS的heartbeet扩展的话本地可以禁用这个扩展。不过针对这个问题，后来我把那几天可能受影响的用户登出，登录过的用户发邮件提醒，做了一些简单的提示，但最安全的方法还是修改密码。

另外值得一说的是，现在大部分密码的问题都是因为用户的邮箱被盗被爆，安全问题确实是一个非常复杂的，不仅仅是技术能独立解决的问题。
