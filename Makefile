cafe:
	jekyll build
	ghp-import _site -b gitcafe-pages -r cafe

blog:
	jekyll build
	ghp-import _site -b master -r html

clean:
	sh export.sh

pub:
	make cafe
	make blog

