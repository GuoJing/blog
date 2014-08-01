---
layout:    post
title:     Grsecurity Learning Mode
category:  tec
description: Grsecurity Learning Mode...
tags: grsecurity learning linux kernel 笔记
---
在[Grsecurity](/tec/2014/07/27/grsecurity-note/)这篇文章里简单的记录了什么是Grsecurity，如何安装以及使用Grsecurity。Grsecurity是一个非常复杂的软件，但其实只要理解了计算机以及操作系统，也就没有那么复杂了。Grsecurity的规则文件非常的简单，但要人手工生成却过于庞大，百密一疏，很难掌握。Grsecurity提供了gradm工具来生成规则，在之前的文章已经说明了如何安装和使用gradm，这里就不贴安装指南了。

注意，这篇文章包括：

1. gradm
2. 日志文件分析
3. Full System Learning，全系统学习模式
4. Process and Role-Based Learning，进程以及规则学习模式
5. 高级的日志文件编写

有几个简单的概念：

1. RBAC: Role-Based Access Control，基于角色的访问控制
2. ACL: Access Control List，访问控制列表

### gradm ###

安装gradm在这篇文章[Grsecurity](/tec/2014/07/27/grsecurity-note/)。

gradm是Grsecurity的日志管理工具，几个重要的命令如下：

    gradm 3.0
    grsecurity RBAC administration and policy analysis utility

    Usage: gradm [option] ... 

    Examples:
        gradm -P
        gradm -F -L /etc/grsec/learning.logs -O /etc/grsec/policy
    Options:
        -E, --enable                      开启RBAC系统
        -D, --disable                     关闭RBAC系统
        -C, --check                       检查配置文件是否正确
        -S, --status                      检查RBAC系统的状态
        -F, --fulllearn                   全系统学习模式
        -P [rolename], --passwd           为RBAC模式的管理员管理密码
        -R, --reload                      在admin模式里重新加载RBAC系统
        -r, --oldreload                   重新加载RBAC系统，会丢弃存在的特殊的规则和继承的subject
        -L <filename>, --learn            学习的输出日志
        -O <filename|directory>, --output 输出日志
        -M <filename|uid>, --modsegv      移除一个UID或者文件的禁用状态
        -a <rolename> , --auth            对于特殊的规则需要验证
        -u, --unauth                      去掉验证

现在我们可以使用gradm来进行安全管理了，接下来统称为policy。

### 日志分析 ###

当使用以下命令输出日志的时候：

    gradm -F -L /etc/grsec/learning.logs -O /etc/grsec/policy

我们是通过日志文件生成了policy文件，Grsecurity会使用这个文件进行访问控制，我们可以简单的看看policy的日志文件，其实读起来并不困难，写起来也不困难，只是这个工程量浩大，几乎无法人为完成。

    # policy generated from full system learning

    define grsec_denied {
            /boot   h
            /dev/grsec      h
            /dev/kmem       h
            /dev/mem        h
            /dev/port       h
            /etc/grsec      h
            /proc/kcore     h
            /proc/slabinfo  h
            /proc/modules   h
            /proc/kallsyms  h
            /lib/modules    hs
            /lib64/modules  hs
            /etc/ssh        h
    }

    role admin sA
    subject / rvka
            / rwcdmlxi

    role shutdown sARG
    subject / rvka
            /
            /dev
            /dev/urandom    r
            /dev/random     r
            /etc            r
            /bin            rx
            /sbin           rx
            /lib            rx
            /lib64          rx
            /usr            rx
            /proc           r
            $grsec_denied
            -CAP_ALL
            connect disabled
            bind disabled

    role default
    subject /
            /                       h
            -CAP_ALL
            connect disabled
            bind    disabled

文件非常的简单，分别是role、subject。

1. role可以被认为是角色，例如*role admin sA*和*role default*
2. subject是一个可执行文件，一个subject只能指定一个可执行程序

*role admin sA*定义了一个规则，其中role是规则，admin表示管理员规则，sA是规则属性，这些属性分别为：

* u: 这个role是一个用户role，说明这个role必须在系统上有一个真实的用户
* g: 这个role是一个组的role，说明这个role必须在系统上有一个真实的组
* s: 这是一个特别的规则，表示并不属于一个用户或者一个组
* l: 小写的L，表示这个规则属于学习模式
* A: 这是一个管理员模式
* G: 这个规则使用gradm验证到内核
* N: 这个规则不需要验证
* P: 这个规则需要PAM验证
* T: 这个规则有可信的TPE（Trusted Path Execution）
* R: 除了关闭系统以外不需要再任何规则上使用

除了role的这些属性，还可以定义*role_allow_ip*，运行只有哪个ip可以使用这个命令。

    role guojing u
    role_allow_ip 192.168.1.0/24
    subject /bin/bash /

以上指定了了这是一个用户guojing的规则，在执行可执行程序/bin/bash时的规则，并且只允许ip 192.168.1.0访问。

对于subject的理解，可以举个例子如下：

    # Role: guojing
    subject /bin/bash o {
            /
            /bin                            x
            /boot                           h
            /dev                            h
            /dev/tty                        rw
            /etc                            r
            /etc/grsec                      h
            /etc/gshadow                    h
            /etc/gshadow-                   h
            /etc/ppp                        h
            /etc/samba/smbpasswd            h
            /etc/shadow                     h
            /etc/shadow-                    h
            /etc/ssh                        h
            /home                           h
            /home/guojing
            /lib                            rx
            /lib/modules                    h
            /lib64/modules                  h
            /proc                           h
            /proc/meminfo                   r
            /root                           h
            /root/.bash_history             rw
            /root/.bashrc                   r
            /sbin
            /sbin/gradm                     x
            /sys                            h
            /usr
            /usr/lib                        r
            /usr/local
            /usr/src                        h
            /var
            /var/backups                    h
            /var/log
            -CAP_ALL
            bind    disabled
            connect disabled
    }

可以看到这是一个属于root的角色，可执行文件是/bin/bash，也就是说root可以执行这个文件，而/bin/ls是无法执行的，如果没有定义/bin/ls的subject，那么即便是root账户，也无法使用ls这个命令，Grsecurity是一个白名单的安全工具。

再仔细看上面的root的规则，其实很好理解，使用/bin/bash，这个命令，是对下面的这些命令都有相应的权限，比如对/dev目录有h权限，对/root/.bash_history有读写的权限。这些都是在学习模式里系统自己监测到的，无需手动增加。但还有一些情况没有学习到，这个时候就可以手动添加[^1]。

[^1]: 例如使用redis的时候，经过测试可以使用，但是在使用了一段时间之后，redis变得无法使用，查看了问题之后发现原来redis要持久化的时候，并没有dump.db的权限，所以在这种情况下，手动的增加权限即可。

每一个subject里的可执行文件也分别有自己的权限，权限h也可以被称作模式，Grsecurity包含主题模式和对象模式：

主题模式：

* h: 进程是隐藏的，只有v模式的进程可以查看
* v: 查看h模式的进程
* p: 进程是受保护的，只有k模式的进程能杀死
* k: 可以杀死p模式的进程
* l: 为这个进程打开学习模式
* o: 撤销ACL继承 

对象模式：

* r: 可读
* w: 可写
* o: 可打开
* h: 对象是隐藏的
* i: 这个模式只用于二进制可执行文件
* x: 这个模式代表文件可执行

这样就详细的了解了日志文件的基本信息，便于继续了解。

### Full System Learning ###

Full System Learning称作全系统学习模式，我自己翻译的，这个模式会学习所有执行的操作，以及监测所有的进程活动、文件系统活动以及端口等信息，并生成日志文件，通过日志文件最终生成policy访问规则文件。

打开学习模式：

    # -F 使用全系统学习模式，日志输出到/etc/grsec/learning.logs
    gradm -F -L /etc/grsec/learning.logs

打开之后我们可以在服务器上进行任何操作，但不推荐进行高危操作，如果进行了高危操作，就好比你安装了一个非常强大的防盗门，但是却把钥匙留给了别人，就不存在防盗门了[^2]。

如果需要进行管理员等高危操作的话，最好使用

    gradm -a admin

在使用完毕之后

    gradm -u

恢复到普通用户模式。

如果确定完成了录制，那么我们需要关闭录制功能。

    gradm -D

当操作完成之后，录制的工作也完成了，就可以看到learning.logs有很多命令，我们可以通过这个日志生成需要的规则。

通过以下规则生成policy文件。

    gradm -F -L /etc/grsec/learning.logs -O /etc/grsec/policy

生成完毕后通过

    gradm -E

启动RBAC模式，一般来说可能会出现一些权限的问题，依旧还是需要手动去修改[^3]。如果出现错误，则需要手动的去修改以便能够启动RBAC模式。一般来说，可能是*group_transition_allow*后面的值为空，改为*group_transition_allow root*之类的就行。如果gradm -E命令没有出错的话可以使用以下命令确认RBAC系统是否已经打开。

    gradm -S

[^2]: 在高危操作，以及安装软件等操作的情况下，建议先使用gradm -D关闭RBAC系统，操作完成后再打开。

[^3]: 有提示错误的时候，可能是group_transition_allow后面的值为空。

### Process and Role-Based Learning ###

除了全系统学习模式以外，还有基于进程和规则的学习模式，这个模式非常的简单，使用在配置文件里写如下操作即可。

    # Role: root
    subject /bin/ls l

注意，最后的l是一个小写的L，而不是数字1，使用之后继续开启学习模式：

    gradm -L /etc/grsec/learning.logs -E

使用了/bin/ls之后，使用以下命令生成policy文件：

    gradm -L /etc/grsec/learning.logs -O /etc/grsec/acl

然后将acl文件中的规则拷贝到policy文件中即可。

虽然也可以使用

    gradm -L /etc/grsec/learning.logs -O /etc/grsec/policy

这个命令直接增加到原来的policy文件下面，但依旧推荐使用两个文件，以便出现问题的时候还可以回退。

TIP: 还可以使用*include </etc/grsec/acls>*这种形式管理policy文件。

**任何学习模式都推荐执行大于3到4次**。

### 网络通信 ###

除了基本的学习模式以外，还需要更加深入的了解配置文件，因为机器自动生成的文件，永远无法满足人类的需求，即便非常智能，但还是会有遗漏，例如，手动增加一两个自己需要的权限。

举个非常简单的例子，如果我要配置服务器，在服务器上尝试打开和关闭service多次，并且ping了本地服务多次，那么权限的伪代码如下：

    # 服务器名字： test
    # 操作的用户： guojing

    # Role: root
    基本的规则

    # Role: guojing
    使用sudo
    使用service
    使用ping

但如果是这样，外网访问test这个服务器的ip就被禁止了，因为在学习的时候，并没有允许外网访问，而且在服务器上录制的时候，很多时候不会考虑到外网访问，所以就会出现问题。所以，在学习的时候，就需要保证外网的服务器以及其他各个服务器都能够访问到这个服务器的某些端口，并且学习了*allowed_ip*之后再启用规则，这样外网的某个特定的服务器就能够访问这个test服务器的服务。

这种情形特别适用于内部服务器，例如mysql服务器和redis服务器。web服务器使用内网ip访问这个服务器。

有一种方式是，我在学习模式的时候，使用web服务器多次请求这个内网服务器，Grsecurity会学习到相应的规则，以及被外访问的端口，并且记录下来。这种方式的好处就是简单，坏处就是不可能一次性全部测试到，如果增加一台服务器，就得重新弄。当然，另一种方式是手动的增加一些基本的配置，所以需要深入的了解命令。

使用bind和connect命令可以达到这一点：

开启redis-server的10000端口的访问，使用tcp协议。

    # Role: root
    subject /usr/local/bin/redis-server o {
            /                               h
            /dump.rdb                       rwcd
            /etc                            h
            /etc/localtime
            /proc                           r
            /proc/bus                       h
            /proc/kallsyms                  h
            /proc/kcore                     h
            /proc/modules                   h
            /proc/slabinfo                  h
            /proc/sys                       h
            /run                            h
            /run/redis.pid                  wd
            /temp-21824.rdb                 rwcd
            -CAP_ALL
            bind 0.0.0.0/32:10000 stream tcp
            connect disabled
    }

开启一个erlang的web服务，绑定20000端口

    # Role: root
    subject /usr/lib/erlang/erts-5.9.1/bin/beam.smp o {
            /                               h
            -CAP_ALL
            bind 0.0.0.0/32:20000 stream tcp
            connect disabled
    }

允许netcat监听1024端口到65535端口，也允许使用tcp链接22.22.22.22的5190端口的服务。

    subject /usr/bin/nc o
        bind 0.0.0.0/0:1024-65535 stream tcp
        connect 22.22.22.22:5190 stream tcp

也可以绑定具体的网卡：

    bind eth1:80 stream tcp
    bind eth0#1:22 stream tcp

### 继承 ###

规则之间是可以继承的，继承关系如下：

    user -> group -> default

例如，有规则如下：

    # 假设guojing在dev组

    role guojing u
    role_allow_ip 192.168.1.5

如果有用户使用guojing作为账户，但是不是192.168.1.5的ip中登录了这个服务器，那么这个规则就不适用了。在阻止用户登录之前，会继续找组的规则。

    role dev g
    role_allow_ip 192.168.1.5
    rola_allow_ip 192.168.1.6

如果这个用户ip在其中，那么允许登录，并使用此规则，否则继续找default规则，一般来说default规则权限极少，基本上可以当成无法使用。

### 能力等级制度 ###

在所有的规则中，还可以编写能力等级制度，举例如下：

    # Role: guojing
    subject /bin/init.d o {
            /var/log/syslog                 a
            /var/log/user.log               a
            /var/run
            /var/spool/rsyslog
            -CAP_ALL
            +CAP_SETGID
            +CAP_SETUID
            +CAP_SYSLOG
            bind 0.0.0.0/32:28930 stream dgram ip tcp udp
            connect 8.8.4.4/32:53 dgram udp
            sock_allow_family ipv6 netlink
    }

其中*CAP_ALL*定义了一些能力等级制度，要增加一个能力等级使用+CAP\_XXX，要去掉一个能力，使用-CAP\_XXX，从上面的例子可以看出，其中去掉了CAP\_ALL，增加了CAP\_SETGID、CAP\_SETUID、CAP\_SYSLOG等权限。/bin/su这个命令会使用CAP\_SETGID、CAP\_SETUID。

### 总结 ###

至此，已经了解了大部分的Grsecurity日志编写中遇到的问题以及一些关键的字段，这些字段能够保证我们可以轻易的读懂policy文件，并且进行一些简单的修改，对于一个subject里需要使用的程序以及权限，最好使用学习模式来生成，而不要自己去修改，因为人是很难编写一个进程的所有需要的文件以及权限的，但我们可以手动增加一些目录。

在使用Grsecurity期间，我自己也遇到一些问题，因为Grsecurity的验证方式非常的严格，所以配置错了，只能在物理服务器上去disable掉Grsecurity，所以最好的方式是，在一个ssh里面打开Grsecurity，并且保证至少有一个ssh会话是可以随时打开和关闭的，也就是说，如果测试Grsecurity，打开了RBAC规则，不要关闭所有的ssh窗口，在测试所有的应用通信没有问题之后，再关闭所以的会话，否则只能去物理机关闭了。

在配置Grsecurity的时候，打开学习模式，在此根据需要，确保有一个用户可以登录到root[^4]，root禁止ssh，但可以通过其他用户登录，这样可以远程的关闭掉Grsecurity[^5]，安装软件并且进行一些操作，在操作完成之后，再开启基于规则的学习模式之后，打开Grsecurity即可。

[^4]: 如果对自己的安全配置极度有信心，那么可以不这么使用，以免有后门，但使用Grsecurity之后，有用户可以登录到root其实已经相当安全，因为root可执行的文件也被限制。

[^5]: 一个黑客知道你的机器的所有密码，并且还知道Grsecurity密码，这就已经不是安全问题了。

可以把整个安全模型定义如下，『->』符号表示可以访问，括号内表示一些基本信息，例如IP和是否安装了Grsecurity：

    # 假设有一个跳板服务器A可以访问数据库服务器
    跳板服务器A（192.168.0.1 Grsecurity）->数据库服务器（Grsecurity）

    # 数据库服务器（Grsecurity）
    # 假设数据库服务器用用户a、b、c
    # 只允许ip 192.168.0.1 访问
    # 开启8888数据库服务器端口访问，并且只允许web服务器访问
    a（sudo）->b（sudo）->c（sudo）->root（只能操作Grsecurity）
    # a什么都做不了
    # b在home目录里做操作
    # c只能重启service
    # root只能操作Grsecurity

    # 跳板服务器A（Grsecurity）
    只允许固定ip访问，只允许使用ssh命令

    # Web服务器 -> 数据库服务器（Grsecurity）
    # Web服务器本身没什么数据
    # 通过内网ip和数据库服务器进行交互

建议稳定的服务器使用Grsecurity，这里稳定的意思是不会做大量的更新，例如Web服务器就不要使用了，因为要经常上线代码，经常安装一些软件，使用Grsecurity会造成不少的麻烦，每次操作可能都要重新生成和学习规则。所以只提供数据库的服务器使用Grsecurity是非常好的。

另外如果觉得开启Grsecurity学习模式可能不能保证所有的端口以及软件都使用，可以在线上开启学习模式一天，保证所有的应用都没有问题之后，再生成policy文件，这样可以保证应用不会出问题。

以上的安全模型就保证了跳板服务器A可以ssh，但其他什么事情都不能做，Web服务器只能通过某个端口和数据库服务器进行交互，但不能ssh。即便跳板服务器被root了，也只能ssh，其他的什么都做不了，即便知道了数据库服务器IP的密码，也什么都做不了，只有知道了使用所有的用户密码才能进行高危操作。

如果知道了所有用户的密码，那就没什么办法了。。。