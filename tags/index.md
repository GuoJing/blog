---
layout:  page
title: 标记
description: 标记
---
散落的贝壳，像海的记忆：

<div class="tagcloud">
{% for tag in site.tags %}
{% capture c %} {{ "tag0" }} {% endcapture %}

{% if tag[1].size > 3 %}
{% capture c %} {{ "tag1" }} {% endcapture %}
{% endif %}
{% if tag[1].size > 10 %}
{% capture c %} {{ "tag2" }} {% endcapture %}
{% endif %}
{% if tag[1].size > 20 %}
{% capture c %} {{ "tag3" }} {% endcapture %}
{% endif %}
{% if tag[1].size > 40 %}
{% capture c %} {{ "tag4" }} {% endcapture %}
{% endif %}

<span class="{{ c }}"><a href="#{{ tag[0] }}">{{ tag[0] }}</a></span>
{% endfor %}
</div>

<ul class="archive">
	{% for tag in site.tags %}
	<li class="year" id="{{ tag[0] }}">{{ tag[0] }} ({{ tag[1].size }})</li>
	{% for post in tag[1] %}
	<li class="item">
		<time datetime="{{ post.date | date:"%Y-%m-%d" }}">{{ post.date | date:"%Y-%m-%d" }}</time>
		<a href="{{ post.url }}" title="{{ post.title }}">{{ post.title }}</a>
	</li>	
	{% endfor %}
	{% endfor %}
</ul>