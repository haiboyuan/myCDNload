ps -ef|grep testData.sh |grep -v grep |awk '{print $2}' |xargs kill -9
ps -ef|grep myload |grep -v grep |awk '{print $2}' |xargs kill -9
ps -ef|grep "./ab" |grep "runUrlList" |grep -v grep |awk '{print $2}' |xargs kill -9
sleep 5
nohup ./testData.sh  &
