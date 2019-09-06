jekyll build
ghp-import _site -b master -r html -p
git add -A
git ci -am'auto commit'
git push origin dev
