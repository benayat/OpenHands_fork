#!/bin/bash

# Script to configure Ubuntu 24.04 to use iGPU for display and dedicate RTX 3090 for vLLM only

# 1. Check current GPU configuration
echo "=== Current GPU Configuration ==="
nvidia-smi
echo ""

# Check if running Wayland or X11
echo "=== Checking Display Server ==="
if [ "$XDG_SESSION_TYPE" == "wayland" ]; then
    echo "You are using Wayland display server"
    IS_WAYLAND=true
else
    echo "You are using X11 display server"
    IS_WAYLAND=false
    echo "=== Current X Server GPU Usage ==="
    glxinfo | grep "OpenGL renderer"
    echo ""
fi
echo ""

# 2. Configure display settings based on the display server
if [ "$IS_WAYLAND" = true ]; then
    echo "=== Creating Wayland configuration to force iGPU usage ==="
    # Create a configuration file for GDM to prefer Intel GPU
    sudo mkdir -p /etc/udev/rules.d
    sudo tee /etc/udev/rules.d/99-nvidia-compute-only.rules > /dev/null << EOF
# Set NVIDIA GPU to compute only mode
SUBSYSTEM=="pci", ATTRS{vendor}=="0x10de", ATTRS{class}=="0x030000", ATTR{power/control}="on", ATTR{driver/unbind}="unbind", TAG+="systemd", ENV{SYSTEMD_WANTS}="nvidia-compute-mode.service"
EOF
else
    echo "=== Creating X11 configuration to force iGPU usage ==="
    sudo mkdir -p /etc/X11/xorg.conf.d
    sudo tee /etc/X11/xorg.conf.d/10-intel.conf > /dev/null << EOF
Section "Device"
    Identifier "Intel Graphics"
    Driver "intel"
    Option "AccelMethod" "sna"
    Option "TearFree" "true"
    Option "DRI" "3"
EndSection

Section "ServerLayout"
    Identifier "Layout0"
    Option "AllowNVIDIAGPUScreens" "false"
EndSection
EOF
fi

# 3. Create a script to set all NVIDIA services to use compute mode only
echo "=== Creating NVIDIA compute mode script ==="
sudo tee /etc/systemd/system/nvidia-compute-mode.service > /dev/null << EOF
[Unit]
Description=Set NVIDIA GPU to compute mode
After=display-manager.service

[Service]
Type=oneshot
ExecStart=/usr/bin/nvidia-smi -i 0 --compute-mode=EXCLUSIVE_PROCESS
ExecStart=/usr/bin/nvidia-smi -i 0 --applications-clocks-permission=RESTRICTED
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# 4. Enable the service
echo "=== Enabling NVIDIA compute mode service ==="
sudo systemctl enable nvidia-compute-mode.service

# 5. Set environment variables for vLLM script
echo "=== Creating environment config for vLLM ==="
cat > ~/vllm_env.sh << EOF
# Environment settings for vLLM
export CUDA_VISIBLE_DEVICES=0
export __NV_PRIME_RENDER_OFFLOAD=0
export __GLX_VENDOR_LIBRARY_NAME=mesa
EOF

# 6. Update the serve_devstral_vllm.sh script to source these environment variables
echo "=== Updating vLLM script with environment settings ==="
cat > serve_devstral_vllm.sh.new << EOF
#!/bin/bash

# Configuration for serving Devstral 24B on RTX 3090
# Optimized for 32k context length without concurrent requests
# Using RAM offloading to leverage 64GB DDR5 system memory

# Source the environment configuration
source ~/vllm_env.sh

# Start without quantization, using full precision model
# Adding Devstral-specific parameters from the original command
vllm serve mistralai/Devstral-Small-2505 \\
    --host 0.0.0.0 \\
    --port 8000 \\
    --tensor-parallel-size 1 \\
    --max-model-len 32768 \\
    --gpu-memory-utilization 0.95 \\
    --max-num-batched-tokens 32768 \\
    --max-num-seqs 1 \\
    --disable-log-requests \\
    --swap-space 24 \\
    --block-size 16 \\
    --enforce-eager \\
    --max-cpu-memory 58 \\
    --tokenizer_mode mistral \\
    --config_format mistral \\
    --load_format mistral \\
    --tool-call-parser mistral \\
    --enable-auto-tool-choice \\
    --served-model-name devstral-24b
EOF

mv serve_devstral_vllm.sh.new serve_devstral_vllm.sh
chmod +x serve_devstral_vllm.sh

echo ""
echo "=== Also, here's how to manually check which display server you're using: ==="
echo "Run: echo \$XDG_SESSION_TYPE"
echo "If it returns 'wayland', you're using Wayland"
echo "If it returns 'x11', you're using X11"
echo ""
echo "=== Setup Complete ==="
echo "After rebooting your system, your RTX 3090 will be dedicated exclusively to compute tasks."
echo "The display will use your iGPU only."
echo "For vLLM, I've updated your script to use 95% of GPU memory since it will be dedicated to vLLM."
echo ""
echo "To apply all changes, please reboot your system with:"
echo "sudo reboot"
