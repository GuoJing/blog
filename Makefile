cafe:
	jekyll build
	ghp-import _site -b gitcafe-pages -r cafe -p

blog:
	jekyll build
	ghp-import _site -b master -r html -p 

clean:
	sh export.sh

pub:
	#make blog
	git add -A
	git ci -am'auto commit'
	git push origin dev

