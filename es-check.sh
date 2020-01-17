#/bin/bash

export PATH="$PATH:./"

[ $(id -u) -gt 0 ] && echo "请用root您执行此脚本！" && exit 1

Green_font_prefix="\033[32m" && Red_font_prefix="\033[31m" && yellow_font_prefix="\033[33m" && Green_background_prefix="\033[42;37m" && Red_background_prefix="\033[41;37m" && Font_color_suffix="\033[0m"
host_ip=$(ifconfig -a | grep inet | grep -v 127.0.0.1 | grep -v inet6 | awk '{print $2}')
LOGPATH='/tmp/eslog'
separator='------------------------------------------------------------------------'

yell () {
  printf "%b\n" "${yellow_font_prefix}$1${Font_color_suffix}\n"
}

check_dir(){
    if [ ! -d $LOGPATH ];then
        mkdir $LOGPATH
    else
        rm -rf $LOGPATH && mkdir $LOGPATH
    fi
}
check_ipaddr()
{
    echo $1|grep "^[0-9]\{1,3\}\.\([0-9]\{1,3\}\.\)\{2\}[0-9]\{1,3\}$" > /dev/null;
    if [ $? -ne 0 ]
    then
        #echo "IP地址必须全部为数字" 
        return 1
    fi
    ipaddr=$1
    a=`echo $ipaddr|awk -F . '{print $1}'`  #以"."分隔, 取出每个列的值 
    b=`echo $ipaddr|awk -F . '{print $2}'`
    c=`echo $ipaddr|awk -F . '{print $3}'`
    d=`echo $ipaddr|awk -F . '{print $4}'`
    for num in $a $b $c $d
    do
        if [ $num -gt 255 ] || [ $num -lt 0 ]    #每个数值必须在0-255之间 
        then
            echo $ipaddr "中, 字段"$num"错误" 
            return 1
        fi
   done
   #echo $ipaddr "地址合法"
   return 0
}

get_user_input(){
    read -p "请输入es VIP地址（这个IP地址可以到控制台里查看到）:" esvip
    check_ipaddr $esvip
    ip_status=$?
    if [ $ip_status -eq 0 ];then
          break 
    else
      echo -e "${Error}输入的地址不合规, 请确认你输入的ip地址"
      exit 1
    fi
}

if_passwd(){
read -p "您的es服务有无设置您名密码安全认证？（也就是登录kibana的用户名密码） Y/N:" esyn
 case $esyn in
 [Yy]* ) Get_User_Passwd;judge_httpcode;;
 [Nn]* ) elastic='';judge_httpcode;;
 * ) echo "输入有误, 请输入yes/y/no/n";;
 esac 
}

Get_User_Passwd(){
    read -p "请输入您的您的您名（建议用elastic超级用户执行，其他权限用户权限会存在不足获取信息不准情况）:" username
    read -p "请输入您的密码（我们不会记录您的密码）:" password
    elastic='-u'$username:$password
}

judge_httpcode(){
truecode=200
httpcode=$(curl -i -m 10 -o /dev/null -s -w %{http_code} $elastic ''$esvip':9200/_cat/health')
if [ $httpcode != $truecode ];then
    echo "获取esvip返回状态码为 $httpcode , 账户密码或者es的IP地址可能填写错误, 请再次确认。"
    break;
fi
}

indices_sort(){
mb=1048576
TMPINDICES="$LOGPATH/tmp_indices"
TMPFORMAT="$LOGPATH/tmp_format"
COLUMN="$LOGPATH/column"
COLUMN2="$LOGPATH/column2"
curl -s $elastic ''$esvip':9200/_cat/indices?bytes=b' | grep -v 'watcher-history' | grep -v 'monitoring' |  sort -rnk9 | column -t > $TMPINDICES
cat $TMPINDICES | while read line
do
    storesize=$(echo $line | awk '{print $9}' )
    if [ $storesize -lt $mb ];then
        format_kb=$(expr $storesize / 1024)
        echo $format_kb'kb' >> $TMPFORMAT
    else
        format_mb=$(expr $storesize / 1024 / 1042)
        echo $format_mb'mb' >> $TMPFORMAT
    fi
done
awk 'ARGIND==1{a[FNR]=$1}ARGIND==2{$9=a[FNR];print}' $TMPFORMAT $TMPINDICES > $COLUMN
sed '1i health status index uuid pri rep docs.count docs.deleted store.size pri.store.size' $COLUMN > $COLUMN2
}

format_disk(){
gb=1024
cluster_all_allocation_diskused=$(curl -s $elastic ''$esvip':9200/_cat/allocation?v&bytes=mb' | awk ' {sum += $3};END {print sum}')
cluster_all_allocation_diskavail=$(curl -s $elastic ''$esvip':9200/_cat/allocation?v&bytes=mb' | awk ' {sum += $4};END {print sum}')

if [ $cluster_all_allocation_diskused -ge $gb ];then
    diskused_format_gb=$(expr $cluster_all_allocation_diskused / 1024)
    echo -e "当前集群节点存储已使用(只统计data节点):$diskused_format_gb gb" 
else
    echo -e "当前集群节点存储已使用(只统计data节点):$cluster_all_allocation_diskused mb" 
    
fi

if [ $cluster_all_allocation_diskavail -ge $gb ];then
    diskavail_format_gb=$(expr $cluster_all_allocation_diskavail / 1024)
    echo -e "当前集群存储还剩余空间(只统计data节点):$diskavail_format_gb gb" 
else
    echo -e "当前集群存储还剩余空间(只统计data节点):$cluster_all_allocation_diskavail mb" 
fi


}

shard_division(){
#node.role:mdi分别表示 master、data、ingest 
cluster_number_of_all_nodes=$(curl -s $elastic ''$esvip':9200/_cat/nodes?v&h=r' | wc -l)
cluster_number_of_data_nodes=$(curl -s $elastic ''$esvip':9200/_cat/nodes?v&h=r' | grep d | wc -l)
cluster_number_of_master=$(curl -s $elastic ''$esvip':9200/_cat/nodes?v&h=r' | grep m | wc -l)
remainder=$(printf "%.2f" `echo "scale=2;$cluster_master_shards/$cluster_number_of_data_nodes"|bc`)
if [[ $remainder =~ ".00" ]];then
    echo "1. 当前总节点数 $cluster_number_of_all_nodes个 , master:$cluster_number_of_master个 , data:$cluster_number_of_data_nodes 个, 分片数理论上要是节点数的倍数, 当前为:$remainder , 当前数据分布均匀;"
else
    echo "1. 当前总分片数除于节点数值为:$remainder , 没有整除, 这样会导致数据分片分布不均匀, 造成一定的数据热点问题，建议默认分片数设置为data node节点数的倍数。"
fi
}

shard_judge(){
#echo "2. 当前总分片数 < 1000, 建议分片不能过少, 分片过少, 单个分片大小会很大, 这会影响集群的恢复能力。这里通常建议控制单个分片30G大小, 具体怎么控制分片的数量和大小, 查看下面的那篇文章"
if [ $cluster_number_of_data_nodes -le $cluster_master_shards ] || [ $cluster_number_of_data_nodes -lt 1000 ];then
    echo "2. 当前data节点数小于分片数并且小于1000,属于正常范围，data节点数:$cluster_number_of_data_nodes,总分片数:$cluster_master_shards"
elif [ $cluster_master_shards -ge 1000 ];then
    echo "2. 当前总分片数 $cluster_master_shards > 1000, 分片数过大会一定的影响集群读写性能、内存不足等问题, 总分片数=index索引数*默认设置分片数*（副本数+1）, 如果分片数过大, 可以调整默认分片数设置或副本数设置。"
fi
}

cluster_indices(){
cluster_system_indices=$(curl -s $elastic ''$esvip':9200/_cat/indices?bytes=b' | grep \\. |  tail -n +2 | wc -l)
cluster_user_indices=$(curl -s $elastic ''$esvip':9200/_cat/indices?bytes=b' | grep -v \\. |  tail -n +2 | wc -l)
if [ $cluster_system_indices -ge 100 ] || [ $cluster_user_indices -ge 100 ];then
    echo "3. 当前索引数大于100, 当前系统索引:$cluster_system_indices, 您自建索引数（业务索引）:$cluster_user_indices, 如果您是日志场景请注意过期日志数据要定期删除, 索引的建立最好按周、按月或者按年的时间维度来创建, 按天索引数会很多。"
else
    echo "3. 当前系统索引:$cluster_system_indices, 您自建索引数（业务索引）:$cluster_user_indices"
fi
}

index_top3(){
echo "4. 数据量大小排名前五的索引分别是:"
array=(2 3 4 5 6)
for i in ${array[@]}
do
index_top_name=$(cat $COLUMN2 | head -n $i | tail -n1 | awk '{print $3}')
index_top_shards=$(cat $COLUMN2 | head -n $i | tail -n1 | awk '{print $5}')
index_top_replicas=$(expr $(cat $COLUMN2 | head -n $i | tail -n1 | awk '{print $6}') + 1)
index_top_size=$(cat $COLUMN2 | head -n $i | tail -n1 | awk '{print $9}'| tr -d "mb")
index_top_shards_multiplied_replicas=$(expr $index_top_shards \* $index_top_replicas)
index_top_size_sum=$(expr $index_top_size / $index_top_shards_multiplied_replicas)
index=$(expr $i - 1)
if [ $index_top_size_sum -gt 3072 ];then
    echo " ($index) $index_top_name, 它总大小是: $index_top_size mb, 它的默认分片设置number_of_shards=$index_top_shards, 副本数设置number_of_replicas=$index_top_replicas,它每个分片大小目前为:$index_top_size / ($index_top_shards * ($index_top_replicas + 1) ) = $index_top_size_sum mb "
else
    echo " ($index) $index_top_name, 它总大小是: $index_top_size mb, 它的默认分片设置number_of_shards=$index_top_shards, 副本数设置number_of_replicas=$index_top_replicas,它每个分片大小目前为:$index_top_size / ($index_top_shards * ($index_top_replicas + 1) ) = $index_top_size_sum mb "
fi
done
echo "注:每个分片大小最优值为<=30G(3072mb), 因此理论上这个索引还能继续增长大小,直到单个分片30G大小。"
}

cluster_diskusage(){
cluster_nodes_all_disk_total=$(curl -s $elastic ''$esvip':9200/_cat/nodes?v&h=diskTotal' | awk ' {sum += $1};END {print sum}' )
cluster_nodes_all_disk_use=$(curl -s $elastic ''$esvip':9200/_cat/nodes?v&h=diskUsed' | awk ' {sum += $1};END {print sum}' )
cluster_nodes_cluster_disk_usage=`echo "scale=2;$cluster_nodes_all_disk_use  / $cluster_nodes_all_disk_total * 100" | bc`

if [ $(echo "$cluster_nodes_cluster_disk_usage > 80 " | bc) -gt 0 ];then
    echo "5. 当前集群维度磁盘利用率超过80, 注意扩容磁盘空间, 这里强烈建议预留20%的磁盘空间给es集群本身segment 合并、ES Translog、日志等;"
    echo "5.1 另外, Linux 操作系统默认为 root 您预留5%的磁盘空间, 用于关键流程处理、系统恢复、防止磁盘碎片化问题等"
else
    echo "5. 当前集群维度磁盘使用率$cluster_nodes_cluster_disk_usage%"
fi
}

node_diskusage(){
local disks=(`curl -s $elastic ''$esvip':9200/_cat/nodes?v&h=ip,diskUsedPercent'| tail -n +2| awk '{print $1,$2}'`)
local len=${#disks[@]}
for ((i=1;i<=$len;i=i+2));do
    if [ `echo ${disks[i]} | awk -v tem=0 '{print($1>tem)? "1":"0"}'` -eq "0" ]; then
        echo "6. 节点:${disks[$i-1]} 当前磁盘使用率:${disks[$i]}%,"磁盘使用大于等于80%, 请检查。""
    else
        #echo "6. 当前节点:${disks[$i-1]} 当前磁盘使用率:${disks[$i]}% "
        echo "6. 当前节点维度磁盘使用率正常"
        return 0
    fi
done
}

document_count_case(){
document_count=$(curl -s $elastic ''$esvip':9200/_cat/count' | awk '{print $3}')
case ${#document_count} in
    1)  echo -e "当前集群文档总数是:$document_count"
    ;;
    2)  echo -e "当前集群文档总数是:$document_count"
    ;;
    3)  echo -e "当前集群文档总数是:$document_count"
    ;;
    4)  echo -e "当前集群文档总数是:${document_count:0:1},${document_count:1}"
    ;;
    5)  echo -e "当前集群文档总数是:${document_count:0:2},${document_count:2}"
    ;;
    6)  echo -e "当前集群文档总数是:${document_count:0:3},${document_count:3}"
    ;;  
    7)  echo -e "当前集群文档总数是:${document_count:0:1},${document_count:1:3},${document_count:4}"
    ;;
    8)  echo -e "当前集群文档总数是:${document_count:0:2},${document_count:2:3},${document_count:5}"
    ;;
    9)  echo -e "当前集群文档总数是:${document_count:0:3},${document_count:3:3},${document_count:6}"
    ;;
    *)  echo -e "当前集群文档总数是:$document_count "
    ;;
esac
#echo -e "当前集群文档总数是:${document_count:0:1},${document_count:1:3},${document_count:4:3},${document_count:7}" | tee -a "$ESLOG"
}


es(){
if_passwd
clear
echo -e "集群智能分析中, 请稍后... 如果长时间卡住没弹出结果请按ctrl+C终止重试" 
es_health=$(curl -s $elastic ''$esvip':9200/_cat/health?v')
Cluster_status=$(echo $es_health | awk '{print $18}')
Cluster_node_total=$(echo $es_health | awk '{print $19}')
Cluster_node_data=$(echo $es_health | awk '{print $20}')
active_shards_percent=$(echo $es_health | awk '{print $28}')
cluster_health_basis=$(curl -s $elastic ''$esvip':9200/_cluster/health')

cluster_name=$(echo $cluster_health_basis | tr -d '{}'  | sed 's/[,][,]*/ /g'  | sed 's/[:][:]*/ /g' | awk '{print $2}' | sed 's/\"//g')
cluster_status=$(echo $cluster_health_basis | tr -d '{}'  | sed 's/[,][,]*/ /g'  | sed 's/[:][:]*/ /g' | awk '{print $4}' | sed 's/\"//g')
cluster_timed_out=$(echo $cluster_health_basis | tr -d '{}'  | sed 's/[,][,]*/ /g'  | sed 's/[:][:]*/ /g' | awk '{print $6}')
cluster_number_of_nodes=$(echo $cluster_health_basis | tr -d '{}'  | sed 's/[,][,]*/ /g'  | sed 's/[:][:]*/ /g' | awk '{print $8}')
cluster_number_of_data_nodes=$(echo $cluster_health_basis | tr -d '{}'  | sed 's/[,][,]*/ /g'  | sed 's/[:][:]*/ /g' | awk '{print $10}')

cluster_pieces=$(curl -s $elastic ''$esvip':9200/_cat/health?v&pretty' | tr -d '{}'  | sed 's/[,][,]*/ /g'  | sed 's/[:][:]*/ /g')
cluster_master_shards=$(echo $cluster_pieces | awk '{print $23}')
cluster_master_pri=$(echo $cluster_pieces | awk '{print $24}')

cluster_relocating_shards=$(echo $cluster_health_basis | tr -d '{}'  | sed 's/[,][,]*/ /g'  | sed 's/[:][:]*/ /g' | awk '{print $16}')
cluster_initializing_shards=$(echo $cluster_health_basis | tr -d '{}'  | sed 's/[,][,]*/ /g'  | sed 's/[:][:]*/ /g' | awk '{print $18}')
cluster_delayed_unassigned_shards=$(echo $cluster_health_basis | tr -d '{}'  | sed 's/[,][,]*/ /g'  | sed 's/[:][:]*/ /g' | awk '{print $22}')
cluster_number_of_pending_tasks=$(echo $cluster_health_basis | tr -d '{}'  | sed 's/[,][,]*/ /g'  | sed 's/[:][:]*/ /g' | awk '{print $24}')
cluster_number_of_in_flight_fetch=$(echo $cluster_health_basis | tr -d '{}'  | sed 's/[,][,]*/ /g'  | sed 's/[:][:]*/ /g' | awk '{print $26}')
cluster_task_max_waiting_in_queue_millis=$(echo $cluster_health_basis | tr -d '{}'  | sed 's/[,][,]*/ /g'  | sed 's/[:][:]*/ /g' | awk '{print $28}')
cluster_nodes_status=$(curl -s $elastic ''$esvip':9200/_cat/nodes?v')
cluster_all_indices=$(curl -s $elastic ''$esvip':9200/_cat/indices?bytes=b' | grep -v 'watcher-history' | grep -v 'monitoring' |  sort -rnk9)
#node
cluster_nodes_disk=$(curl -s $elastic ''$esvip':9200/_cat/nodes?v&h=ip,diskTotal,diskUsed,diskAvail,diskUsedPercent,master,name')
aliases=$(curl -s $elastic ''$esvip':9200/_cat/aliases?v')
fielddata=$(curl -s $elastic ''$esvip':9200/_cat/fielddata?v' | sed 's/\s\+/ | /g')
pending_tasks=$(curl -s $elastic ''$esvip':9200/_cat/pending_tasks?v' | sed 's/\s\+/ | /g')
cluster_plugins=$(curl -s $elastic ''$esvip':9200/_cat/plugins?v')
cluster_setting_pretty=$(curl -s $elastic ''$esvip':9200/_all/_settings?&pretty')
cluster_all_allocation=$(curl -s $elastic ''$esvip':9200/_cat/allocation?v')

echo -e "--------------------------以下是智能分析结果----------------------------" | tee -a "$ESLOG"
echo -e "当前集群的名字是:$cluster_name" | tee -a "$ESLOG"
echo -e "执行脚本输入的您名:$username" | tee -a "$ESLOG"
echo -e "当前集群健康状态是:$cluster_status" | tee -a "$ESLOG"
echo -e "当前集群是否存在time_out: $cluster_timed_out" | tee -a "$ESLOG"
echo -e "当前集群的节点数是:$cluster_number_of_nodes" | tee -a "$ESLOG"
echo -e "当前集群data node总数是:$cluster_number_of_data_nodes" | tee -a "$ESLOG"
#echo -e "当前集群文档总数是:$document_count" | tee -a "$ESLOG"
document_count_case | tee -a "$ESLOG"
echo -e "当前集群的总分片数是: $cluster_master_shards" | tee -a "$ESLOG"
echo -e "当前集群的主分片数是: $cluster_master_pri" | tee -a "$ESLOG"
echo -e "当前集群可用分片百分比是:$active_shards_percent" | tee -a "$ESLOG"
format_disk | tee -a "$ESLOG"
echo -e "当前集群正在迁移的分片数:$cluster_relocating_shards" | tee -a "$ESLOG"
echo -e "当前集群初始化的分片数:$cluster_initializing_shards" | tee -a "$ESLOG"
echo -e "当前集群没有被分配到节点的分片数:$cluster_delayed_unassigned_shards" | tee -a "$ESLOG"
echo -e "当前集群在等待的任务数:$cluster_number_of_pending_tasks" | tee -a "$ESLOG"
echo -e "当前集群number_of_in_flight_fetch:$cluster_number_of_in_flight_fetch" | tee -a "$ESLOG"
echo -e "当前集群task_max_waiting_in_queue_millis:$cluster_task_max_waiting_in_queue_millis" | tee -a "$ESLOG"
indices_sort
#智能检测开始
echo $separator >> "$ESLOG"
echo -e "当前集群信息智能检测:" | tee -a "$ESLOG"
shard_division | tee -a "$ESLOG"
shard_judge | tee -a "$ESLOG"
cluster_indices | tee -a "$ESLOG"
index_top3 | tee -a "$ESLOG"
cluster_diskusage | tee -a "$ESLOG"
node_diskusage | tee -a "$ESLOG"
echo -e "\n" >> $ESLOG
echo -e "更多详细优化文章请参考:https://cloud.tencent.com/developer/article/1507657" | tee -a "$ESLOG"
#end
echo -e "\n" >> $ESLOG
echo $separator | tee -a "$ESLOG"
echo -e "当前集群节点状态:" | tee -a "$ESLOG"
echo -e "$cluster_nodes_status" | tee -a "$ESLOG"
echo -e "\n" >> $ESLOG
echo -e "注意:带 * 号的表示是master节点, 我们es集群的node节点是cvm, 对客户是不可见的, 客户无需关心cvm侧节点的运维操作。" | tee -a "$ESLOG"
echo -e "\n" >> $ESLOG
echo $separator | tee -a "$ESLOG"
echo -e "当前集群节点磁盘状态:"| tee -a "$ESLOG"
echo -e "$cluster_nodes_disk" | tee -a "$ESLOG"
echo -e "\n" >> $ESLOG
echo -e "注意:如果以上节点有部分节点磁盘使用率diskUsedPercent跟其他节点有明显的差距, 说明存在“数据热点”情况, 也就是说索引分片的分片是不均匀的, “数据热点”的出现将会导致部分节点压力过大, 建议分片数的设置要为节点数的整数倍。" | tee -a "$ESLOG"
echo -e "\n" >> $ESLOG
echo $separator | tee -a "$ESLOG"
echo -e "每个节点上分配的分片（shard）的数量和每个分片（shard）所使用的硬盘容量:" | tee -a "$ESLOG"
echo -e "$cluster_all_allocation" | tee -a "$ESLOG"
echo -e "\n" >> $ESLOG
echo $separator | tee -a "$ESLOG"
echo -e "所有别名:" | tee -a "$ESLOG"
echo -e "$aliases" | tee -a "$ESLOG"
echo -e "\n" >> $ESLOG
echo $separator | tee -a "$ESLOG"
echo -e "所有索引信息（过滤掉了.watcher-history & .monitoring- 开头的索引）:" >> "$ESLOG"
cat $COLUMN2 | column -t >> "$ESLOG"
echo -e "\n" >> $ESLOG
echo $separator  >> "$ESLOG"
echo -e "所有字段名:" >> "$ESLOG"
echo -e "$fielddata" >> "$ESLOG"
echo -e "\n" >> $ESLOG
echo $separator >> "$ESLOG"
echo -e "正在挂起的任务:$pending_tasks" >> "$ESLOG"
echo -e "\n" >> $ESLOG
echo $separator >> "$ESLOG"
echo -e "当前插件:" >> "$ESLOG"
echo -e "$cluster_plugins" >> "$ESLOG"
echo -e "\n" >> $ESLOG
echo $separator >> "$ESLOG"
echo -e "当前索引详情配置:" >> "$ESLOG"
echo -e "$cluster_setting_pretty" >> $ESLOG

}

yell_info() {
yell "# ------------------------------------------------------------------------------
# 您好！本脚本纯shell编写, 用于收集ES基础信息
#
# 脚本开源, 您可以用编辑器打开脚本查阅里面的代码。
#
# 确认脚本无误后, 放到ES集群节点上运行。
# ------------------------------------------------------------------------------"
}
yell_info2() {
yell "以上内容为部分输出, 详细内容已保存至$ESLOG ,  非常欢迎您对本脚本提供宝贵的建议，感谢您的支持！"
}
del_log(){
rm -rf $TMPINDICES
rm -rf $TMPFORMAT
rm -rf $COLUMN
rm -rf $COLUMN2
}
yell_info
get_user_input
ESLOG="$LOGPATH/$esvip"-"eslog-`hostname`-`date +%Y%m%d`.log"
check_dir
while true; do
    echo -e "您输入的ES VIP是:${Green_font_prefix}$esvip${Font_color_suffix} 您运行此脚本的本机IP地址是:${Green_font_prefix}$host_ip${Font_color_suffix} 请再次确认它们是在同一VPC或者网络互通的情况下哦, 不然网络不可达脚本检测会失败"
    read -p "确认请输入(Y)退出请输入(N): Y/N:" yn
    case $yn in
        [Yy]* )  es ;yell_info2;del_log;break;;
        [Nn]* ) echo "goodbye~";exit;;
        * ) echo "输入有误, 请输入yes/y/no/n";;
    esac 
done
