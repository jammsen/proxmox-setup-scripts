#!/usr/bin/env bash

# Get the latest CUDA base-ubuntu tag
get_latest_cuda_tag() {
    curl --silent "https://gitlab.com/nvidia/container-images/cuda/raw/master/doc/supported-tags.md" \
        | grep -i "base-ubuntu" \
        | head -1 \
        | sed -n 's/.*`\([^`]*\)`.*/\1/p'
}

latest_tag=$(get_latest_cuda_tag)

if [[ -z "$latest_tag" ]]; then
    echo "Error: Could not retrieve latest CUDA tag" >&2
    exit 1
fi

echo "Running nvidia/cuda:$latest_tag for nvidia-smi"
docker run --rm --gpus all "nvidia/cuda:${latest_tag}" nvidia-smi
echo "Testing FFmpeg for encoding with NVIDIA GPU"
docker run --rm -it --gpus all linuxserver/ffmpeg -hwaccel cuda -f lavfi -i testsrc2=duration=300:size=1280x720:rate=90 -c:v hevc_nvenc -qp 18 nvidia-hevc_nvec-90fps-300s.mp4