## 导出 ##

很多人fork我的博客以使用这个皮肤，我提供了一个工具，可以使用`Make clean`导出到目录的new\_site，为干净的文件目录。

## 关于 ##

这是我的博客，你可以fork我的代码，从我的代码里面你可以轻松的创建一个博客。也就是说，你可以fork然后直接用我的皮肤。

但是，有两点希望你`注意`：

1. 删掉我的博客文章，因为这是我的博客。
2. 删掉我的统计信息，错误的统计会让我奇怪。

上面两点`请你注意`，一是你留着也没意思，二是我会觉得不爽，感觉不被尊重。如果你使用了我的代码，你应该是一个技术人员，你知道不被尊重的感觉，也希望以后能被人尊重，对吧。

有一点请你`了解`，但你有权利不做：

1. 请保留我的Copyright，可以写成皮肤由我设计。
2. 尊重我作为最原始作者的劳动成果。

## 部署 ##

根据这些步骤，你可以很简单的部署到自己的Github上。

1. 点击页面右上角的`fork`或下载源代码到电脑中。
2. 删除_posts下的文章。
3. rm -rf _posts。
4. mkdir _posts。
5. git push到自己的项目中。

根据上面的步骤你就可以正式使用此博客了。

## 我默认关闭了评论功能 ##

开启:

注释掉_layouts/post.html

	<!--
	<div class="comments {{ page.categories }}_comments_css">
	<div id="disqus_container"> 
    	{% if page.not_comment %}
    	<span class="comment">该文章已关闭评论。</span>
    	{% else %}
    	<a href="#" class="comment" onclick="return false;">点击评论或查看评论。</a>
    	{% endif %}    
    	<div id="disqus_thread"></div>
	</div>
	</div>
	-->

## 替换评论key ##

如果你不替换，你会评论到我的博客url下面，不会在你的评论系统你出现。这里使用的评论系统是disqus，你可以在config里配置评论申请的key。

    author:
        name:         Your Name
        twitter:      twitter.com/youraccount
        key:          your disqus key

## 如何使用 ##

如何创建Github Pages并且写东西，而且是很geek的方法，请看:

1. [使用Github Pages建独立博客](http://beiyuu.com/github-pages/)
2. [Jekyll常用函数和技巧](http://guojing.me/blog/2012/11/14/jekyll-and-github-tec/)

## 一些变量 ##

在文章的头部有一些变量可以加，加了之后模板会有相应的展现。值为任何都行，只要有即可。

1. not_comment 关闭评论
2. private 私有日志

tips: private私有日志只是预发布作用，实际上在github上还是可以看到的。

## Retina ##

1. 该皮肤支持rmbp以及Retina屏及分辨率。

## 一些工具 ##

有一些工具快速帮你写日志。

1. [Sublime Text 2快速写日志插件](https://github.com/GuoJing/SublimeText2Plugins/blob/master/Jkblogger.py)


[![Bitdeli Badge](https://d2weczhvl823v0.cloudfront.net/GuoJing/guojing.github.com/trend.png)](https://bitdeli.com/free "Bitdeli Badge")

