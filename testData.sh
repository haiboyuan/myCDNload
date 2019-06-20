#!/bin/bash

#deploy data
#./myload.sh  deploy -t hpc_ats -n  1000000 -d "1K:100%"  
#./myload.sh  deploy -t hpc_ats -n  300000 -d "50K:100%"  
#./myload.sh  deploy -t hpc_ats -n  200000 -d "256K:100%" 
#./myload.sh  deploy -t hpc_ats -n  150000 -d "512K:100%" 
#./myload.sh  deploy -t hpc_ats -n  100000 -d "1M:100%" 
#./myload.sh  deploy -t hpc_ats -n  20000 -d "10M:100%" 
#sleep 60
#./myload.sh  deploy -t ats -n  150000 -d "512K:100%" 
#./myload.sh  deploy -t fc_squid -n  150000 -d "512K:100%"

#run
TEST_DEST_IP="10.20.64.203"
RUN_URL_LIST=$(dirname $0)/urlDir/runUrlList.txt
#CONCURRENT_NUM=(100 500 1000)
CONCURRENT_NUM=( 100 )
FILE_SIZE_RANGE_ALL_TEST_NUM=( 1K\|-\|0\|1000000\|2 256K\|-\|0\|100000\|2 1M\|-\|0\|100000\|2)   #fileSize|Range|MissRatio|allNum|loopTimes, "-"for Range means no range
#FILE_SIZE_RANGE_ALL_TEST_NUM=( 1K\|-\|0\|1000000\|3)   #fileSize|Range|MissRatio|allNum|loopTimes, "-"for Range means no range
#WAF_URL_RATIO_LISTS=(0 5 10 30 50 100)
WAF_URL_RATIO_LISTS=(0)
#CACHE_TYPE=(ats nginx_ats nginx_lua_ats hpc_ats hpc_tfs fc_squid sr_ats hpc_cos_ats)
#CACHE_TYPE=( hpc_ats_c hpc_ats_lua )
CACHE_TYPE=( hpc_ats_lua )

for cacheType in ${CACHE_TYPE[@]};do
    #start related service
    case $cacheType in
        ats)
            ;;
        hpc_tfs)
            ;;
        fc_squid)
            ;;
        hpc_rfs)
            ;;
        hpc_ats_lua)
            python /opt/truck/remote.py  call -H ${TEST_DEST_IP} -c "cd /usr/local/hpc/conf/vhost;cp -rf hpcc_load_lua.conf.bk hpcc_load_lua.conf;rm -f hpcc_load_c.conf;/usr/local/hpc/sbin/nginx -s stop;sleep 1;/usr/local/hpc/sbin/nginx"
            while [ 0 -ne $? ];do
                sleep 10
                python /opt/truck/remote.py  call -H ${TEST_DEST_IP} -c "cd /usr/local/hpc/conf/vhost;cp -rf hpcc_load_lua.conf.bk hpcc_load_lua.conf;rm -f hpcc_load_c.conf;/usr/local/hpc/sbin/nginx -s stop;sleep 1;/usr/local/hpc/sbin/nginx"
            done
            sleep 30
            echo "" >> $(dirname $0)/resultDir/allTestResult.csv
            echo "\"#cacheType is $cacheType\"" >> $(dirname $0)/resultDir/allTestResult.csv
            cacheType="hpc_ats"
            ;;
        hpc_ats_c)
            python /opt/truck/remote.py  call -H ${TEST_DEST_IP} -c "cd /usr/local/hpc/conf/vhost;cp -rf hpcc_load_c.conf.bk hpcc_load_c.conf;rm -f hpcc_load_lua.conf;/usr/local/hpc/sbin/nginx -s stop;sleep 1;/usr/local/hpc/sbin/nginx"
            while [ 0 -ne $? ];do
                sleep 10
                python /opt/truck/remote.py  call -H ${TEST_DEST_IP} -c "cd /usr/local/hpc/conf/vhost;cp -rf hpcc_load_c.conf.bk hpcc_load_c.conf;rm -f hpcc_load_lua.conf;/usr/local/hpc/sbin/nginx -s stop;sleep 1;/usr/local/hpc/sbin/nginx"
            done
            sleep 30
            echo "" >> $(dirname $0)/resultDir/allTestResult.csv
            echo "\"#cacheType is $cacheType\"" >> $(dirname $0)/resultDir/allTestResult.csv
            cacheType="hpc_ats"
            ;;
        hpc_ats|hpc_cos_ats)
            python /opt/truck/remote.py  call -H ${TEST_DEST_IP} -c "/usr/local/hpc/sbin/nginx;echo "" >/data/proclog/log/hpc/access.log;echo "" >/data/proclog/log/hpc/flexi_rcpt_mansubi/access_debug.log"
            while [ 0 -ne $? ];do
                sleep 10
                python /opt/truck/remote.py  call -H ${TEST_DEST_IP} -c "/usr/local/hpc/sbin/nginx;echo "" >/data/proclog/log/hpc/access.log;echo "" >/data/proclog/log/hpc/flexi_rcpt_mansubi/access_debug.log"
            done
            ;;
        nginx_ats)
            python /opt/truck/remote.py  call -H ${TEST_DEST_IP} -c "/usr/local/hpc/sbin/nginx -s stop"
            while [ 0 -ne $? ];do
                sleep 10
                python /opt/truck/remote.py  call -H ${TEST_DEST_IP} -c "/usr/local/hpc/sbin/nginx -s stop"
            done

            python /opt/truck/remote.py  call -H ${TEST_DEST_IP} -c "/usr/local/NGX-Lua/sbin/nginx  -s stop"
            while [ 0 -ne $? ];do
                sleep 10
                python /opt/truck/remote.py  call -H ${TEST_DEST_IP} -c "/usr/local/NGX-Lua/sbin/nginx  -s stop"
            done

            python /opt/truck/remote.py  call -H ${TEST_DEST_IP} -c "/usr/local/SRCache/sbin/nginx -s stop"
            while [ 0 -ne $? ];do
                sleep 10
                python /opt/truck/remote.py  call -H ${TEST_DEST_IP} -c "/usr/local/SRCache/sbin/nginx -s stop"
            done

            sleep 1
            python /opt/truck/remote.py  call -H ${TEST_DEST_IP} -c "/usr/local/NGX/sbin/nginx"
            while [ 0 -ne $? ];do
                sleep 10
                python /opt/truck/remote.py  call -H ${TEST_DEST_IP} -c "/usr/local/NGX/sbin/nginx"
            done
            ;;
        nginx_lua_ats)
            python /opt/truck/remote.py  call -H ${TEST_DEST_IP} -c "/usr/local/NGX/sbin/nginx -s stop"
            while [ 0 -ne $? ];do
                sleep 10
                python /opt/truck/remote.py  call -H ${TEST_DEST_IP} -c "/usr/local/NGX/sbin/nginx -s stop"
            done

            python /opt/truck/remote.py  call -H ${TEST_DEST_IP} -c "/usr/local/hpc/sbin/nginx -s stop"
            while [ 0 -ne $? ];do
                sleep 10
                python /opt/truck/remote.py  call -H ${TEST_DEST_IP} -c "/usr/local/hpc/sbin/nginx -s stop"
            done

            python /opt/truck/remote.py  call -H ${TEST_DEST_IP} -c "/usr/local/SRCache/sbin/nginx -s stop"
            while [ 0 -ne $? ];do
                sleep 10
                python /opt/truck/remote.py  call -H ${TEST_DEST_IP} -c "/usr/local/SRCache/sbin/nginx -s stop"
            done

            sleep 1
            python /opt/truck/remote.py  call -H ${TEST_DEST_IP} -c "/usr/local/NGX-Lua/sbin/nginx"
            while [ 0 -ne $? ];do
                sleep 10
                python /opt/truck/remote.py  call -H ${TEST_DEST_IP} -c "/usr/local/NGX-Lua/sbin/nginx"
            done
            ;;
        sr_ats)
            python /opt/truck/remote.py  call -H ${TEST_DEST_IP} -c "/usr/local/hpc/sbin/nginx -s stop"
            while [ 0 -ne $? ];do
                sleep 10
                python /opt/truck/remote.py  call -H ${TEST_DEST_IP} -c "/usr/local/hpc/sbin/nginx -s stop"
            done

            sleep 1
            python /opt/truck/remote.py  call -H ${TEST_DEST_IP} -c "/usr/local/SRCache/sbin/nginx"
            while [ 0 -ne $? ];do
                sleep 10
                python /opt/truck/remote.py  call -H ${TEST_DEST_IP} -c "/usr/local/SRCache/sbin/nginx"
            done
            ;;
        *)
            echo "invalid cacheType $cacheType"
            exit
            ;;
    esac

    for concurrent in ${CONCURRENT_NUM[@]};do
        for fileSizeRangeAllTestNum in ${FILE_SIZE_RANGE_ALL_TEST_NUM[@]};do
            fileSize=$(echo $fileSizeRangeAllTestNum |cut -f1 -d\|)
            range=$(echo $fileSizeRangeAllTestNum |cut -f2 -d\|)
            writeRatio=$(echo $fileSizeRangeAllTestNum |cut -f3 -d\|)
            allTestNum=$(echo $fileSizeRangeAllTestNum |cut -f4 -d\|)
            loopTimes=$(echo $fileSizeRangeAllTestNum |cut -f5 -d\|)
            for wafUrlRatio in ${WAF_URL_RATIO_LISTS[@]};do
                for((i=0;i<${loopTimes};i++));do
                    echo "loop is $i, cacheType is $cacheType, concurrent is $concurrent, fileSize is $fileSize, allTestNum is $allTestNum"
                    if [ $i -eq 0 ];then
                        if [ -f ${RUN_URL_LIST}_${cacheType}_${fileSize}_${allTestNum}_${writeRatio}_${wafUrlRatio} ];then
                            cp -rf ${RUN_URL_LIST}_${cacheType}_${fileSize}_${allTestNum}_${writeRatio}_${wafUrlRatio} ${RUN_URL_LIST}
                            origTimestamp=$(cat ${RUN_URL_LIST} |awk -F/ '{print $NF}' |awk -F_ '{if($3 != "") {print $3}}' |uniq)
                            currentTimestamp=$(date +%s)
                            if [ ${writeRatio} -eq 0 ];then
                                if [ -n "${origTimestamp}" ];then
                                    sed -i "s/_${origTimestamp}//g" ${RUN_URL_LIST}
                                fi
                            else
                                if [ -n "${origTimestamp}" ];then
                                    sed -i "s/${origTimestamp}/${currentTimestamp}/g" ${RUN_URL_LIST}
                                else
                                    sed -i "s/$/&_${currentTimestamp}/g" ${RUN_URL_LIST}
                                fi
                            fi
                            sleep 1
                            ./myload.sh  run -t $cacheType -n $allTestNum -c $concurrent -d ${fileSize}:100% -w ${writeRatio} -o ${wafUrlRatio} -ra ${range} -reuse
                        else
                            ./myload.sh  run -t $cacheType -n $allTestNum -c $concurrent -d ${fileSize}:100% -w ${writeRatio} -o ${wafUrlRatio} -ra ${range}
                            cp -rf ${RUN_URL_LIST} ${RUN_URL_LIST}_${cacheType}_${fileSize}_${allTestNum}_${writeRatio}_${wafUrlRatio}
                        fi
                    else
                        origTimestamp=$(cat ${RUN_URL_LIST} |awk -F/ '{print $NF}' |awk -F_ '{if($3 != "") {print $3}}' |uniq)
                        currentTimestamp=$(date +%s)
                        if [ ${writeRatio} -eq 0 ];then
                            if [ -n "${origTimestamp}" ];then
                                sed -i "s/_${origTimestamp}//g" ${RUN_URL_LIST}
                            fi
                        else
                            if [ -n "${origTimestamp}" ];then
                                sed -i "s/${origTimestamp}/${currentTimestamp}/g" ${RUN_URL_LIST}
                            else
                                sed -i "s/$/&_${currentTimestamp}/g" ${RUN_URL_LIST}
                            fi
                        fi
                        ./myload.sh  run -t $cacheType -n $allTestNum -c $concurrent -d ${fileSize}:100% -w ${writeRatio} -o ${wafUrlRatio} -ra ${range} -reuse
                    fi
                    sleep 1
                done    #loop times
            done    #wafUrlRatio
        done    #fileSize    
    done    #concurrent
done    #cacheType

