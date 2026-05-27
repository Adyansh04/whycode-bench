# WhyCode Detection & Triangulation Benchmark

This repository contains the development environment for the **WhyCode Detection & Triangulation Benchmark**. It packages the main marker detection logic ([whycode_vision](https://github.com/Adyansh04/whycode)) and the simulation environment ([whycode_sim](https://github.com/Adyansh04/whycode-sim)) into a Docker Compose runtime environment optimized for ROS 2.

- **Docker Compose** is the runtime source of truth.
- **`.devcontainer/devcontainer.json`** provides VS Code integration for developer workspace containment.
- **NVIDIA GPU Acceleration + X11 GUI forwarding** is pre-configured for local rendering.

---

## Setup and Build Instructions

Follow these instructions to clone the parent repository, clone/import dependencies using `vcstool`, and build the workspace.

### 1. Clone the Parent Repository
Clone this repository and navigate to its root directory on your host machine:
```bash
git clone git@github.com:Adyansh04/whycode-bench.git
cd whycode-bench
```

### 2. Import Source Repositories
This project keeps source packages (`whycode_vision` and `whycode_sim`) in separate repositories. Run the following command on your host machine to clone/import them into the `workspace/src` directory:
```bash
# Install vcstool if you do not have it:
sudo apt-get update && sudo apt-get install -y python3-vcstool

# Import the repositories:
vcs import workspace/src < workspace.repos
```

To pull the latest tips for both packages later:
```bash
cd workspace/src
vcs pull
cd ../..
```
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

## Running the Simulation Demo

You can launch the integrated demo containing both the Gazebo world and the WhyCode detector. 

### 1. Launch Options
Inside the container (after sourcing the workspace), run the launch file. We have exposed launch arguments to configure the run dynamically:

#### Option A: Headless Mode (Recommended for Performance, solid 30 FPS)
This runs Gazebo with headless rendering, using EGL GPU acceleration for the camera:
```bash
ros2 launch whycode_vision whycode_demo.launch.py gui:=false
```

#### Option B: GUI Mode
This launches the full Gazebo Harmonic user interface window:
```bash
ros2 launch whycode_vision whycode_demo.launch.py gui:=true
```

#### Option C: Change World or Configuration
You can specify which Gazebo world to load (e.g. `whycode_1.world`, `whycode_2.world`, `whycode_3.world`, `docking.world`):
```bash
ros2 launch whycode_vision whycode_demo.launch.py world:=whycode_3.world gui:=true
```

#### Supported Launch Arguments:
* `world` (default: `whycode_2.world`): World file to load.
* `gui` (default: `true`): Launch Gazebo GUI (`true`/`false`).
* `image_view` (default: `true`): Launch `image_view` node to show result stream (`true`/`false`).
* `use_composition` (default: `false`): Use composable node container for WhyCon.
* `config_file` (default: default sim config): Path to custom WhyCon detector parameters YAML file.

### 2. Monitoring Outputs
Open a separate terminal inside the container (`./scripts/manage.sh exec`) and source `/root/workspace/install/setup.bash`:
* **Echo WhyCode poses:**
  ```bash
  ros2 topic echo /whycon/poses
  ```
* **Run Rqt Image View manually:**
  ```bash
  ros2 run rqt_image_view rqt_image_view
  ```

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
```

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
If rqt or Gazebo GUI fails to open with display errors on host:
```bash
xhost +local:docker
```

### Rebuilding container after Dockerfile changes
If you modify `.devcontainer/Dockerfile` or add system libraries, recreate the container:
```bash
./scripts/manage.sh recreate
```
