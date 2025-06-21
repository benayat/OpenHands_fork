#!/bin/bash

# Configuration for serving Devstral 24B on RTX 3090
# Optimized for 32k context length without concurrent requests
# Using RAM offloading to leverage 64GB DDR5 system memory

export CUDA_VISIBLE_DEVICES=0

# Start without quantization, using full precision model
vllm serve mistralai/Devstral-Small-2505 \
    --host 0.0.0.0 \
    --port 8000 \
    --tensor-parallel-size 1 \
    --max-model-len 32768 \
    --gpu-memory-utilization 0.80 \
    --max-num-batched-tokens 32768 \
    --max-num-seqs 1 \
    --disable-log-requests \
    --swap-space 24 \
    --block-size 16 \
    --enforce-eager \
    --max-cpu-memory 58 \
    --served-model-name devstral-24b
