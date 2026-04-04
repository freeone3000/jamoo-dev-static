---
title: Jasmine Moore's Personal Website
layout: index
---

<section markdown="1">
## Publications
- [TextWorld: A Learning Environment for Text-based Games (arxiv)](https://arxiv.org/pdf/1806.11532)
</section>

{% comment %} Build a category tree from posts {% endcomment %}
{% assign posts_by_categories = site.posts | where_exp: "post", "post.categories.size > 0" | sort: "date" | reverse %}
{% assign category_tree = "" | split: "" %}
{% for post in posts_by_categories %}
  {% if post.categories %}
    {% assign cat_path = post.categories | join: "||" %}
    {% unless category_tree contains cat_path %}
      {% assign category_tree = category_tree | push: cat_path %}
    {% endunless %}
  {% endif %}
{% endfor %}

{% comment %} We then use the post *path* to get the level 1 and level 2 categories,
since these form part of the path. {% endcomment %}
{% assign sorted_paths = category_tree | sort %}
{% assign level1_categories = "" | split: "" %}
{% for path in sorted_paths %}
  {% assign cats = path | split: "||" %}
  {% assign level1 = cats[0] %}
  {% unless level1_categories contains level1 %}
    {% assign level1_categories = level1_categories | push: level1 %}
  {% endunless %}
{% endfor %}

{% comment %}And now we can render the tree. {% endcomment %}
{% for level1 in level1_categories %}

<section markdown="1">

## {{ level1 }}

  {% assign level2_categories = "" | split: "" %}
  {% for path in sorted_paths %}
    {% assign cats = path | split: "||" %}
    {% if cats[0] == level1 and cats.size > 1 %}
      {% assign level2 = cats[1] %}
      {% unless level2_categories contains level2 %}
        {% assign level2_categories = level2_categories | push: level2 %}
      {% endunless %}
    {% endif %}
  {% endfor %}
  
  {% for level2 in level2_categories %}
<section markdown="1">

### {{ level2 }}

    {% for post in posts_by_categories %}
      {% if post.categories[0] == level1 and post.categories[1] == level2 %}
- [{{ post.title }}]({{ post.url | relative_url }}) ({{ post.date | date: "%Y-%m-%d" }})
      {% endif %}
    {% endfor %}

</section>

{% comment %} level2 section {% endcomment %}
  {% endfor %}
  
  {% comment %} Handle level1-only posts (no level2) {% endcomment %}
  {% for post in posts_by_categories %}
    {% if post.categories[0] == level1 and post.categories.size == 1 %}
- [{{ post.title }}]({{ post.url | relative_url }}) ({{ post.date | date: "%Y-%m-%d" }})
    {% endif %}
  {% endfor %}
</section> {% comment %} level1 section {% endcomment %}
{% endfor %}

<section markdown="1">
## Pages
- <a href="{{ '/assets/pdf/SearchFocus2025.pdf' | relative_url }}" rel="external opener me" target="_blank">Resume</a>
{% for page in site.pages %}
  {% if page.layout != "index" %}
- [{{ page.title }}]({{ page.url | relative_url }})
    {% endif %}
{% endfor %}
</section>

