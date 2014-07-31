# 简单的导出干净博客的工具
# 默认保存在$HOME/new_site目录

echo '************************************************'
echo Blog will save to new_site
echo '************************************************'

echo clean path new_site...
rm -rf new_site
mkdir new_site

echo use git archive to export...

git archive master | tar -x -C new_site

cd new_site

echo remove _posts

rm -rf _posts
mkdir _posts

echo remove about
rm -rf about

echo remove release
rm -rf release

echo remove downloads
rm -rf downloads

echo remove guestbook
rm -rf guestbook

echo remove links
rm -rf links

echo regenerate CNAME
rm -rf CNAME

echo remove images
rm -rf images

echo remove libs
rm -rf libs

touch CNAME

echo remove README
rm -rf README*

touch README.md

echo Auto generate README > README.md

echo Done

echo You still need to do

echo '------------------------'
echo 1. change _config.yml
echo 2. change CNAME
echo 3. push to your branch
echo Thank you!
