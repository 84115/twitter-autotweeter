git pull origin master
echo -n "" > stamp.json
./tweet.sh tweet "Clocked in @ "$(date +"%H:%M")" http://github.com/84115/twooo" >> stamp.json 
git add .
git commit am "Clocked in @ "$(date +"%H:%M")""
git push origin master
