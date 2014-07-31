---
layout:    post
title:     Sublime Text 2插件开发Tips
category:  tec
description: Sublime Text 2插件开发Tips
tags: sublime text plugin tips simple
---
用了几天Jekyll和Github搭建和写博客，觉得很爽，因为Jekyll支持的是Markdown，而Markdown又很简单，又是文件存储，非常的爽，不需要数据库，还可以备份和同步到Dropbox。不仅仅如此，这个世界世界上基于Jekyll开发并提供免费host的服务商太多了，ruhoh就是一个，你仅仅需要把你的静态文件移过去即可。

说了这么多赞美Jekyll的废话，和Sublime Text 2插件开发有什么关系？实际上是因为我想写博客，而每次头部都要定义一些自定义内容，而且是Jekyll必须的，每次都要拷贝粘贴，非常麻烦，所以我就想写一个简单的快捷键来做这个事情。

**好吧，很简单，快捷键，输入标题，生成一个新文件，博客内容为空。**这么简单是不是？不过还是从简单的开始。

### 创建一个Plugin ###

`Tools` -> `New Plugin`，得到一个新的插件，代码如下。

	import sublime, sublime_plugin

	class ExampleCommand(sublime_plugin.TextCommand):
		def run(self, edit):
			self.view.insert(edit, 0, "Hello, World!")

保存到`Packages` -> `User` -> `xx.py`即可，xx可以是插件的名字，如上，可以为__Example.py__也可以叫其他的，没关系。

__Tips__: ExampleCommand是一个命名规则，比如要以**\*\*Command**为Class名，并继承sublime_plugin的对象。

保存之后，打开命令行（control+\`），输入`view.run_command("example")`即可运行刚才的插件，这个时候可以看到运行的命令名称是前面写的command名称。运行之后会发现在当前buffer里面插入了一个**Hello World**。

### 代码分析 ###

其实这个代码很简单，不复杂，使用python，简单易懂。但是里面包含了很多信息。import sublime和sublime plugin没什么好说的，从下面的代码来看。

    class ExampleCommand(sublime_plugin.TextCommand):

这里包含了几个信息，前面的提到过，**\*\*Command**命名，然后面继承，其实还有一个就是TextCommand，这个是你的插件的命令形式，有三种。

1. ApplicationCommand
2. WindowCommand
3. TextCommand

ApplicationCommand是应用程序，WindowCommand就是窗口了，TextCommand就是普通的命令行，用run_command命令启动。我这里想实现的是使用一个快捷键，然后打开一个小的命令窗口，然后输入代码，得到内容，然后插入到当前buffer。

这里需要了解两个对象:

* window
* view

window就是window的实例，window包含多个views，view是当前buffer的实例，比如要在当前buffer插入字符串，则可以使用view.insert方法，而window可以获得多个view。

### 开始 ###

所以我们很简单的，继承一个WindowCommand来做一个很简单的小的输入和输出。样子就是这样。

<img src="/images/2012/slp01.png" style="width:600px">

输入一些标题，生成一串字符串，这是Jekyll需要的：

	---
	layout:    post
	title:     Sublime Text 2插件开发Tips
	category:  blog
	description: Sublime Text 2插件开发Tips...
	---

目的是要自动生成，不要每次都手写，迅速而简单。

ok，代码如下。

    import sublime, sublime_plugin

	class JkbloggerCommand(sublime_plugin.WindowCommand):
		title = 'default blogger'
		layout = 'post'
		category = 'blog'
		description = ''

		def run(self):
			fname = ''
			def done(commands):
				pass

			self.window.show_input_panel("Input the title:",
				fname, done, None, None)

其实这个就很简单了，继承WindowCommand，然后定义一个run方法，插件环境会自动运行类下的run方法，代码就不多解释了，run方法调用了window对象的show_input_panel, 参数分别为提示文案、默认值、处理方法等。

运行run之后输入文案之后会自行调用done方法。在这个结构完成之后，我们写详细代码就可以了。

前面说了view是buffer，window是窗口，我们需要一个新的buffer来做事情：

    v = self.window.new_file()

new_file返回一个新的view对象。

    v.insert(e, 0, text)

使用view的insert方法可以插入内容到当前view中，但是第一个参数是e，官方文档写的edit，是一个sublime的view的edit对象。

    e = v.begin_edit()

通过begin_edit方法可以活动该对象。

这样实际上window，view，edit的对象的关系就很清楚了。window > view > edit。

### 快捷键 ###

绑定快捷键很简单，[Sublime Text 2 Tips](http://guojing.me/blog/2012/11/06/sublime-text-2-tips/)这篇文章说明了如何绑定快捷键。只要在Default里增加一行快捷键设定就可以了，我设定的是command+m。

### 工具栏 ###

写完之后可以显示到工具栏里，这个就更有意思了，如果不会用快捷键，也可以用鼠标。在Packages的User的目录下创建一个`Main.sublime-menu`文件，如果有就直接写。

    [
        {
            "id": "tools",
	        "children":
	        [
	            {"id": "wrap"},
	            { "command": "jkblogger" }
	        ]
	    }
	]

写了这行代码之后，重启就能够看到我们的命令出现在工具栏了。当然，同样有几种可以选择。

1. Main.sublime-menu
2. Side Bar.sublime-menu
3. Context.sublime-menu

Main不用说了，Side Bar也都知道，Context是右键内容。

有关进程的章节和处理结果的章节在样例中并没有实现，只是作为插件开发的时候的测试，可能会有某些内容不完整。

### 进程 ###

有时候插件需要做一些远程处理，这个时候不要去打扰用户的使用，而在后台去做操作，需要创建一些进程，我们可以创建一个方法继承`threading.Thread`。

    class SampleApiCall(threading.Thread): 
    	def __init__(self, sel, string, timeout):
    		self.sel = sel
    		...
    		...

在插件中可以使用urllib、urllib2、threading。可以使用循环来出发进程，我们可以回到Command类的run方法，写下如下代码。

	threads = []  
	for sel in sels:  
    	string = self.view.substr(sel)  
	    thread = SampleApiCall(sel, string, 5)  
	    threads.append(thread)  
	    thread.start()

### 处理结果 ###

处理结果的代码很简单，同样要注意view和edit。

    view.sel().clear()
    edit = view.begin_edit('sample')
    self.handle_threads(edit, threads, braces)

handle_threads代码如下。

	def handle_threads(self, edit, threads,
		braces, offset=0, i=0, dir=1):  
	    next_threads = []  
	    for thread in threads:  
    	    if thread.is_alive():  
        	    next_threads.append(thread)  
            	continue  
	        if thread.result == False:  
    	        continue  
    	    //do something
	    threads = next_threads

如果进程还live，那么我们就先等等，否则处理进程。

### 发布 ###

发布可以用大名鼎鼎的[Package Control](http://wbond.net/sublime_packages/package_control)就可以了，它简单易懂还方便安装，但是可能需要实现其api才能使用，毕竟私自修改目录和快捷键还是比较麻烦的，最好还是和用户首先声明。

### 结语 ###

其实写一个Sublime Text 2插件也不是很难，主要是要了解其原理和结构，好在python简单易懂，命令行也能print所有你需要的东西，比如如何从window里面拿到view，如何创建一个edit对象，都是print dir()出来的，也可以使用help和doc，python就是这点非常好。如果实在不了解，还可以去[官方API文档](http://www.sublimetext.com/docs/2/api_reference.html)去查看相关的帮助，文档说的也算是比较详细，但需要认真仔细的寻找。

### 代码 ###

1. [Github](https://github.com/GuoJing/SublimeText2Plugins/blob/master/Jkblogger.py)

### 参考 ###

1. [官方API文档](http://www.sublimetext.com/docs/2/api_reference.html)
2. [How to Create a Sublime Text 2 Plugin](http://net.tutsplus.com/tutorials/python-tutorials/how-to-create-a-sublime-text-2-plugin/)
3. [Sublime Text 2 — open file using only keyboard](http://superuser.com/questions/467693/sublime-text-2-open-file-using-only-keyboard)
4. [How can I filter a file for lines containing a string in Sublime Text 2?](http://superuser.com/questions/452189/how-can-i-filter-a-file-for-lines-containing-a-string-in-sublime-text-2/452190#452190)
