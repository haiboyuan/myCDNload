#!/bin/bash

#****************************************************
#2017-04-03  V1.0  --haibo.yuan
#基于压力测试工具ab开发CDN压力测试脚本，具体功能包括
#   1. 数据灌入，可以指定文件大小比例，指定总数据量或者
#      按磁盘总大小指定百分比容量
#   2. 压力测试，可以设定如下测试参数：
#      （1）数据总量以及并发量设定
#      （2）不同大小文件以及百分比
#      （3）文件请求热度分配比例，如80%请求指定到20%文件上
#      （4）回源比例与命中比例分配
#   3. 支持的Cache平台类型
#      rfs|ats|tfs|squid|hpc_rfs|hpc_ats|hpc_tfs|fc_squid
#
#2018-01-12  V1.1  --haibo.yuan
#增加如下场景支持
#   1. 对nginx_ats|nginx_lua_ats等调试Cache平台支持
#   2. 支持Range压力请求
#
#2018-07-18  V1.2  --haibo.yuan
#支持WAF百分比设定性能测试，具体
#   增加-o|-other选项设定百分比支持双域名同时测试，
#   其中分别包含走WAF与不走WAF业务，按不同比例设置验证
#   不同百分比WAF业务对实际HPC性能影响
#****************************************************

#全局常量
RFSDESTIP="42.81.100.20"  #测试Cache机器 rfs
ATSDESTIP="10.20.64.203"  #测试Cache机器 ats
#ATSDESTIP="192.168.90.103"  #测试Cache机器 ats
TFSDESTIP="42.81.100.5"  #测试Cache机器 tfs
FCDESTIP="10.20.64.102"  #测试Cache机器 fc
DEBUG=true  #true打开debug信息，false关闭
RFSBASEURL="www.load.com/test_rfs"
ATSBASEURL="www.load.com/test_ats"
ATSBASEURL1="www.load1.com/test_ats"
SRATSBASEURL="www.load.com/test_srats"
TFSBASEURL="www.load.com/test_tfs"
#TFSBASEURL="www.load.com/test"
SQUIDBASEURL="www.load.com/test_squid"
URLSDIR=urlDir
ALL_DEPLOY_URL_LIST="$URLSDIR/allDeployUrlList.txt"
SINGLE_RUN_URL_LIST="$URLSDIR/singleRunUrlList.txt"
RUN_URL_LIST="$URLSDIR/runUrlList.txt"
RESULTDIR=resultDir
ALL_TEST_RESULT="${RESULTDIR}/allTestResult.csv"
#METRICS_REPORT_MENU_TITLE="RunTime|21 DestinationType|20 AllNum|8 ConcurrentNum|15 FileSizeDistribution|35 Hot|11 WriteRatio[%]|14 WAFRequestRatio[%]|19 M_RequestsPerSecond[#/sec]|28 M_TimePerRequest[ms]|22 M_TransferRate[Mbps]|28 M_TotalTransfer[Mb]|20 M_ErrorRequestRatio[%]|22"
METRICS_REPORT_MENU_TITLE="RunTime|21 DestinationType|20 AllNum|8 ConcurrentNum|15 FileSizeDistribution|35 BytesRange|11 WriteRatio[%]|14 M_RequestsPerSecond[#/sec]|28 M_TimePerRequest[ms]|22 M_TransferRate[Mbps]|28 M_TotalTransfer[Mb]|20 M_ErrorRequestRatio[%]|22"
RFSFILESDIR="/data/proclog/test_rfs"
ATSFILESDIR="/data/proclog/test_ats"
SRATSFILESDIR="/data/proclog/test_srats"
TFSFILESDIR="/data/proclog/test_tfs"
SQUIDFILESDIR="/data/proclog/test_squid"
ORIGINAL_FILE_FOR_DEPLOY="/data/proclog/test/lib64.tar"
REFRESH_SPEED=3000    #刷新速度，刷新3000个url等待1秒
LOOP_URL=no       #做压力测试是否循环使用URL，yes循环使用，no不循环使用
DEPLOY_BAND_WIDTH=$((50*1024*1024)) #HPC系统灌装数据时的假定带宽值，据此设定等待时间 50M
TFSTOOL_WRK_DIR=/tfstool_wrk_dir

#全局变量
action=""  #run: 执行压力测试, deploy: 往存储里部署数据
cacheType=""    #Cache类型，包括rfs ats hpcc等
num=""    #总测试URL条数
concurrent=100    #并发量
ratio=5     #总测试数据大小占总存储容量的比例
hot="100:100" #访问热点分步，如90:10 即90%访问量访问10%的URL数据
distribution="10K:1%-100K:1%-500K:1%-1M:2%-5M:5%-10M:5%-20M:5%-30M:10%-40M:20%-50M:50%"    #文件粒度大小分布  
writeRatio=0   #写请求占读请求比例，如10即写入数据流量为读数据流量的10%
otherURLRatio=0   #目前可以添加另外一条不同servername的url，此值即为另外一条url的请求占比数，如10即为第二条url占比总请求数10%
runReusedUrl=no  #执行压力测试时使用当前环境的URL List，不重新产生List，yes重复利用，no不重复利用
range="-"    #压力测试请求资源range范围，缺省为-表示不带range请求

#rfs存储系统参数
RFSPORTS=(718 719 720 721 722 723 724 725 726 727 728)

usage() {
    echo "Usage: ./$(basename $0) deploy|clear|run -t|-type rfs|ats|tfs|squid|hpc_rfs|hpc_ats|hpc_tfs|fc_squid|nginx_ats|nginx_lua_ats [-n 1000] [-c 100] [-r|-ratio 10] [-d|-distribution 1K:40%-1M:30%-10M:30%] [-h|-hot 80:20] [-w|-write 10] [-o|-other 10] [-ra|-range 0-26244]"
    exit
}

if [ $# -lt 3 ];then
    usage
fi
while [ -n "$1" ];do
    case "$1" in
        deploy|clear|run)
            action=$1
            shift;;
        -t|-type)
            cacheType=$2
            shift 2;;
        -n)
            num=$2
            shift 2;;
        -c)
            concurrent=$2
            shift 2;;
        -r|-ratio)
            ratio=$2
            shift 2;;
        -d|-distribution)
            distribution=$2
            shift 2;;
        -h|-hot)
            hot=$2
            shift 2;;
        -w|-wr)
            writeRatio=$2
            shift 2;;
        -o|-other)
            otherURLRatio=$2
            shift 2;;
        -ra|-range)
            range=$2
            shift 2;;
        -re|-reuse)
            runReusedUrl=yes
            shift;;
        *) 
            echo "$1 is invalid option"
            usage;;
    esac
done

#Debug 日志
debug() {
    if [ "$DEBUG" == "true" ];then
        echo "debug[$(date)]: $1"
    fi
}

#对变量加空格占位符
occupiedVar() {
    var=$1
    oSpace=$2
    varLen=${#var}       
    if [ ${oSpace} -le ${varLen} ];then
        var="${var} "
    else
        for((i=0;i<$((oSpace-varLen));i++));do
            var="${var} "
        done
    fi
    echo "$var"
}

#清除存储数据
clear_process() {
    debug "clear data process"
    case $cacheType in 
        rfs)
            debug "clear data for ats system"
            rfsPortNum=${#RFSPORTS[@]}
            for((i=0;i<$rfsPortNum;i++));do
                curl -s ${destIP}:${RFSPORTS[$i]}/ddir/${baseUrl} >/dev/null 2>&1
                debug "curl -s ${destIP}:${RFSPORTS[$i]}/ddir/${baseUrl}"
            done;;
        ats)
            debug "deploy data for ats system";;
        tfs)
            debug "deploy data for tfs system";;
        *)
            echo "invalid cacheType: $cacheType"
            usage;;
    esac
}

#存储数据灌装
deploy_process() {
    debug "deploy process: dest:$destIP,cacheType: $cacheType, sizeType: $1, dataSize: $2, distribution: $3 "
    sizeType=$1
    dataSize=$2
    distribution=$3
    if [ ! -d ${filesDir} ];then
        mkdir -p ${filesDir}
    fi
    if [ ! -d ${TFSTOOL_WRK_DIR} ];then
        mkdir -p ${TFSTOOL_WRK_DIR}
    fi
    if [ -f "$ORIGINAL_FILE_FOR_DEPLOY" ];then
        originalFileForDeploy="$ORIGINAL_FILE_FOR_DEPLOY"
    else
        originalFileForDeploy="/dev/zero"
    fi
    #根据部署存储数据场景建立目录
    if [ $sizeType -eq 1 ];then
        deployUrlList="$URLSDIR/${cacheType}_BaseURLNum_${dataSize}_${distribution}/deployUrlList.txt"
    elif [ $sizeType -eq 2 ];then
        deployUrlList="$URLSDIR/${cacheType}_BaseStorageRatioNum_${dataSize}_${distribution}/deployUrlList.txt"
    else
         echo "invalid sizeType:$sizeType"
         exit
    fi
    if [ ! -d $(dirname $deployUrlList) ];then
        mkdir -p $(dirname $deployUrlList)
    fi
    echo -n "" >./$deployUrlList

    #根据数据大小分布distribution往存储里写数据
    arrDistribution=${distribution//-/ }
    for sizeRatio in $arrDistribution;do
        ratio=$(echo $sizeRatio |cut -f2 -d:)
        ratio=${ratio//%/}
        size=$(echo $sizeRatio |cut -f1 -d:)
        sizeValue=${size//[cKMG]/}
        unit=${size//[0-9]/}
        debug "deploy data for $cacheType system"
        case $unit in
            c)
                sizeBytes=$sizeValue
                ;;
            K)
                sizeBytes=$((sizeValue*1024))
                ;;
            M)
                sizeBytes=$((sizeValue*1024*1024))
                ;;
            G)
                sizeBytes=$((sizeValue*1024*1024*1024))
                ;;
            *)
                echo "invalid size unit $unit"
                exit
                ;;
        esac
        case $cacheType in 
            hpc_rfs|rfs)
                rfsPortNum=${#RFSPORTS[@]}
                storageSize=$((4*1073741824000*rfsPortNum-50*1073741824*rfsPortNum)) #每张盘大小为4T，每张预留50G做为预留空间用做元数据以及可能的其他存储误差
                ;;
            hpc_ats|ats|sr_ats|hpc_cos_ats)
                storageSize=$((4*1073741824000*10-50*1073741824*10)) #每张盘大小为4T，每张预留50G做为预留空间用做元数据以及可能的其他存储误差,10张盘
                ;;
            hpc_tfs|tfs)
                storageSize=$((4*1073741824000*10-50*1073741824*10)) #每张盘大小为4T，每张预留50G做为预留空间用做元数据以及可能的其他存储误差,10张盘
                ;;
            fc_squid|squid)
                storageSize=$((4*1073741824000*10-50*1073741824*10)) #每张盘大小为4T，每张预留50G做为预留空间用做元数据以及可能的其他存储误差,10张盘
                ;;
            *)
                echo "invalid cacheType: $cacheType"
                usage
                ;;
        esac
        if [ $sizeType -eq 1 ];then
            debug "input data as the URL number"
            case $unit in
                c|K|M|G)
                    ;;
                *)
                    echo "invalid size unit $unit"
                    exit
                    ;;
            esac
            urlNum=$((dataSize*ratio/100))
        elif [ $sizeType -eq 2 ];then
            debug "input data as storage ratio"
            dataSizeBytes=$(($storageSize*$dataSize/100))    #根据总磁盘大小和比例计算需要灌装数据总字节数
            case $unit in
                c)
                    urlNum=$((dataSizeBytes*ratio/sizeValue/100))
                    ;;
                K)
                    urlNum=$((dataSizeBytes*ratio/sizeValue/100/1024))
                    ;;
                M)
                    urlNum=$((dataSizeBytes*ratio/sizeValue/100/1024/1024))
                    ;;
                G)
                    urlNum=$((dataSizeBytes*ratio/sizeValue/100/1024/1024/1024))
                    ;;
                *)
                    echo "invalid size unit $unit"
                    exit
                    ;;
            esac
        else
             echo "invalid sizeType:$sizeType"
             exit
        fi
        case $cacheType in 
            rfs)
                dd if=$originalFileForDeploy of=${filesDir}/${size}_0_${RFSPORTS[0]} bs=${size} count=1 >/dev/null 2>&1
                for((i=0,j=0;i<$urlNum;i++,j++));do
                    echo "${baseUrl}/${size}_${i}_${RFSPORTS[$j]}" >> ./$deployUrlList
                    #curl -sv 127.1:720/setsmf/jiandan.com/sfile3  -F upload=@sfile1 -H "Expect:"
                    curl -s ${destIP}:${RFSPORTS[$j]}/setsmf/${baseUrl}/${size}_${i}_${RFSPORTS[$j]}  -F upload=@${filesDir}/${size}_${i}_${RFSPORTS[$j]} -H "Expect:" >/dev/null 2>&1
                    #debug "debug: size is $size, rfs port is  ${RFSPORTS[$j]}"
                    if [ $j -eq $((rfsPortNum-1)) ];then
                        mv ${filesDir}/${size}_${i}_${RFSPORTS[$j]} ${filesDir}/${size}_$((i+1))_${RFSPORTS[0]}
                        j=-1 #达到rfs存储盘总数时初始化从第一张盘开始,-1因为for循环后+1
                    else
                        mv ${filesDir}/${size}_${i}_${RFSPORTS[$j]} ${filesDir}/${size}_$((i+1))_${RFSPORTS[$((j+1))]}
                    fi
                done
                ;;
            ats)
                dd if=$originalFileForDeploy of=${filesDir}/${size}_0 bs=${size} count=1 >/dev/null 2>&1
                echo "HTTP/1.1 200 OK" >${filesDir}/${size}_0_tmp
                echo "Content-Length: $sizeBytes" >>${filesDir}/${size}_0_tmp
                echo "" >>${filesDir}/${size}_0_tmp
                cat ${filesDir}/${size}_0 >>${filesDir}/${size}_0_tmp
                mv ${filesDir}/${size}_0_tmp ${filesDir}/${size}_0
                for((i=0;i<$urlNum;i++));do
                    echo "${baseUrl}/${size}_${i}" >> ./$deployUrlList
                    curl -sv "${baseUrl}/${size}_${i}" -XPUSH -x ${destIP}:770 -H "Expect:"  --data-binary @${filesDir}/${size}_${i} >/dev/null 2>&1
                    mv ${filesDir}/${size}_${i} ${filesDir}/${size}_$((i+1))
                done
                ;;
            tfs)
                dd if=$originalFileForDeploy of=${filesDir}/${size}_0 bs=${size} count=1 >/dev/null 2>&1
                for((i=0;i<$urlNum;i++));do
                    cp ${filesDir}/${size}_${i} ${filesDir}/${size}_$((i+1))
                done
                tfs_key_num=0
                for((i=0;i<$urlNum;i++));do
                    ./tfstool -s ${destIP}:600 -i "put ${filesDir}/${size}_${i}" >${TFSTOOL_WRK_DIR}/out_${size}_${i} 2>&1 &
                    if [ $((i%500)) -eq 0 -o $i -eq $((urlNum-1)) ];then    #每500个请求并发一次，收集tfs key
                        sleep_time=$((sizeBytes*500/DEPLOY_BAND_WIDTH))
                        if [ ${sleep_time} -eq 0 ];then #如果并发总量小于假定带宽，等待时间设置为1
                            sleep_time=1
                        fi
                        if [ $i -eq $((urlNum-1)) ];then
                            sleep_time=$((sleep_time*3))
                        fi
                        sleep ${sleep_time}
                        for((j=0;j<$i+1;j++));do
                            if [ -f ${TFSTOOL_WRK_DIR}/out_${size}_${j} ];then
                                tfs_key=$(cat ${TFSTOOL_WRK_DIR}/out_${size}_${j} |grep  ${size}_${j} |awk '{print $4}' |awk -F, '{print $1}')
                                if [ -n "$tfs_key" ];then
                                    echo "http://${destIP}/v1/tfs/$tfs_key" >> ./$deployUrlList
                                    tfs_key_num=$((tfs_key_num+1))
                                    mv ${TFSTOOL_WRK_DIR}/out_${size}_${j} ${TFSTOOL_WRK_DIR}/out_${size}_${j}_rm
                                fi
                            fi
                        done
                    fi
                done
                debug "get tfs_key_num: $tfs_key_num against urlNum $urlNum"
                ;;
            squid)
                ;;
            hpc_rfs|hpc_ats|hpc_tfs|fc_squid|sr_ats|hpc_cos_ats)
                dd if=$originalFileForDeploy of=${filesDir}/${size} bs=${size} count=1 >/dev/null 2>&1
                for((i=0;i<$urlNum;i++));do
                    echo "${baseUrl}/${size}_${i}" >> ./$deployUrlList
                    curl -sv "${baseUrl}/${size}_${i}" -x ${destIP}:80 -o /dev/null >/dev/null 2>&1 &
                    if [ $((i%500)) -eq 0 ];then    #每500个请求并发一次，检查数据是否正确灌入系统
                        sleep_time=$((sizeBytes*500/DEPLOY_BAND_WIDTH))
                        if [ ${sleep_time} -eq 0 ];then #如果并发总量小于假定带宽，等待时间设置为1
                            sleep_time=1
                        fi
                        sleep ${sleep_time}
                        curl -sv "${baseUrl}/${size}_${i}" -x ${destIP}:80 -o out_${cacheType}_${size}_${i} >log_${cacheType}_${size}_${i} 2>&1   
                        if [ "${cacheType}" == "fc_squid" ];then
                            hitFlag=$(grep -s  "HIT from "  log_${cacheType}_${size}_${i})
                        elif [ "${cacheType}" == "sr_ats" ];then
                            hitFlag="HIT"   #不检查HIT状态
                        else
                            hitFlag=$(grep -s  "CC_CACHE: TCP_HIT"  log_${cacheType}_${size}_${i})
                        fi
                        if [ ! -n "$hitFlag" ];then
                            echo "Not HIT file ${baseUrl}/${size}_${i}"
                            i=$((i-1))
                            sleep 1
                            continue
                        else
                            originalFileSize=$(ls -l ${filesDir}/${size} |awk '{print $5}')
                            outFileSize=$(ls -l out_${cacheType}_${size}_${i} |awk '{print $5}')
                            if [ ! -n "${outFileSize}" -o  $outFileSize -ne $originalFileSize ];then
                                echo "Size Not equal $outFileSize !== $originalFileSize"
                                i=$((i-1))
                                sleep 1
                                continue
                            fi
                        fi
                        rm -f log_${cacheType}_${size}_${i} out_${cacheType}_${size}_${i}   #debug
                    fi
                done
                ;;
            *)
                echo "invalid cacheType: $cacheType"
                usage
                ;;
        esac
    done

    #备份灌装数据的URL记录并把所有记录追加到灌装数据记录文件中
    timeStamp=$(date |sed 's/ /-/g')
    cp -rf  ./$deployUrlList ./${deployUrlList}_$timeStamp
    cat  ./$deployUrlList >> $ALL_DEPLOY_URL_LIST
}

#压力测试
run_process() {
    #***************
    #   run_process $num $concurrent $hot $distribution $writeRatio $otherURLRatio $range
    #   myload run -n 10000  -c 1000  -hot  80:10  -distri 1K:40%-1M:30%-10M:30%  -wr 10 -o 10 -ra 0-100
    #***************
    num=$1
    concurrent=$2
    hot=$3
    distribution=$4
    writeRatio=$5
    otherURLRatio=$6
    range=$7
    if [ ! -d ./${RESULTDIR} ];then
        mkdir -p ./${RESULTDIR}
    fi
    #根据测试场景建立数据结果目录
    testResult="${RESULTDIR}/${cacheType}_num${num}_concurrent${concurrent}_hot${hot}_distribution${distribution}_writeRatio${writeRatio}_otherURLRatio${otherURLRatio}_range${range}/testResult.txt"
    testResultRaw="${RESULTDIR}/${cacheType}_num${num}_concurrent${concurrent}_hot${hot}_distribution${distribution}_writeRatio${writeRatio}_otherURLRatio${otherURLRatio}_range${range}/testResultRaw.txt"
    if [ ! -d $(dirname $testResult) ];then
        mkdir -p $(dirname $testResult)
    fi
    echo -n "" >./$testResult
    echo -n "" >./$testResultRaw

    if [ "${runReusedUrl}" != "yes" ];then
        echo -n "" >./${SINGLE_RUN_URL_LIST}
        echo -n "" >./${RUN_URL_LIST}
        debug "run process: dest:$destIP,cacheType: $cacheType, num: $num, concurrent: $concurrent, hot: $hot, distribution: $distribution, writeRatio: $writeRatio, otherURLRatio: $otherURLRatio, range: $range"
        hotFileRatio=$(echo $hot |cut -f2 -d:)
        hotFileNum=$((concurrent*hotFileRatio/100))
        hotRequestRatio=$(echo $hot |cut -f1 -d:)
        hotRequestNum=$((concurrent*hotRequestRatio/100))
        noneHotFileNum=$((concurrent*(100-hotFileRatio)/100))
        noneHotRequestNum=$((concurrent*(100-hotRequestRatio)/100))
        debug "hotFileNum:$hotFileNum, noneHotFileNum: $noneHotFileNum, hotRequestNum:$hotRequestNum, noneHotRequestNum:$noneHotRequestNum"
        #根据数据大小分布distribution生成要访问的URL列表
        arrDistribution=${distribution//-/ }
        for sizeRatio in $arrDistribution;do
            ratio=$(echo $sizeRatio |cut -f2 -d:)
            ratio=${ratio//%/}
            size=$(echo $sizeRatio |cut -f1 -d:)
            sizeValue=${size//[cKMG]/}
            unit=${size//[0-9]/}
            debug "create load test URL list for ${cacheType} system for sizeRatio $sizeRatio"
            case $unit in
                c|K|M|G)
                    ;;
                *)
                    echo "invalid size unit $unit"
                    exit
                    ;;
            esac
            sizeHotFileNum=$((hotFileNum*ratio/100))
            sizeHotRequestNum=$((hotRequestNum*ratio/100))
            sizeNoneHotFileNum=$((noneHotFileNum*ratio/100))
            sizeNoneHotRequestNum=$((noneHotRequestNum*ratio/100))
            for((i=0,j=0;i<$sizeHotRequestNum;i++,j++));do
                case $cacheType in 
                    rfs)
                        #http://42.81.100.20:718/getsmf/www.load.com/test/1K_0_718
                        fileSeq=$j
                        portSeq=$fileSeq
                        rfsPortNum=${#RFSPORTS[@]}
                        if [ $portSeq -ge $rfsPortNum ];then
                            portSeq=$((portSeq%rfsPortNum))
                        fi
                        echo "http://${destIP}/getsmf/${baseUrl}/${size}_${fileSeq}_${RFSPORTS[$portSeq]}" >> ./$SINGLE_RUN_URL_LIST
                        ;;
                    ats|hpc_ats|hpc_rfs|hpc_tfs|fc_squid|nginx_ats|nginx_lua_ats|sr_ats|hpc_cos_ats)
                        #http://www.load.com/test/256K_0
                        echo "http://${baseUrl}/${size}_${j}" >> ./$SINGLE_RUN_URL_LIST
                        ;;
                    tfs|nginx_tfs)
                        ;;
                    squid)
                        ;;
                    *)
                        echo "invalid cacheType: $cacheType"
                        usage
                        ;;
                esac
                if [ $j -eq $((sizeHotFileNum-1)) ];then
                    j=-1 #达到URL列表末尾时从-1开始，因为for循环末尾+1
                fi
            done
            for((i=0,j=0;i<$sizeNoneHotRequestNum;i++,j++));do
                case $cacheType in 
                    rfs)
                        fileSeq=$((sizeHotFileNum+j))
                        portSeq=$fileSeq
                        rfsPortNum=${#RFSPORTS[@]}
                        if [ $portSeq -ge $rfsPortNum ];then
                            portSeq=$((portSeq%rfsPortNum))
                        fi
                        echo "http://${destIP}/getsmf/${baseUrl}/${size}_${fileSeq}_${RFSPORTS[$portSeq]}" >> ./$SINGLE_RUN_URL_LIST
                        ;;
                    ats|hpc_ats|hpc_rfs|hpc_tfs|fc_squid|nginx_ats|nginx_lua_ats|sr_ats|hpc_cos_ats)
                        echo "http://${baseUrl}/${size}_$((sizeHotFileNum+j))" >> ./$SINGLE_RUN_URL_LIST
                        ;;
                    tfs|nginx_tfs)
                        ;;
                    squid)
                        ;;
                    *)
                        echo "invalid cacheType: $cacheType"
                        usage
                        ;;
                esac
                if [ $j -eq $((sizeNoneHotFileNum-1)) ];then
                    j=-1 #达到URL列表末尾时从-1开始，因为for循环末尾+1
                fi
            done
        done

        if [ "${LOOP_URL}" == "yes" ];then
            #根据请求总数扩展测试url，重复使用
            for((i=0;i<$((num/concurrent));i++));do
                cat ./$SINGLE_RUN_URL_LIST >> ./$RUN_URL_LIST
            done
        else
            #根据请求总数扩展测试url，不重复使用
            time_stamp=$(date +%s)
            for((i=0;i<$((num/concurrent));i++));do
                for sizeRatio in $arrDistribution;do 
                    size=$(echo $sizeRatio |cut -f1 -d:)
                    size_unique_num=$(grep "$size" ./$SINGLE_RUN_URL_LIST |sort |uniq  |wc -l)
                    url_num=$(grep "$size" ./$SINGLE_RUN_URL_LIST |wc -l)
                    if [ $writeRatio -ne 0 ];then
                        miss_url_num=$((url_num*writeRatio/100))
                    else
                        miss_url_num=0
                    fi
                    if [ $otherURLRatio -ne 0 ];then
                        miss_url_num_otherURL=$((miss_url_num*otherURLRatio/100))
                        not_miss_url_num_otherURL=$((url_num*otherURLRatio/100-miss_url_num_otherURL))
                    else
                        miss_url_num_otherURL=0
                        not_miss_url_num_otherURL=0
                    fi
                    miss_i=0
                    miss_otherURL_i=0
                    not_miss_otherURL_i=0
                    if [ "$cacheType" != "rfs" ];then
                        for url in $(grep "$size" ./$SINGLE_RUN_URL_LIST);do
                            sequence=$(echo $url |awk -F"${size}_" '{print $2}')
                            new_sequence=$((sequence+i*size_unique_num))
                            new_url="$(echo $url |awk -F"${size}_" '{print $1}')${size}_${new_sequence}"
                            if [ $miss_i -lt $miss_url_num ];then
                                new_url=${new_url}_${time_stamp}
                                if [ $miss_otherURL_i -lt $miss_url_num_otherURL ];then
                                    new_url=${new_url/$baseUrl/$baseUrl1}
                                    miss_otherURL_i=$((miss_otherURL_i+1))
                                fi
                                miss_i=$((miss_i+1))
                            else
                                if [ $not_miss_otherURL_i -lt $not_miss_url_num_otherURL ];then
                                    new_url=${new_url/$baseUrl/$baseUrl1}
                                    not_miss_otherURL_i=$((not_miss_otherURL_i+1))
                                fi
                            fi
                            echo "$new_url" >>./$RUN_URL_LIST
                        done
                    else
                        for url in $(grep "$size" ./$SINGLE_RUN_URL_LIST);do
                            sequence=$(echo $url |awk -F"${size}_" '{print $2}' |awk -F"_" '{print $1}')
                            rfsPort=$(echo $url |awk -F"${size}_" '{print $2}' |awk -F"_" '{print $2}')
                            new_sequence=$((sequence+i*size_unique_num))
                            rfsPortNum=${#RFSPORTS[@]}
                            new_rfsPort=$((rfsPort+i*size_unique_num%rfsPortNum))
                            if [ $new_rfsPort -gt ${RFSPORTS[$((rfsPortNum-1))]} ];then
                                new_rfsPort=$((new_rfsPort-rfsPortNum))
                            fi
                            new_url="$(echo $url |awk -F"${size}_" '{print $1}')${size}_${new_sequence}_${new_rfsPort}"
                            echo "$new_url" >>./$RUN_URL_LIST
                        done
                    fi
                done
            done
        fi

        #nginx_tfs需要使用deploy阶段的tfs_key列表
        if [ "$cacheType" == "nginx_tfs" ];then
            if [ -f ./${URLSDIR}/tfs_BaseURLNum_${num}_${size}\:100\%/deployUrlList.txt ];then
                cp -rf  ./${URLSDIR}/tfs_BaseURLNum_${num}_${size}\:100\%/deployUrlList.txt ./$RUN_URL_LIST
            else
                echo "File ./${URLSDIR}/tfs_BaseURLNum_${num}_${size}\:100\%/deployUrlList.txt NOT exist"
                exit
            fi
        fi
    fi
    #执行压力测试
    debug "run load test URL list for ${cacheType} system"
    totalTransfer=0
    requestsPerSecond=0
    timePerRequest=0
    transferRate=0
    errorRequestNum=0
    case $cacheType in 
        rfs)
            rfsPortNum=${#RFSPORTS[@]}
            for((i=0;i<$rfsPortNum;i++));do
                cat ./$RUN_URL_LIST |grep "${RFSPORTS[$i]}$" > ./${RUN_URL_LIST}_${RFSPORTS[$i]}
            done
            for((i=0;i<$rfsPortNum;i++));do
                #./ab -n 12 -c 12  -X 42.81.100.20:718 -f test.txt
                echo -n "" >./${testResultRaw}_${RFSPORTS[$i]}
                singlePortNum=$(cat ./${RUN_URL_LIST}_${RFSPORTS[$i]} |wc -l)
                singlePortConcurrent=$((singlePortNum*concurrent/num))
                if [ $singlePortNum -gt 0 -a $singlePortConcurrent -gt 0 ];then
                    ./ab -n $singlePortNum -c $singlePortConcurrent -X $destIP:${RFSPORTS[$i]} -f ./${RUN_URL_LIST}_${RFSPORTS[$i]} > ./${testResultRaw}_${RFSPORTS[$i]} 2>&1 &
                    debug "./ab -n $singlePortNum -c $singlePortConcurrent -X $destIP:${RFSPORTS[$i]} -f ./${RUN_URL_LIST}_${RFSPORTS[$i]} > ./${testResultRaw}_${RFSPORTS[$i]}"
                else
                    rm -f ./${testResultRaw}_${RFSPORTS[$i]}
                fi
            done
            #根据结果监控所有测试结束后统计结果
            sleep 5
            for((i=0;i<$rfsPortNum;i++));do
                if [ -f ./${testResultRaw}_${RFSPORTS[$i]} ];then
                    sTotalTransfer=$(grep -s "Total transferred:" ./${testResultRaw}_${RFSPORTS[$i]} |awk '{print $3}')
                    sRequestsPerSecond=$(grep -s "Requests per second:" ./${testResultRaw}_${RFSPORTS[$i]} |awk '{print int($4+0.5)}')
                    sTimePerRequest=$(grep -s "Time per request:" ./${testResultRaw}_${RFSPORTS[$i]} |grep -v "across all" |awk '{print int($4+0.5)}')
                    sTransferRate=$(grep -s "Transfer rate:" ./${testResultRaw}_${RFSPORTS[$i]} |awk '{print int($3+0.5)}')
                    sErrorRequestNum=$(grep -s "404 responses:" ./${testResultRaw}_${RFSPORTS[$i]} |awk '{print $3}')
                    if [ ! -n "$sTotalTransfer" -o ! -n "$sRequestsPerSecond" -o ! -n "$sTimePerRequest" -o ! -n "$sTransferRate" ];then
                        debug "Not get key metric in $(pwd)/${testResultRaw}_${RFSPORTS[$i]}"
                        i=$((i-1))
                        sleep 30
                        continue
                    else
                        totalTransfer=$((totalTransfer+sTotalTransfer))
                        requestsPerSecond=$((requestsPerSecond+sRequestsPerSecond))
                        timePerRequest=$((timePerRequest+sTimePerRequest))
                        transferRate=$((transferRate+sTransferRate))
                        if [ -n "$sErrorRequestNum" ];then
                            errorRequestNum=$((errorRequestNum+sErrorRequestNum))
                        fi
                    fi
                fi
            done
            timePerRequest=$((timePerRequest/rfsPortNum))
            ;;
        ats|hpc_ats|hpc_rfs|hpc_tfs|fc_squid|nginx_ats|nginx_lua_ats|sr_ats|nginx_tfs|hpc_cos_ats)
            #./ab -k -n 10 -c 5 -X 42.81.100.6:770 -f ats.txt
            if [ "$cacheType" == "ats" ];then
                destPort=770
            else
                destPort=80
            fi
            if [ "$cacheType" == "fc_squid" ];then
                ./ab  -n $num -c $concurrent -X ${destIP}:${destPort} -f ./${RUN_URL_LIST} -H "connection:close" > ./${testResultRaw} 2>&1 &
                debug "./ab -n $num -c $concurrent -X ${destIP}:${destPort} -f ./${RUN_URL_LIST} -H \"connection:close\" > ./${testResultRaw}"
            else
                if [ "$range" == "-" ];then
                    ./ab -k  -n $num -c $concurrent -X ${destIP}:${destPort} -f ./${RUN_URL_LIST} > ./${testResultRaw} 2>&1 &
                    debug "./ab -k  -n $num -c $concurrent -X ${destIP}:${destPort} -f ./${RUN_URL_LIST} > ./${testResultRaw}"
                else
                    ./ab -k  -n $num -c $concurrent -X ${destIP}:${destPort} -H "range:bytes=${range}" -f ./${RUN_URL_LIST} > ./${testResultRaw} 2>&1 &
                    debug "./ab -k  -n $num -c $concurrent -X ${destIP}:${destPort} -H \"range:bytes=${range}\" -f ./${RUN_URL_LIST} > ./${testResultRaw}"
                fi
            fi
            sleep 5
            while true;do
                totalTransfer=$(grep -s "Total transferred:" ./${testResultRaw} |awk '{print $3}')
                requestsPerSecond=$(grep -s "Requests per second:" ./${testResultRaw} |awk '{print int($4+0.5)}')
                timePerRequest=$(grep -s "Time per request:" ./${testResultRaw} |grep -v "across all" |awk '{print int($4+0.5)}')
                transferRate=$(grep -s "Transfer rate:" ./${testResultRaw} |awk '{print int($3+0.5)}')
                errorRequestNum=$(grep -s "Failed requests:" ./${testResultRaw} |awk '{print $3}')
                if [ ! -n "$totalTransfer" -o ! -n "$requestsPerSecond" -o ! -n "$timePerRequest" -o ! -n "$transferRate" ];then
                    debug "Not get key metric in $(pwd)/${testResultRaw}"
                    sleep 30
                    continue
                else
                    break
                fi
            done
            ;;
        tfs)
            ;;
        squid)
            ;;
        *)
            echo "invalid cacheType: $cacheType"
            usage
            ;;
    esac
    if [ ! -n "$errorRequestNum" ];then
        errorRequestNum=0
    fi
    errorRequestRatio=$(printf "%.2f" $(echo "scale=2; ${errorRequestNum}*100/${num}" | bc -l))
    transferRate=$((transferRate/1024*8))
    totalTransfer=$((totalTransfer/1024/1024))


    #生成测试报告文件
    debug "Result: totalTransfer $totalTransfer,requestsPerSecond $requestsPerSecond, timePerRequest $timePerRequest, transferRate $transferRate, errorRequestNum $errorRequestNum"
    menusTitle=""
    formatMetricsValue=""
    runTime="$(date +%F/%T)"
    #metricsValue=($runTime $cacheType $num $concurrent $distribution $hot $writeRatio $requestsPerSecond $timePerRequest $transferRate $totalTransfer $errorRequestRatio)
echo "$distribution************************************************"
    showDistribution=${distribution//:100%/}
echo "$showDistribution************************************************"
    #metricsValue=($runTime $cacheType $num $concurrent $showDistribution $range $writeRatio $otherURLRatio $requestsPerSecond $timePerRequest $transferRate $totalTransfer $errorRequestRatio)
    metricsValue=($runTime $cacheType $num $concurrent $showDistribution $range $writeRatio $requestsPerSecond $timePerRequest $transferRate $totalTransfer $errorRequestRatio)
    metricsI=0
    for title in $METRICS_REPORT_MENU_TITLE;do
        titleName=$(echo $title |cut -f1 -d\|)
        occupiedSpace=$(echo $title |cut -f2 -d\|)
        titleName="$(occupiedVar $titleName $occupiedSpace),"
        menusTitle="${menusTitle}${titleName}"
        metric=${metricsValue[$metricsI]}
        metric=$(occupiedVar $metric $occupiedSpace)
        formatMetricsValue="${formatMetricsValue}${metric},"
        metricsI=$((metricsI+1))
    done
    echo "$menusTitle" >./$testResult
    echo "$formatMetricsValue" >>./$testResult
    escapeMenusTitle=${menusTitle//[/\\\[}
    escapeMenusTitle=${escapeMenusTitle//]/\\\]}
    if ! grep -s "$escapeMenusTitle" $ALL_TEST_RESULT >/dev/null;then
        echo "$menusTitle" >>$ALL_TEST_RESULT
    fi
    echo "$formatMetricsValue" >>$ALL_TEST_RESULT
}   #run_process

#main
debug "action:$action    num: $num    concurrent: $concurrent  range: $range    ratio: $ratio  distribution: $distribution "
scriptPath=$(dirname $0)
cd $scriptPath
if [ ! -d ./${URLSDIR} ];then
    mkdir -p ./${URLSDIR}
fi

case $cacheType in 
    hpc_rfs|rfs)
        destIP=${RFSDESTIP}
        baseUrl=${RFSBASEURL}
        filesDir=${RFSFILESDIR}
        ;;
    hpc_ats|ats|nginx_ats|nginx_lua_ats|hpc_cos_ats)
        destIP=${ATSDESTIP}
        baseUrl=${ATSBASEURL}
        baseUrl1=${ATSBASEURL1}
        filesDir=${ATSFILESDIR}
        ;;
    sr_ats)
        destIP=${ATSDESTIP}
        baseUrl=${SRATSBASEURL}
        filesDir=${SRATSFILESDIR}
        ;;
    hpc_tfs|tfs|nginx_tfs)
        destIP=${TFSDESTIP}
        baseUrl=${TFSBASEURL}
        filesDir=${TFSFILESDIR}
        ;;
    fc_squid|squid)
        destIP=${FCDESTIP}
        baseUrl=${SQUIDBASEURL}
        filesDir=${SQUIDFILESDIR}
        ;;
    *)
        echo "invalid cacheType: $cacheType"
        usage
        ;;
esac

if [ "$action" == "clear" ];then
    echo "***START*** clear data process at $(date)"
    clear_process
    echo "***FINISH*** clear data process at $(date)"
elif [ "$action" == "deploy" ];then
    echo "***START*** deploy process at $(date)"
    sizeType=2  #测试数据量大小类型，1按照URL条数 2按照数据量占总存储容量
    dataSize=$ratio
    if [ -n "$num" ];then
        sizeType=1
        dataSize=$num
    else
        sizeType=2
        dataSize=$ratio
    fi
    deploy_process $sizeType $dataSize $distribution
    echo "***FINISH*** deploy process at $(date)"
elif [ "$action" == "run" ];then
    sleep 2
    echo "***START*** run process at $(date)"
    run_process $num $concurrent $hot $distribution $writeRatio $otherURLRatio $range
    echo "***FINISH*** run process at $(date)"
else
    echo "unkown action: $action"
    usage 
fi

