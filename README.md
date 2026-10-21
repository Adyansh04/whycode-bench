# WhyCode Detection & Triangulation Benchmark

This repository contains the development environment for the **WhyCode Detection & Triangulation Benchmark**. It packages the main marker detection logic ([whycode_vision](https://github.com/Adyansh04/whycode)) and the simulation environment ([whycode_sim](https://github.com/Adyansh04/whycode-sim)) into a Docker Compose runtime environment optimized for ROS 2.

- **Docker Compose** is the runtime source of truth.
- **`.devcontainer/devcontainer.json`** provides VS Code integration for developer workspace containment.
- **NVIDIA GPU Acceleration + X11 GUI forwarding** is pre-configured for local rendering.

---

## Setup and Build Instructions

Follow these instructions to clone the repository with its two packages and build the workspace.

### 1. Clone the Repository
The packages, `whycode_vision` and `whycode_sim`, are git submodules in `workspace/src`. Clone them
along with this repository:
```bash
git clone --recurse-submodules git@github.com:Adyansh04/whycode-bench.git
cd whycode-bench
```

In a clone made without them: `git submodule update --init`.

### 2. Updating the Packages
The bench pins each package to a commit. To move both to their branch tips (`main` for
whycode_vision, `isaac-sim` for whycode_sim) and record that:
```bash
git submodule update --remote
git add workspace/src/whycode_vision workspace/src/whycode_sim
git commit -m "chore: update the packages"
```

Run git on the host: the containers mount only `./workspace`, and a fresh clone keeps the packages'
git data in this repository's `.git/modules`.

---

## Running the Development Container

We use the helper script `scripts/manage.sh` on the host to manage the container lifecycle.

### 1. Start the Container
Start the container in detached mode. This command automatically handles display (X11) and GPU configuration permissions:
```bash
./scripts/manage.sh start
```

### 2. Open a Shell inside the Container
Attach a bash session to the running container:
```bash
./scripts/manage.sh exec
```

---

## Building & Sourcing the Workspace

All ROS 2 builds must be executed **inside the running container** (the environment attached via `./scripts/manage.sh exec`).

### 1. Navigate to the Workspace Directory
Inside the container, navigate to the ROS 2 workspace:
```bash
cd /root/workspace
```

### 2. Build the ROS 2 Packages
Compile the workspace using `colcon`:
```bash
colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
```

### 3. Source the Workspace Environment
Run the setup script to register the built packages:
```bash
source /root/workspace/install/setup.bash
```

---

## Running the Simulation

The simulation runs in a second container, the stock Isaac Sim 6.2.0.1 image, which publishes the
camera, odometry, TF and marker ground truth to the ROS container. Build the workspace first:
Isaac loads `whycode_sim_msgs` from it. The first start streams about 20 GB of assets (20-40 min).

```bash
./scripts/manage.sh start isaac
```

Recording and replaying bags, the paths and the recorded bags are described in the
[whycode_sim README](https://github.com/Adyansh04/whycode-sim/tree/isaac-sim#readme). Run
`./scripts/manage.sh clean` before replaying a bag: it stops the sim and every ROS process.

The recorded bags (WhyCode and AprilTag; one lap of each path, and three laps at rising speeds) are
on [Hugging Face](https://huggingface.co/datasets/Adyansh/Whycode-isaac-bag). Unpack them into
`./data`, where the containers see them as `/root/data/<bag>`:

```bash
unzip whycode_bench_bags.zip -d data && mv data/whycode_bench_bags/* data/
```

## Benchmark

`scripts/benchmark.sh` records the comparison bags and scores every detector on them: WhyCode,
WhyCon, AprilTag 3 (`apriltag_ros`, at half and full resolution), NVIDIA's GPU AprilTag detector
(Isaac ROS, in its own `isaac-ros` container) and OpenCV's ArUco on the same AprilTag markers.

```bash
./scripts/benchmark.sh record      # the range, viewing-angle and loop bags, one Isaac run at a time
./scripts/benchmark.sh evaluate    # each detector on each bag, against the ground truth
./scripts/benchmark.sh report      # plots, tables and an at-a-glance summary.svg in data/benchmark
```

Each step takes names to run part of it, such as `evaluate whycon` or `record range_whycode_640`.
CPU is measured with only the poses published: WhyCode's `/whycon/poses`, without its image,
debug, TF or RViz output; the tag detectors' poses, which they publish on `/tf` only. Each
detector replays a bag slowly enough to take every frame. Isaac ROS needs an NVIDIA driver 580 or
newer for its CUDA 13 build.

---

## Environment Management (`manage.sh`)

Use the helper script `scripts/manage.sh` to manage the container lifecycle:

```bash
./scripts/manage.sh start     # Build and start the container in detached mode
./scripts/manage.sh stop      # Stop the running container
./scripts/manage.sh restart   # Restart the container
./scripts/manage.sh recreate  # Rebuild and recreate the container from scratch
./scripts/manage.sh logs      # Follow container logs (stdout/stderr)
./scripts/manage.sh exec      # Open a bash terminal inside the container
./scripts/manage.sh clean     # Stop the sim and every ROS process, then check the graph is empty
```

Add `isaac` to `start`, `stop`, `restart`, `recreate`, `logs` or `exec` to act on the Isaac Sim
container instead, e.g. `./scripts/manage.sh exec isaac`.

---

## Mounts

| Host Path | Container Path | Purpose |
|---|---|---|
| `./workspace` | `/root/workspace` | ROS 2 workspace |
| `./data` | `/root/data` | Shared files (bags, datasets, configs) |
| `./.vscode` | `/root/workspace/.vscode` | VS Code workspace config |
| `./.clangd` | `/root/workspace/.clangd` | clangd config |
| `./.clang-format` | `/root/workspace/.clang-format` | C/C++ format style |
| `./ruff.toml` | `/root/workspace/ruff.toml` | Ruff lint/format config |
| `${HOME}/.ssh` | `/root/.ssh` (ro) | SSH credentials |
| `/dev` | `/dev` | Hardware device access |
| `/tmp/.X11-unix` | `/tmp/.X11-unix` | GUI socket |

---

## Tooling & Formatters

- **C++:** Formatting uses `clang-format` based on the local `.clang-format` file. Language server support is managed by `clangd` using the exported `compile_commands.json`.
- **Python:** Linting and formatting is managed by Ruff using `/root/workspace/ruff.toml`.
- **Manual Formatting:** Trigger formatting manually using `Format Document` (`Ctrl+Shift+I`) inside VS Code.

---

## Troubleshooting

### GUI Apps do not open
If rqt or RViz fails to open with display errors on host:
```bash
xhost +local:docker
```

### Rebuilding container after Dockerfile changes
If you modify `.devcontainer/Dockerfile` or add system libraries, recreate the container:
```bash
./scripts/manage.sh recreate
```
