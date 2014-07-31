---
layout:    post
title:     Jekyll Tags Categories Archive 实现
category:  tec
description: Jekyll Tags Categories Archive的简单实现...
tags: jekyll tags categories archive 实现 code
---
最近研究了一下Jekyll的Tags、Categories和Archive实现，官方文档里写的很模糊，但仔细看还是能看出倪端，YAML格式的数据说简单也简单，但整起来还是有点麻烦的，直接上代码吧。

	<div class="tagcloud">
	for tag in site.tags
	<a href="#tag[0]">tag[0]</a>
	endfor
	</div>

	<ul class="archive">
		for tag in site.tags
		<li class="year" id="tag[0]">tag[0] tag[1].size)</li>
		for post in tag[1]
		<li class="item">
			<time datetime="post.date | date:"%Y-%m-%d"">
			post.date | date:"%Y-%m-%d"</time>
			<a href="post.url" title="post.title">post.title</a>
		</li>
	endfor
	endfor
	</ul>

Categories的代码逻辑也是一样，只要稍微改一下for的变量即可。

简单的说一下（包括Tags和Categories），site是Jekyll的网站对象，是个一直存在的全局的对象，其中编译之后自己会有site.tags和site.categories两个对象，这两个都是YAML的格式化数据，是列表的的组合，其第一个值是相应的结果，比如tag或者分类，第二个值是列表，是这个tag或者这个分类下的所有文章，所以只要遍历一下即可。

Archive稍微有些不同，需要定义一个变量，循环所有文章，并把年份拿出来做组合索引。

	<ul class="archive">
	for post in site.posts
  	capture y post.date | date:"%Y" endcapture
  	if year != y
    	assign year = y
    	<li class="year">y</li>
  	endif
  	<li class="item">
  		//和上面一样
  	</li>
	endfor
	</ul>

这里关键的是capture对象并获得年份，然后根据年份Group即可，其实这里也可以稍微修改一下，改为月份也很简单。只要把date格式化改一下即可。

这里面有参考官方的sample和代码，具体这几个文件可以参考我的Github。

1. [Tags](https://github.com/GuoJing/guojing.github.com/blob/master/tags.md)
2. [Categories](https://github.com/GuoJing/guojing.github.com/blob/master/categories.md)
3. [Archive](https://github.com/GuoJing/guojing.github.com/blob/master/archive.md)
