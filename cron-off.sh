git pull origin master
echo -n "" > stamp.json
./tweet.sh tweet "Clocked out @ "$(date +"%H:%M")" http://github.com/84115/twooo" >> stamp.json 
git push origin master
