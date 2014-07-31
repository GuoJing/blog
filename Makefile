cafe:
	jekyll build
	ghp-import _site -b gitcafe-pages -r cafe -p

blog:
	jekyll build
	ghp-import _site -p -n

clean:
	sh export.sh

pub:
	make cafe
	make blog

