#!/bin/bash

for BITWIDTH in 16 8; do
    for DSP_WIDTH in 28; do
        python batch_classify.py \
            --xclbin $XCLBIN_PATH/xdnn_v2_32x${DSP_WIDTH}_$((112 / ${DSP_WIDTH}))pe_${BITWIDTH}b_$((2 + ${DSP_WIDTH} / 14))mb_bank21.xclbin \
            --netcfg $MLSUITE_ROOT/examples/compile/work/caffe/resnet/fp32/resnet50_without_bn_deploy_${DSP_WIDTH}.cmds \
            --fpgaoutsz 2048 \
            --datadir $MLSUITE_ROOT/examples/compile/work/caffe/resnet/fp32/resnet50_without_bn.caffemodel_data \
            --labels $MLSUITE_ROOT/models/data/ilsvrc12/synset_words.txt \
            --xlnxlib $LIBXDNN_PATH \
            --imagedir $MLSUITE_ROOT/models/data/ilsvrc12/ilsvrc12_img_val \
            --useblas \
            --golden $MLSUITE_ROOT/models/data/ilsvrc12/val.txt \
            --quantizecfg $MLSUITE_ROOT/examples/quantize/work/caffe/resnet/resnet50_without_bn_quantized_int${BITWIDTH}_deploy.json \
            --firstfpgalayer conv1
    done
done

for BITWIDTH in 16 8; do
    for DSP_WIDTH in 28; do
        python batch_classify.py \
            --xclbin $XCLBIN_PATH/xdnn_v2_32x${DSP_WIDTH}_$((112 / ${DSP_WIDTH}))pe_${BITWIDTH}b_$((2 + ${DSP_WIDTH} / 14))mb_bank21.xclbin \
            --netcfg $MLSUITE_ROOT/examples/compile/work/caffe/resnet/fp32/resnet101_without_bn_deploy_${DSP_WIDTH}.cmds \
            --fpgaoutsz 2048 \
            --datadir $MLSUITE_ROOT/examples/compile/work/caffe/resnet/fp32/resnet101_without_bn.caffemodel_data \
            --labels $MLSUITE_ROOT/models/data/ilsvrc12/synset_words.txt \
            --xlnxlib $LIBXDNN_PATH \
            --imagedir $MLSUITE_ROOT/models/data/ilsvrc12/ilsvrc12_img_val \
            --useblas \
            --golden $MLSUITE_ROOT/models/data/ilsvrc12/val.txt \
            --quantizecfg $MLSUITE_ROOT/examples/quantize/work/caffe/resnet/resnet101_without_bn_quantized_int${BITWIDTH}_deploy.json \
            --firstfpgalayer conv1
    done
done

for BITWIDTH in 16 8; do
    for DSP_WIDTH in 28; do
        python batch_classify.py \
            --xclbin $XCLBIN_PATH/xdnn_v2_32x${DSP_WIDTH}_$((112 / ${DSP_WIDTH}))pe_${BITWIDTH}b_$((2 + ${DSP_WIDTH} / 14))mb_bank21.xclbin \
            --netcfg $MLSUITE_ROOT/examples/compile/work/caffe/resnet/fp32/resnet152_without_bn_deploy_${DSP_WIDTH}.cmds \
            --fpgaoutsz 2048 \
            --datadir $MLSUITE_ROOT/examples/compile/work/caffe/resnet/fp32/resnet152_without_bn.caffemodel_data \
            --labels $MLSUITE_ROOT/models/data/ilsvrc12/synset_words.txt \
            --xlnxlib $LIBXDNN_PATH \
            --imagedir $MLSUITE_ROOT/models/data/ilsvrc12/ilsvrc12_img_val \
            --useblas \
            --golden $MLSUITE_ROOT/models/data/ilsvrc12/val.txt \
            --quantizecfg $MLSUITE_ROOT/examples/quantize/work/caffe/resnet/resnet152_without_bn_quantized_int${BITWIDTH}_deploy.json \
            --firstfpgalayer conv1
    done
done

