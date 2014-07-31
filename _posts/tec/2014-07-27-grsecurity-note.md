---
layout:    post
title:     Grsecurity
category:  tec
description: Grsecurity笔记...
tags: grsecurity linux kernel 笔记
---
最近在做一些服务器的安全配置，觉得SA这个职位真不好当，之前对Linux以及操作系统内核还挺感兴趣的，做了那么多，删了又重装了好几次，觉得无非也就那么回事，操作系统、内核、打包、更新什么的，要做的也就那么多吧。更不要说简单的扫了一遍Linux内核的东西，觉得计算机也无非就是那么样了，依旧无法跳出是人做的工程，就好比长城很伟大，但也是砖码起来的，并没有什么黑科技之类的玩意儿。

但是即便是如此，服务器使用起来也不是什么简单的活儿，才兼职了几天的SA，就不允许任何人再更新版本了，当然仅仅是暂时，每次更新一个软件，还得仔细看要更新哪些依赖，内核是否支持，会不会把其他的东西搞坏。即便搞坏了，能不能快速的恢复，等等，才能体会到SA这种职业真是吃力不讨好，做的事情很多，但是没有所谓产出，真是幕后英雄。联想到最近豆瓣服务器挂了那么长时间，真是要对所有在一线运维的SA们致敬才是。

我们的服务器是Debian，毕竟这个社区人多，安装包也多，自己懒得折腾，Arch什么的就不想在线上弄，当然Gentoo也是不可能的，最终选来选去，还是Debian，社区活跃度还不错，CentOS也可以，但和今天要说的主题没有什么关系，其实什么服务器都无所谓，除了Redhat[^1]以外，都不是那么省心。

[^1]: 说到Redhat，我初中到高中那段时间，用的竟然是Redhat9，但当时用的ADSL以及拨号上网什么的对我来说设置太难了，最终只能什么都干不了。

注意，这篇文章包括：

1. 为何使用Grsecurity
2. 如何编译内核以便使用Grsecurity
3. 基本的Grsecurity学习模式
4. gradm工具管理Grsecurity

### 为何使用Grsecurity ###

废话说到这里，终于可以了解一下Grsecurity了，相信很多人都使用了Grsecurity，但是网上资料比较少，除了官方的文档以外，基本上找不到什么好的使用笔记。另一方面，官方的文档虽然写的够详细，但很多错误的情况没写出来，这种感觉就和高中数学题里的『因此可得』一样，让人难以理解，我尽量把遇到的一些问题记录下来吧。

GNU/Linux有很多方面的安全加固，无论是用户空间还是内核空间，用户空间最简单的就是一些依赖的包的安全更新了，举个例子，比如说redis-server爆出重大漏洞，在第一时间就更新redis-server包，这是一个简单的用户空间的安全更新，又比如说root用户是否能SSH，等等，这些都是用户空间的一个简单的安全方面的内容。

除了用户空间的一些安全加固，还应该对内核方面进行安全加固，内核配置可以从*/etc/sysctl.conf*更改，使用*sysctl -p*生效。比如可以将*net.ipv4.tcp_syncookies*的值改为1，这样就可以防止防止SYN洪水攻击等等。内核配置有很多，可以根据服务器的情况来自行的修改。

除了内核模块的安全加固以外，还有直接深入内核的安全加固，就是使用Grsecurity/PaX的安全加固模式，这也是我们之后要详细说明的。但可以看到Linux安全社区对使用Grsecurity/PaX的安全加固模式的评价还是很高的。

> without Grsecurity/PaX, linux security is like monkey can never perform a regular masturbation cu'z lacking of giant pennis;-)

也就是说，如果不使用Grsecurity/PaX的安全加固模式，安全就不等于安全。因为有能力的黑客，当诱惑足够大的时候，依旧可以使用其他的方式入侵系统，这对系统是非常不好的。

### Grsecurity是什么 ###

Grsecurity是什么？首先可以看看官方的介绍。

> Grsecurity is an extensive security enhancement to the Linux kernel that defends against a wide range of security threats through intelligent access control, memory corruption-based exploit prevention, and a host of other system hardening that generally require no configuration. It has been actively developed and maintained for the past 13 years. Commercial support for grsecurity is available through Open Source Security, Inc.

简单的说，Grsecurity就是一个增强内核安全的工具，和SELinux以及Apparmor一样，用来控制文件访问权限等安全工具。但Grsecurity和这两个工具有点不太一样。我简单列举一下Grsecurity的好处。

1. Grsecurity深入的直接打包到内核
2. Grsecurity使用简单
3. Grsecurity有自主学习模式
4. Grsecurity能防御0day漏洞
5. Grsecurity具有保护共享网络中服务器的安全性

除了上面列举的几个安全问题，Grsecurity还支持很多安全功能。我觉得对我来说最重要的是0day漏洞和共享网络中服务器的安全性。最简单的来说，假设我有10台服务器，我有一个最核心的服务器，配置了各种安全措施，但是另外一台服务器非常的不安全，甚至已经被攻下了，那么实际上这个网络中的所有安全措施就已经是不安全了，但Grsecurity能防护这一点。

为何Grsecurity能防护这一点，因为Grsecurity是一个最小操作模式的一个安全工具，这个最小操作模式是我自己发明的瞎写的，便于理解。因为Grsecurity具有学习模式，在学习模式下，所有的命令以及需要使用的文件，相关的日志都会记录下来。一旦开启了Grsecurity的观察模式，那么除了这些命令以外，其他的命令就再也无法使用了。所以，Grsecurity和其他的安全工具相比，Grsecurity是一个白名单模式。

说到这里，插一段很囧的事情，当我第一次配置Grsecurity的时候，我开启了学习模式，然后简单的*ls*和*pwd*了一下，然后开启了观察模式，导致我甚至包括root都无法使用除了*ls*和*pwd*以外的命令，非常的囧。幸好可以直接去服务器上把Grsecurity的观察模式给关闭，要不然确实安装了一个极端安全但是无法使用的服务器了。所以在开启观察模式之前，一定要确保至少root可以执行一些**基本的命令**。

### 安装Grsecurity ###

Grsecurity需要打包到内核，所以需要重新编译内核，Linux的内核更新以及编译还算是比较简单，首先需要看自己的内核版本：

    cat /proc/version

其中会列出现在服务器的内核版本，比如Linux Version 3.2.0，这个时候需要到内核源码中下载相应的内核代码，我个人推荐找和现在服务器内核版本差异不大的版本。比如说我这里是3.2.0，最近的这个版本的升级应该是3.2.61，所以我使用这个版本的内核。

    cd /usr/src
    wget https://www.kernel.org/pub/linux/kernel/v3.x/linux-3.2.61.tar.xz
    tar -xf linux-3.2.61.tar.xz

然后去Grsecurity下载相应的patch，记得，一定要和你选的内核版本一致。

    ## https://grsecurity.net/download.php
    wget https://grsecurity.net/stable/grsecurity-3.0-3.2.61-201407232156.patch

其中3.0是Grsecurity的版本，而3.2.61是内核版本。

下载完成后，我们需要给内核打patch。

    cd linux-3.2.61
    patch -p1 < ../grsecurity-3.0-3.2.61-201407232156.patch

其实patch就是一个diff，打包完成之后，需要自己配置内核，使用以下命令：

    make menuconfig

如果编译不了，则需要安装支持插件的gcc，如下：

    # 服务器包管理不同，命令也可能不同
    apt-get install gcc-4.7-plugin-dev

上面的命令会打开一个配置窗口，在窗口中操作如下：

{:.center}
![Grsecurit](/images/2014/security1.png)

{:.center}
选择安全模式设置

{:.center}
![Grsecurit](/images/2014/security2.png)

{:.center}
找到Grsecurit

{:.center}
![Grsecurit](/images/2014/security3.png)

{:.center}
打开Grsecurit

{:.center}
![Grsecurit](/images/2014/security4.png)

{:.center}
选择配置Configuration Method

{:.center}
![Grsecurit](/images/2014/security5.png)

{:.center}
默认可以选择自动

{:.center}
![Grsecurit](/images/2014/security6.png)

{:.center}
打开Sysctl支持，如果有改动就无需再编译内核

完成之后执行：

    fakeroot make deb-pkg

这条命令会编译内核并且需要相当长的时间，这个时候只要等待即可。

当编译完成之后，安装：

    cd ..
    dpkg -i *.deb

安装完成之后reboot即可。

### Grsecurity的学习模式 ###

Grsecurity的配置文件相当的复杂，基本上不是人能完成的，况且如果写错了，那么服务器有可能很多命令不能执行，只能用键盘链接到服务器，然后使用安全模式进入服务器，关闭观察模式才行，所以Grsecurity有学习模式来生成配置文件。

学习模式使用*gradm*命令，同样在Grsecurity的下载页可以下载到。

    make
    make install

在编译之前，可能需要安装lex或者flex，以及byacc或者bison。

    # 服务器包命令不同，命令也可能不同
    apt-get install flex bison

安装好*gradm*之后，我们就可以配置安全规则了。

Grsecurity有两种学习模式，分别为：

1. Full System Learning，全系统学习模式
2. Process and Role-Based Learning，进程以及规则学习模式

两种学习模式使用起来差不多，简单说说全系统学习模式。

    # 请先打开gradm -h查看基本的命令
    # -F 使用全系统学习模式，日志输出到/etc/grsec/learning.logs
    gradm -F -L /etc/grsec/learning.logs

这个时候就可以开始学习了，学习的方式很简单，只要输入你常用的命令即可，系统会自动的学习。比如使用sudo，打开和关闭service，使用vi编写一段小的脚本，等等等等。命令最好重复3、4次以上，这样的记录会更加精确，不需要管比如vi使用了哪个其他的进程，使用了哪个log地址，这些都会被系统自动的记录。

如果需要进行管理员等高危操作的话，最好使用

    gradm -a admin

在使用完毕之后

    gradm -u

恢复到普通用户模式。

如果确定完成了录制，那么我们需要关闭录制功能。

    gradm -D

当操作完成之后，录制的工作也完成了，就可以看到learning.logs有很多命令，我们可以通过这个日志生成需要的规则。

    gradm -F -L /etc/grsec/learning.logs -O /etc/grsec/policy

生成完成之后，我们可以使用

    gradm -E

开启RBAC[^rbac]（前面说到的观察模式）模式，主动观察和防御一些不可靠的可能存在漏洞和安全隐患的操作。

[^rbac]: 基于角色的访问控制。

**这里需要强调一点的是，千万别学我只ls或者pwd之后就保存学习内容，然后开启RBAC模式，否则可能ssh的所有用户都无法使用除此之外的其他命令**，学习的时候之后要保证所有的应用程序，比如mysql以及redis等等都可以正常的工作。

如果需要开启ssh，那么在录制的过程中，需要某个用户ssh上去，这样才会记录下来ssh的用户，以及相应的ip，只有这样的规则的用户才能够最终到服务器上去操作。

举例说明有一台服务器A，我在上面配置了规则，什么都没做，然后开启了RBAC模式，退出，那么ssh无法使用。如果在录制的过程中，用户a、b、c，只有a ssh了，那么b、c将无法ssh，如果a的局域网ip是0.0.0.1，那么a用户在0.0.0.2上，无法ssh。

所以说Grsecurity的安全规则非常的严格。

### 配置学习规则 ###

除此之外，还可以在*/etc/grsec/learn_config*中配置学习规则，改动了这个文件的配置之后，学习的规则也会相应的改变，格式如下：

    <command> <pathname>

command可以为inherit-learn, no-learn, inherit-no-learn, high-reduce-path, dont-reduce-path, protected-path, high-protected-path,以及 always-reduce-path。

这些命令非常的容易理解，所以就不详细展开，例如high-reduce-path就会设置一个路径或者可执行文件为更加严格的模式，相反，dont-reduce-path则会减少对一个路径或者可执行文件的严格度。

### 业务的安全性 ###

在我还是上大学的时候，一个朋友王俊就黑了我的服务器[^2]。当时我一直没有把安全当成很重要的事情，后来到豆瓣，出了不少安全事故，我才慢慢的重视起安全问题。

[^2]: 而我们也是这样认识的，并且成为了很好的朋友。

有很多人会觉得我的服务器上没有什么重要的信息，或者说已经足够安全了，我觉得这种理念是不好的，所以才会有这么多的安全事故，以及现在如此不安全的互联网。计算机发展到今天，依旧还是之前我说的，没有什么黑科技，还是人类发明的玩意儿，很蠢，而且漏洞百出，所以不存在完全的100%的安全，无论是小的厂商，还是和金融有关的大的安全厂商，安全都应该是最开始就应该重视的问题。

当然，世界上没有100%的安全，安全问题永远出在最薄弱的那个环节，比如100台服务器，其中有1台被root了，那么剩下99台就不安全。也有可能即便服务器安全，应用程序权限太多，也不安全了。更有可能即便使用了像Grsecurity这样的工具，录制学习模式的时候，做了太多管理员的事情，相当于没有限制。更更更有甚者，把服务器用户名密码发到了网上。。。

而且，任何人都有可能出错，都有可能疏忽，所以安全是一个应该从开始就重视的问题。所以业务从一开始就应该重视安全，即便配置了安全设置，也应该当所有的数据都会被拖库，所以数据也要从底层增加安全性[^3]，以保证就算服务器不安全了数据也相对安全。即便所有的东西都不安全了，也可以增加黑客攻击的成本。

[^3]: 例如非对称加密算法。

当然，即便做到如此程度，安全依旧是一个问题，用户盗号之类的，依旧不能100%防护，甚至依旧挡不住，为什么？有可能用户的邮箱被盗了，等等等等。但即便如此，听上去好像毫无希望，但也比什么都不做的好。

之后也会介绍一些Grsecurity的高级使用方法。

### 相关网址 ###

[Grsecurity](http://grsecurity.net)

[Grsecurity Learning Mode](/tec/2014/07/31/grsecurity-learning-mode/)
