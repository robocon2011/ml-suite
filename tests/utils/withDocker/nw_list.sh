#!/bin/bash
echo "### Cleaning Stale Files From Previous Run ###"
rm -rf output_logs
rm nw_status.txt

# Logs directory
mkdir output_logs

# Select platform
if [ -z "$MLSUITE_PLATFORM" ]; then
  export MLSUITE_PLATFORM="(unknown)"
  AUTODETECT_PLATFORM=`python -c "from xfdnn.rt.xdnn import getHostDeviceName; print(getHostDeviceName(None).decode('utf-8'))" | tr -d '\n'`
  if [ ! -z "$AUTODETECT_PLATFORM" -a $? -eq 0 -a `echo "$AUTODETECT_PLATFORM" | wc -w` -eq "1" ]; then
      #echo "Auto-detected platform: ${AUTODETECT_PLATFORM}"
      export MLSUITE_PLATFORM=${AUTODETECT_PLATFORM}
  else
      echo "Warning: failed to auto-detect platform. Please manually specify platform with -p"
  fi
else
  export MLSUITE_PLATFORM=$MLSUITE_PLATFORM
fi

export PLATFORM=$MLSUITE_PLATFORM
export PLATFORM=alveo-u250

# Export MLSuite path
export MLSUITE_ROOT=/opt/ml-suite
export XFDNN_ROOT=/opt/ml-suite
export SSD_DATA=/opt/ml-suite/share/data


# Set the model dir base path
MODELS_DIR_PATH=/opt/ml-suite/models/container/caffe/

# Adding data to log file
echo "######## Status of Deephi networks ########" >> nw_status.txt
echo "Platform : $PLATFORM" >> nw_status.txt
gitid=$(git log --format="%H" -n 1)
#date=$(date)
echo "Git commit ID : $gitid" >> nw_status.txt
echo "Date : $(date)" >> nw_status.txt
printf "\n\n" >> nw_status.txt


# Disable if dont want to run any of the networks
deephi_nw_run=1
pruned_nw_run=1
yolo_nw_run=1
yolo_prelu_nw_run=1

for i in "default" 
do

    if [ $deephi_nw_run -eq 1 ];
    then
        echo "#####  network List #####" >> nw_status.txt
        ./run_network.sh $MODELS_DIR_PATH/bvlc_googlenet $i
        ./run_network.sh $MODELS_DIR_PATH/inception_v2 $i
        ./run_network.sh $MODELS_DIR_PATH/inception_v3 $i
        ./run_network.sh $MODELS_DIR_PATH/inception_v4 $i
        ./run_network.sh $MODELS_DIR_PATH/resnet50_v1 $i
        ./run_network.sh $MODELS_DIR_PATH/resnet50_v2 $i
        ./run_network.sh $MODELS_DIR_PATH/squeezenet $i
        ./run_network.sh $MODELS_DIR_PATH/vgg16 $i
        ./run_network.sh $MODELS_DIR_PATH/inception_v2_ssd $i
    
    fi
    
    
    if [ $pruned_nw_run -eq 1 ];
    then    
        echo "#####  Pruned network List #####" >> nw_status.txt
    
        ./run_network.sh $MODELS_DIR_PATH/resnet_50_v1_prune_round10_2.6G $i
        ./run_network.sh $MODELS_DIR_PATH/resnet_50_v1_prune_round5_3.7G $i
    fi

done


export XBLAS_EMIT_PROFILING_INFO=1

if [ $yolo_nw_run -eq 1 ];
then    
################## Yolo standard network call

rm ${MLSUITE_ROOT}/apps/yolo/single_img_out.txt
rm ${MLSUITE_ROOT}/apps/yolo/batch_out.txt

NW_LOG_DIR=output_logs/yolov2_standard
NW_NAME=yolov2_standard

mkdir $NW_LOG_DIR

YOLO_RUN_DIR=$MLSUITE_ROOT/apps/yolo

printf "\n\n" >> nw_status.txt
    
echo "*** Network : $NW_NAME" >> nw_status.txt
printf "\n" >> nw_status.txt
echo "Run Directory Path        : $MLSUITE_ROOT/apps/yolo" >> nw_status.txt
echo "Output Log Directory Path : $(pwd)/$NW_LOG_DIR" >> nw_status.txt
echo "compile mode : default" >> nw_status.txt
 
for run_mode in "latency" "throughput"
do
    # Goto yolo directory
    cd $YOLO_RUN_DIR
    echo "$YOLO_RUN_DIR"
    
    ./run.sh -p $PLATFORM -t test_detect -m yolo_v2_standard_608 -k v3 -b 8 -g /opt/data/COCO_Dataset/labels/val2014 -d /opt/data/COCO_Dataset/val2014_dummy -compilerOpt $run_mode
    
    cd -
    
    cp $YOLO_RUN_DIR/single_img_out.txt ${NW_LOG_DIR}/${run_mode}_single_img_out.txt
    mkdir ${NW_LOG_DIR}/${run_mode}
    cp $YOLO_RUN_DIR/work/* ${NW_LOG_DIR}/${run_mode}/
    cp $YOLO_RUN_DIR/batch_out.txt ${NW_LOG_DIR}/${run_mode}_batch_out.txt
   
    BATCH_HW_ERR=$(grep "ERROR" ${NW_LOG_DIR}/${run_mode}_single_img_out.txt | tail -1)
    if [ ! -z "$BATCH_HW_ERR" ];
    then
       echo "HW Error : $BATCH_HW_ERR" >> nw_status.txt
       echo "check Output Log Directory Path for more details." >> nw_status.txt
       echo "*** Network End" >> nw_status.txt
       exit 1;
    fi
 
    echo "Run mode : ${run_mode}" >> nw_status.txt
    grep "hw_counter" ${NW_LOG_DIR}/${run_mode}_single_img_out.txt | tail -1 >> nw_status.txt
    grep "exec_xdnn" ${NW_LOG_DIR}/${run_mode}_single_img_out.txt | tail -1 >> nw_status.txt
    grep "mAP" ${NW_LOG_DIR}/${run_mode}_batch_out.txt >> nw_status.txt

done
echo "*** Network End" >> nw_status.txt
fi

if [ $yolo_prelu_nw_run -eq 1 ];
then    
################## Yolo prelu network call

rm ${MLSUITE_ROOT}/apps/yolo/single_img_out.txt
rm ${MLSUITE_ROOT}/apps/yolo/batch_out.txt

NW_LOG_DIR=output_logs/yolov2_prelu
NW_NAME=yolov2_prelu

mkdir $NW_LOG_DIR

YOLO_RUN_DIR=$MLSUITE_ROOT/apps/yolo

printf "\n\n" >> nw_status.txt
    
echo "*** Network : $NW_NAME" >> nw_status.txt
printf "\n" >> nw_status.txt
echo "Run Directory Path        : $MLSUITE_ROOT/apps/yolo" >> nw_status.txt
echo "Output Log Directory Path : $(pwd)/$NW_LOG_DIR" >> nw_status.txt
echo "compile mode : default" >> nw_status.txt
 
for run_mode in "latency" "throughput"
do

    # Goto yolo directory
    cd $YOLO_RUN_DIR

    ./run.sh -p $PLATFORM -t test_detect -m yolo_v2_prelu_608 -k v3 -b 8 -g /opt/data/COCO_Dataset/labels/val2014 -d /opt/data/COCO_Dataset/val2014_dummy -compilerOpt $run_mode
    
    cd -
    
    cp $YOLO_RUN_DIR/single_img_out.txt ${NW_LOG_DIR}/${run_mode}_single_img_out.txt
    mkdir ${NW_LOG_DIR}/${run_mode}
    cp $YOLO_RUN_DIR/work/* ${NW_LOG_DIR}/${run_mode}/
    cp $YOLO_RUN_DIR/batch_out.txt ${NW_LOG_DIR}/${run_mode}_batch_out.txt

    BATCH_HW_ERR=$(grep "ERROR" ${NW_LOG_DIR}/${run_mode}_single_img_out.txt | tail -1)
    if [ ! -z "$BATCH_HW_ERR" ];
    then
       echo "HW Error : $BATCH_HW_ERR" >> nw_status.txt
       echo "check Output Log Directory Path for more details." >> nw_status.txt
       echo "*** Network End" >> nw_status.txt
       exit 1;
    fi
    
   
    echo "Run mode : ${run_mode}" >> nw_status.txt
    grep "hw_counter" ${NW_LOG_DIR}/${run_mode}_single_img_out.txt | tail -1 >> nw_status.txt
    grep "exec_xdnn" ${NW_LOG_DIR}/${run_mode}_single_img_out.txt | tail -1 >> nw_status.txt
    grep "mAP" ${NW_LOG_DIR}/${run_mode}_batch_out.txt >> nw_status.txt
    
done
echo "*** Network End" >> nw_status.txt
fi


chmod 777 -R output_logs
chmod 777 -R nw_status.txt

################### Table Generation
#
#python gen_table.py nw_status.txt
#
#cur_time=$(date +"%d%b%y_%H-%M")
#cur_date=$(date +"%d%b%y")
#echo "$cur_time"
#
#mv nw_status.txt output_logs/nw_status_$cur_date.txt
#mv xfdnn_nightly.csv output_logs/xfdnn_nightly_$cur_date.csv
#mv output_logs output_logs_$cur_date
#chmod 777 -R output_logs_$cur_date
#cp -r output_logs_${cur_date} /wrk/acceleration/test_deephi/daily_logs/output_logs_${cur_date}_Docker
