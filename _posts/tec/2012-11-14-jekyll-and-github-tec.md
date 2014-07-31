---
layout:    post
title:     Jekyll常用函数和技巧
category:  tec
description: Jekyll小技巧...
tags: jekyll life code github tips dev
---
Jekyll和Github做博客很爽，基本的需求也都可以满足，这里记录一些小技巧，留有以后可以查看，说不定也可以帮助后来的人。

### 函数 ###

#### 循环输出n篇文章 ####

	for post in site.posts limit:n
	endfor

#### 倒序循环输出n篇文章 ####

	for post in site.posts offset:n limit:n
	endfor

#### 日期 ####

	post.date | date:"%Y年%m月%d日"

#### 分页输出 ####

	for post in paginator.posts
		something
	endfor

#### 分页 ####

	if paginator.previous_page
		if paginator.previous_page == 1
			//to the root page
		else:
			"page" +  paginator.previous_page
		endif
	endif

	if paginator.next_page:
		"page" + paginator.next_page
	endif

**Tips：** 分页只有在index.html有用，也可以在categorys下的index.html有用。

#### 显示页数的分页 ####

	for post in (1..paginator.total_pages)
		if post == paginator.page
			//is current page
		else
			"page" + post
		endif
	endfor

#### 文章页显示上一篇和下一篇 ###

	if post.previous
		<a href="page.previous.url">post.previous.title</a>
	endif

	if post.next
		<a href="page.next.url">post.next.title</a>
	endif

### 技巧 ###

#### 自定义变量 ####

页面可以自定义变量，在文章的md文件的头部可以自定义，则可以在模板里使用。但是需要先判断是否存在，比如可以创建一个not_comment来自制一个关闭评论的功能。

#### 按category显示文章 ####

	for post in site.categories.blog
	endfor

#### 模板继承 ####

放在目录下的_include/xxx.html

	{ % include xxx.html % }

上面代码没有空格。

### 代码&文档 ###

1. [可以参考我的本网站的代码](https://github.com/GuoJing/guojing.github.com)
2. [Template Data](https://github.com/mojombo/jekyll/wiki/Template-Data)
