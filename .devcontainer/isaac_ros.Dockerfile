# NVIDIA's GPU AprilTag detector (Isaac ROS 4.0 on ROS 2 Jazzy), a baseline the benchmark compares
# WhyCode against. CUDA 13.0, which Isaac ROS 4.0 is built for, from the base image; ROS and the
# Isaac ROS packages from their apt repositories. Needs an NVIDIA driver 580 or newer.
FROM nvcr.io/nvidia/cuda:13.0.2-runtime-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 ROS_DISTRO=jazzy

RUN apt-get update && apt-get install -y curl gnupg ca-certificates && \
    curl -fsSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
        -o /usr/share/keyrings/ros-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu noble main" \
        > /etc/apt/sources.list.d/ros2.list && \
    curl -fsSL https://isaac.download.nvidia.com/isaac-ros/repos.key \
        | gpg --dearmor -o /usr/share/keyrings/nvidia-isaac-ros.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/nvidia-isaac-ros.gpg] https://isaac.download.nvidia.com/isaac-ros/release-4.0 noble main" \
        > /etc/apt/sources.list.d/nvidia-isaac-ros.list && \
    apt-get update && apt-get install -y \
        ros-jazzy-ros-base \
        ros-jazzy-rmw-fastrtps-cpp \
        ros-jazzy-isaac-ros-apriltag \
    && rm -rf /var/lib/apt/lists/*

# The AprilTag node links NVIDIA VPI 4 (libnvvpi.so.4) without declaring it; it ships in the
# Jetson x86_64 repository
RUN curl -fsSL https://repo.download.nvidia.com/jetson/jetson-ota-public.asc \
        | gpg --dearmor -o /usr/share/keyrings/nvidia-jetson.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/nvidia-jetson.gpg] https://repo.download.nvidia.com/jetson/x86_64/noble r38.4 main" \
        > /etc/apt/sources.list.d/nvidia-jetson.list && \
    apt-get update && apt-get install -y libnvvpi4 && rm -rf /var/lib/apt/lists/*

WORKDIR /root/workspace
