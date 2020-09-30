#! /bin/bash

#
# Yatda is just Yet Another Thread Dump Analyzer.  
#It focuses on providing quick JBoss EAP 7 specific statistics and known concerns.
#
# v1.1 Using Kfir Lavi suggestions http://kfirlavi.herokuapp.com/blog/2012/11/14/defensive-bash-programming/
# To debug, use: bash -x ./yatda.sh

#Show helper function
function helper_ {
    echo  "Usage: sh ./yatda.sh THREAD_DUMP_FILE_NAME"
    echo  "     -f: thead dump file name"
    echo  "     -t: specify a thread name to focus on"
    echo  "     -s: specify a particular generic line indicating thread usage"
    echo  "     -n: number of stack lines to focus on from specified threads"
    echo  "     -a: number of stack lines to focus on from all threads"
    echo  "     -u: check update"
}

#Set default string references to search for generic EAP 7 request stats
function set_default_ {
    DUMP_NAME="Full thread dump "
    ALL_THREAD_NAME=" nid=0x"
    REQUEST_THREAD_NAME="default task-"
    REQUEST_TRACE="io.undertow.server.Connectors.executeRootHandler"
    REQUEST_COUNT=0
    SPECIFIED_THREAD_COUNT=0
    SPECIFIED_USE_COUNT=0
    SPECIFIED_LINE_COUNT=20
    ALL_LINE_COUNT=10
    #DEBUGGER_FLAG=0
}

#Check update function
function update_ {
    echo "Checking update"
    DIR=`dirname "$(readlink -f "$0")"`
    SUM=`md5sum $DIR/yatda.sh | awk '{ print $1 }'`
    NEWSUM=`curl https://raw.githubusercontent.com/aogburn/yatda/master/md5`
    echo $DIR
    echo $SUM
    echo $NEWSUM
    if [ "x$NEWSUM" != "x" ]; then
        if [ $SUM != $NEWSUM ]; then
            echo "Version difference detected.  Downloading new version. Please re-run yatda."
            wget -q https://raw.githubusercontent.com/aogburn/yatda/master/yatda.sh -O $DIR/yatda.sh
            exit
        fi
    fi
    echo "Check complete."
}


# flags
function read_input_ {
    local OPTIND
    while getopts r:t:s:n:a:f:h:u:d: flag
    do
        case "${flag}" in
            r) REQUEST_THREAD_NAME=${OPTARG};;
            t) SPECIFIED_THREAD_NAME=${OPTARG};;
            s) SPECIFIED_TRACE=${OPTARG};;
            n) SPECIFIED_LINE_COUNT=${OPTARG};;
            a) ALL_LINE_COUNT=${OPTARG};;
            f) FILE_NAME=${OPTARG};;
            h) helper_ ;;
            u) update_;;
            d) DEBUGGER_FLAG=${OPTARG};;
        esac
    done

    if [ "x$FILE_NAME" = "x" ]; then
        echo "Please specify file name with -f flag"
        echo "Or use -h for helper"
        exit
    fi
}


# Use different thread details if it looks like a thread dump from JBossWeb/Tomcat
function set_for_tomcat_ {
    if [ `grep 'org.apache.tomcat.util' $FILE_NAME | wc -l` -gt 0 ]; then
        echo "Treating as dump from JBossWeb or Tomcat"
        REQUEST_THREAD_NAME="http-|ajp-"
        REQUEST_TRACE="org.apache.catalina.connector.CoyoteAdapter.service"
    fi
}

# Handle java 11 dump differently
function check_jdk11_ {
    if [ `grep "$DUMP_NAME" $FILE_NAME | grep " 11\." | wc -l` -gt 0 ]; then
        echo "Treating as dump from java 11"
    fi
}


# Print stats
function stats_ {

    DUMP_COUNT=`grep "$DUMP_NAME" $FILE_NAME | wc -l`
    echo "Number of thread dumps: " $DUMP_COUNT > $FILE_NAME.yatda

    THREAD_COUNT=`grep "$ALL_THREAD_NAME" $FILE_NAME | wc -l`
    echo "Total number of threads: " $THREAD_COUNT >> $FILE_NAME.yatda

    REQUEST_THREAD_COUNT=`grep "$ALL_THREAD_NAME" $FILE_NAME | egrep "$REQUEST_THREAD_NAME" | wc -l`
    echo "Total number of request threads: " $REQUEST_THREAD_COUNT >> $FILE_NAME.yatda

    if [ $REQUEST_THREAD_COUNT -gt 0 ]; then
        REQUEST_COUNT=`grep "$REQUEST_TRACE" $FILE_NAME | wc -l`
        echo "Total number of in process requests: " $REQUEST_COUNT >> $FILE_NAME.yatda

        REQUEST_PERCENT=`printf %.2f "$((10**4 * $REQUEST_COUNT / $REQUEST_THREAD_COUNT ))e-2" `
        echo "Percent of present request threads in use for requests: " $REQUEST_PERCENT >> $FILE_NAME.yatda

        if [ $DUMP_COUNT -gt 1 ]; then
            echo "Average number of in process requests per thread dump: " `expr $REQUEST_COUNT / $DUMP_COUNT` >> $FILE_NAME.yatda
            echo "Average number of request threads per thread dump: " `expr $REQUEST_THREAD_COUNT / $DUMP_COUNT` >> $FILE_NAME.yatda
            echo "Average number of threads per thread dump: " `expr $THREAD_COUNT / $DUMP_COUNT` >> $FILE_NAME.yatda
        fi
    fi

    if [ "x$SPECIFIED_THREAD_NAME" != "x" ]; then
        echo >> $FILE_NAME.yatda
        SPECIFIED_THREAD_COUNT=`grep "$ALL_THREAD_NAME" $FILE_NAME | egrep "$SPECIFIED_THREAD_NAME" | wc -l`
        echo "Total number of $SPECIFIED_THREAD_NAME threads: " $SPECIFIED_THREAD_COUNT >> $FILE_NAME.yatda

        if [[ "x$SPECIFIED_TRACE" != x && $SPECIFIED_THREAD_COUNT -gt 0 ]]; then
            SPECIFIED_USE_COUNT=`grep "$SPECIFIED_TRACE" $FILE_NAME | wc -l`
            echo "Total number of in process $SPECIFIED_THREAD_NAME threads: " $SPECIFIED_USE_COUNT >> $FILE_NAME.yatda

            SPECIFIED_PERCENT=`printf %.2f "$((10**4 * $SPECIFIED_USE_COUNT / $SPECIFIED_THREAD_COUNT ))e-2" `
            echo "Percent of present $SPECIFIED_THREAD_NAME threads in use: " $SPECIFIED_PERCENT >> $FILE_NAME.yatda

            if [ $DUMP_COUNT -gt 1 ]; then
                echo "Average number of in process $SPECIFIED_THREAD_NAME threads per thread dump: " `expr $SPECIFIED_COUNT / $DUMP_COUNT` >> $FILE_NAME.yatda
                echo "Average number of $SPECIFIED_THREAD_COUNT threads per thread dump: " `expr $SPECIFIED_THREAD_COUNT / $DUMP_COUNT` >> $FILE_NAME.yatda
            fi
        fi
    fi
}

#end stats


# Point out any specific known issues
function find_issue_ {
    echo >> $FILE_NAME.yatda
    echo "## Specific findings ##" >> $FILE_NAME.yatda
    i=1
}

# request thread default and core count
function check_core_ {
    if [[ $REQUEST_THREAD_COUNT -gt 0 && `expr $REQUEST_THREAD_COUNT % 16` == 0 ]]; then
    NUMBER_CORES=`expr $REQUEST_THREAD_COUNT / 16`
    NUMBER_CORES=`expr $NUMBER_CORES / $DUMP_COUNT`
        echo >> $FILE_NAME.yatda
        echo $((i++)) ": The number of present request threads is a multple of 16 so this may be a default thread pool size fitting $NUMBER_CORES CPU cores." >> $FILE_NAME.yatda
    fi
}

# request thread exhaustion
function pool_exhaustion_ {
    if [ $REQUEST_COUNT -gt 0 ] && [ $REQUEST_COUNT == $REQUEST_THREAD_COUNT ]; then
    #if [ $REQUEST_COUNT == $REQUEST_THREAD_COUNT ]; then
        echo >> $FILE_NAME.yatda
        echo $((i++)) ": The number of processing requests is equal to the number of present request threads.  This may indicate thread pool exhaustion so the task-max-threads may need to be increased (https://access.redhat.com/solutions/2455451)." >> $FILE_NAME.yatda
    fi
}

# check datasource exhaustion
# check java.util.Arrays.copyOf calls

#echo >> $FILE_NAME.yatda
# end Findings


function count_top_line_all_requets_top_20_ {
if [ $REQUEST_THREAD_COUNT -gt 0 ]; then
    # This returns counts of the top line from all request thread stacks
    echo "## Top lines of request threads ##" >> $FILE_NAME.yatda
    egrep "\"$REQUEST_THREAD_NAME" -A 2 $FILE_NAME | grep "at " | sort | uniq -c | sort -nr >> $FILE_NAME.yatda
    echo >> $FILE_NAME.yatda

    # This returns counts of the unique 20 top lines from all request thread stacks
    echo "## Most common from first $SPECIFIED_LINE_COUNT lines of request threads ##" >> $FILE_NAME.yatda
    egrep "\"$REQUEST_THREAD_NAME" -A `expr $SPECIFIED_LINE_COUNT + 1` $FILE_NAME | grep "at " | sort | uniq -c | sort -nr >> $FILE_NAME.yatda
    echo >> $FILE_NAME.yatda
fi
}

#Returns counts of the top line from all request thread stacks
#Returns counts of the unique 20 top lines from all request thread stacks
function count_top_line_all_requests_ {
    if [ $SPECIFIED_THREAD_COUNT -gt 0 ]; then
        # Returns counts of the top line from all request thread stacks
        echo "## Top lines of $SPECIFIED_THREAD_NAME threads ##" >> $FILE_NAME.yatda
        egrep "\"$SPECIFIED_THREAD_NAME" -A 2 $FILE_NAME | grep "at " | sort | uniq -c | sort -nr >> $FILE_NAME.yatda
        echo >> $FILE_NAME.yatda

        # This returns counts of the unique 20 top lines from all request thread stacks
        echo "## Most common from first $SPECIFIED_LINE_COUNT lines of $SPECIFIED_THREAD_NAME threads ##" >> $FILE_NAME.yatda
        egrep "\"$SPECIFIED_THREAD_NAME" -A `expr $SPECIFIED_LINE_COUNT + 1` $FILE_NAME | grep "at " | sort | uniq -c | sort -nr >> $FILE_NAME.yatda
        echo >> $FILE_NAME.yatda
    fi
}

# Returns counts of the top line from all thread stacks
function top_all_thread_stacks_ {
    echo "## Top lines of all threads ##" >> $FILE_NAME.yatda
    grep "$ALL_THREAD_NAME" -A 2 $FILE_NAME | grep "at " | sort | uniq -c | sort -nr >> $FILE_NAME.yatda
    echo >> $FILE_NAME.yatda

    # This returns counts of the unique 20 top lines from all request thread stacks
    echo "## Most common from first $ALL_LINE_COUNT lines of all threads ##" >> $FILE_NAME.yatda
    grep "$ALL_THREAD_NAME" -A `expr $ALL_LINE_COUNT + 1` $FILE_NAME | grep "at " | sort | uniq -c | sort -nr >> $FILE_NAME.yatda
}

# Focus on EAP boot threads
function boot_threads_ {
    echo  >> $FILE_NAME.yatda
    echo "## EAP BOOT THREAD INFO ##" >> $FILE_NAME.yatda
    echo  >> $FILE_NAME.yatda
    COUNT=`grep "ServerService Thread Pool " $FILE_NAME | wc -l`
    if [ $COUNT -gt 0 ]; then
        echo "Number of ServerService threads: " $COUNT >> $FILE_NAME.yatda
        if [ $DUMP_COUNT -gt 1 ]; then
            echo "Average number of ServerService threads per thread dump: " `expr $COUNT / $DUMP_COUNT` >> $FILE_NAME.yatda
        fi
        echo "## Most common from first 10 lines of ServerService threads ##" >> $FILE_NAME.yatda
        grep "ServerService Thread Pool " -A 11 $FILE_NAME | grep "at " | sort | uniq -c | sort -nr >> $FILE_NAME.yatda
        echo  >> $FILE_NAME.yatda
    fi
}

#Display data for MSC service threads:
function msc_service_ {
    COUNT=`grep "MSC service thread " $FILE_NAME | wc -l`
    if [ $COUNT -gt 0 ]; then
        echo "Number of MSC service threads: " $COUNT >> $FILE_NAME.yatda

        TASK_COUNT=`grep "org.jboss.msc.service.ServiceControllerImpl\\$ControllerTask.run" $FILE_NAME | wc -l`
        echo "Total number of running ControllerTasks: " $TASK_COUNT >> $FILE_NAME.yatda

        MSC_PERCENT=`printf %.2f "$((10**4 * $TASK_COUNT / $COUNT ))e-2" `
        echo "Percent of present MSC threads in use: " $MSC_PERCENT >> $FILE_NAME.yatda


        if [ $DUMP_COUNT -gt 1 ]; then
            echo "Average number of MSC service threads per thread dump: " `expr $COUNT / $DUMP_COUNT` >> $FILE_NAME.yatda
        fi
        if [[ `expr $COUNT % 2` == 0 ]]; then
            NUMBER_CORES=`expr $COUNT / 2`
            NUMBER_CORES=`expr $NUMBER_CORES / $DUMP_COUNT`
            echo "*The number of present MSC threads is a multple of 2 so this may be a default thread pool size fitting $NUMBER_CORES CPU cores. If these are all in use during start up, the thread pool may need to be increased via -Dorg.jboss.server.bootstrap.maxThreads and -Djboss.msc.max.container.threads properties per https://access.redhat.com/solutions/508413." >> $FILE_NAME.yatda
        fi
        echo "## Most common from first 10 lines of MSC threads ##" >> $FILE_NAME.yatda
        grep "MSC service thread " -A 11 $FILE_NAME | grep "at " | sort | uniq -c | sort -nr >> $FILE_NAME.yatda
    fi
}

#Main function
function main () {

    set_default_
    
    read_input_ "$@"

    if [[ $DEBUGGER_FLAG ]]; then  logger "STARTING LOGGER" > yatda.log; fi

    set_for_tomcat_

    ##check_jdk11

    stats_

    find_issue_

    check_core_

    pool_exhaustion_

    count_top_line_all_requets_top_20_

    count_top_line_all_requests_

    top_all_thread_stacks_

    boot_threads_

    msc_service_

}

#Starting main function
main "$@"
