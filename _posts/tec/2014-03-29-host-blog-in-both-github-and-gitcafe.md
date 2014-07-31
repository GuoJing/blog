---
layout:    post
title:     同时部署博客到GitHub/GitCafe
category:  tec
description: 部署博客到GitHub/GitCafe...
tags: blog jekyll host gitcafe github
---
昨天[@lepture](http://lepture.com)在推上和我说我博客的问题，什么中文url啊速度慢之类的，后来我回复道因为我的博客部署在GitHub上，所以难免会被墙和速度慢。然后lepture给我推荐了一个方法，就是同时部署博客到GitHub和GitCafe。如何做这个，原始的帖子在此[同时使用 GitHub 与 GitCafe 托管博客](http://ruby-china.org/topics/18084)。

之前不知道为什么，虽然我不会Ruby，但其实还是逛到了那个帖子，好像是lepture自推了一把。但那个时候我没有弄，一方面是我比较懒，反正也没什么人看所以也没弄，另外对于GitCafe来说，因为是国内的服务商，总觉得有些不信任的感觉，比如不知道会不会突然就倒闭了或者让用户转移数据之类的。自然国外也会有这样的问题，怎么说，技术方面，总是有种国外的月亮圆的感觉。而且相比之下，国外的节操也比较高罢。

### Huggle ###

对我自己而言，我还是使用GitHub作为默认的博客，而GitCafe做镜像，不仅仅是概念上如此，连代码也是。GitHub上的我的博客，里面还是Jekyll代码，而生成静态网站由GitHub来做，而GitCafe上的代码纯粹是使用Jekyll生成的_site目录上传的，仅仅是html。其实不好，会引发很多问题，主要是本地文件版本管理。这个时候，我觉得其实[hugo](https://github.com/spf13/hugo)这个应用也许更好，这个是用Go语言实现的静态博客生成器，其目的更单纯，就是根据某种规则生成静态文件，纯html，这倒是能更好部署在两个地方。

超哥实现了一个hugo+livereload的一个开发库叫[Huggle](http://ktmud.github.io/huggle/)，相比这种情况下，我觉得更好写博客了。不过因为我之前Jekyll博客已经写了很多了，换静态博客又得重新写模板，虽然我的theme已经封装的可以了，但还是懒得弄。Jekyll[^1]倒也没什么不好就是了。

[^1]: 有时候我会想静态博客足够迁移，不像带数据库的部署起来麻烦，可是各种生成器没有统一的标准，换来换去还是要换模板规则，也挺麻烦的。

### GitCafe ###

扯了这么多蛋说回正题，倒也没什么难度，主要是细心，可以看看GitCafe的帮助文档[如何创建Page](https://gitcafe.com/GitCafe/Help/wiki/Pages-相关帮助#wiki)，里面创建Page说的很详细了，创建完最好弄一个随便的index.html测试一下，看看有没有什么问题。然后在GitCafe里设置自定义域名即可。由于我博客默认还是走GitHub，只是针对国内用户走GitCafe。域名是使用DNSPOD做解析的，解析这方面，在DNSPOD的相应的域名里里选择『添加记录』即可，添加记录里『线路类型』选择电信、联通、国内，总之什么都好。按照你自己喜欢的来。

### ghp-import ###

这里可以使用一个叫[ghp-import](https://github.com/davisp/ghp-import)的库，用来生成静态文件，我觉得这个脚本写的不太好用，毕竟要把当前目录的文件都给删了，然后重新生成一些，不知道有没有更好的解决办法。但这个工具还是ok，可用的：

    ghp-import _site -b gitcafe-pages -r cafe -p

-r表示remote，-b表示branch，还算好理解。但**一定一定注意**这个工具还挺evil的，会把你的工作目录给搞乱。这个工具好处是，如果你GitHub的Blog纯静态的话，而且GitCafe也纯静态的话，其实挺好用的。否则可能会把Jekyll的一些代码也删掉，所以使用起来还是小心为好。

### AND ###

其实弄起来还是挺麻烦的，我自己还有一个[Linux内核学习笔记](/linux-kernel-architecture/archive/)，这个项目是另一个GitHub的项目，利用的GitHub项目的Pages的一个新的博客，虽然看上去是和我的主博客一样。这就有另外一个问题，设置了上面的域名解析之后，国内访问这个网址会404，而国外IP没有问题，所以为了解决这个问题，只好也把这个项目给挪到GitCafe上去了。所以以后每次写博客，都要build两次，还真是折腾。

所以，写博客就变成：

1. 写博客的markdown。
2. 提交到GitHub。
3. 使用ghp-import提交到GitCafe。

对于洁癖患者而言，还有一个挺郁闷的问题[^2]，使用ghp-import会有很多git改动的diff，但是又不能commit，很是钻心的难受。所以，最好还是全host静态文件得了。不过速度快，确实心情好，这个没办法。如果觉得这个过程麻烦，也可以看lepture的那个帖子写的Makefile也成，那会减少不少工作。

[^2]: 因为我GitHub是Jekyll，GitCafe是html。

### LAST ###

最后几天用下来感觉ghp-import还是不太好用，特别是我这种GitHub是Jekyll，GitCafe是html的情况，ghp-import最适应的情况应该是项目本身和gh-pages不冲突，最好是纯静态页面，可以在多个地方都部署。我本身的博客的.git/config里的master是指向github的，而有个cafe的分支指向GitCafe，在这之间轮回换，很容易搞出GitCafe的问题，如果只是改改文字，应该没有什么问题，但是改结构，GitCafe那边很容易出现超多的冲突。这个时候我觉得最好的解决办法就是push -f了。

另外如果一不小心弄坏了，比如改了很大的[结构路径](https://github.com/GuoJing/guojing.github.com/commit/f047e553a1fdb77ab012602daeea7cedfa591129)[^3]，最简单还是把GitCafe上的分支删了重来。

至于喜不喜欢折腾，真的，就看你在速度和麻烦之间怎么取舍了。

[^3]: 比如这个提交其实改动很大，如果Jekyll使用了paginator，则会生成很多的分页静态文件，而我首页不需要，删除之后，很多文件被删了，html文件之间很容易出现冲突。
