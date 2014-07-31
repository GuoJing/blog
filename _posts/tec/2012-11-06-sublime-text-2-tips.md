---
layout:     post
title:      Sublime Text 2 Tips
category: tec
description: Sublime Text 2 Tips
tags: sublime tips plugin dev
---
最近尝试使用Sublime Text 2这款大家都说很好用的新编辑器里的神器。虽然我自己一般使用vim或emacs而且每款编辑器都用了不短的时间了，但是还是对这种被开发者叫为神器的编辑器很好奇，最近尝试了一下，总体来说还是不错的。

对我来说编辑器最重要的是快捷键、命令输入、分屏和快速在几个分屏区域上跳转，Sublime确实做到了，但是总有一些小问题，这里搜集一些简单的tips，会陆续更新。

### 快捷键 ###

在多个分屏的区域上跳转，Mac OS上好像有问题，默认的是control+1、2、3、4，但是实际上你会发现这个并不能使用。解决方法只有修改键盘的绑定了。

`Sublime Text 2` -> `Preferences` -> `Key Bindings - User` 里面修改。

也可以在`Key Bindings - Default`里修改，我是直接在Default里把focus group这个快捷键从control改成了alt。不知道是哪个键，可以通过轨迹纪录来找。

也可以自己在文件中找，Mac OS下的文件地址在~/Libary/Application Support/Sublime Text 2/Packages/User/Default (OSX).sublime-keymap，其他的系统也有相应的文件。

### 记录轨迹 ###

当你想要自己自定义快捷键的时候，又发现不知道该怎么用，比如我想自定义按shift+T就能插入某个字符的话，或者实现某个菜单的命令又不知道的话，可以用录制的方式。

`View` -> `Show Console`可以打开命令模式，使用`sublime.log_commands(True)`命令可以记录你的一举一动，然后就可以自定义快捷键之类的了。比如上面我的需求，我先纪录下来命令，然后再去Default里修改键位。

[有关记录和绑定的官方文档](http://docs.sublimetext.info/en/latest/customization/key_bindings.html)

上面两个tips应该能够帮我们解决大部分的快捷键的问题。：）

### 插件 ###

插件开发可以用python，所以说python是最容易让人国际化的语言了，简单实用性能还ok，所以python应该多学习学习。

插件目录可以放在`Packages/<插件名>/`下，或者通过`Tools` -> `New Plugin`创建一个新插件，通过`view.run_command("sample")`命令运行插件。

[插件开发专门页](/blog/2012/11/09/sublime-text-2-plugins-tips/)

[有关插件相关的官方文档](http://docs.sublimetext.info/en/latest/extensibility/plugins.html)

剩下的以后再补充。
