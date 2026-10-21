# whycode-bench

A benchmark for the [WhyCode](https://github.com/Adyansh04/whycode) fiducial detector. Isaac Sim
drives a robot past markers in a warehouse and records the camera with exact ground truth; the
detector, and AprilTag detectors for comparison, are then replayed against those bags and scored.
The results are in
[whycode_vision's README](https://github.com/Adyansh04/whycode#compared-with-apriltag).

| Repository | In `workspace/src/` | Holds |
|---|---|---|
| this one | | Docker setup, demo and benchmark scripts |
| [whycode](https://github.com/Adyansh04/whycode) | `whycode_vision` | the detector |
| [whycode-sim](https://github.com/Adyansh04/whycode-sim) | `whycode_sim` | the Isaac Sim scene, bag tools and scoring |

## Requirements

Linux with an X11 desktop, Docker with the NVIDIA Container Toolkit, and an NVIDIA RTX GPU. Isaac
Sim runs at about half real time on a laptop RTX 4080, and its caches take about 20 GB. The Isaac
ROS baseline needs a driver of version 580 or newer.

## Setup

```bash
git clone --recurse-submodules git@github.com:Adyansh04/whycode-bench.git
cd whycode-bench
./scripts/manage.sh start         # the ROS 2 Jazzy container
./scripts/manage.sh exec          # a shell in it, in /root/workspace
colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=RelWithDebInfo
source install/setup.bash
```

The packages are git submodules. `git submodule update --init` fills them in a clone made without
them, and `git submodule update --remote` moves them to their branch tips (`main` for
whycode_vision, `isaac-sim` for whycode_sim). Run git on the host.

## Bags

The recorded loop bags are on
[Hugging Face](https://huggingface.co/datasets/Adyansh/Whycode-isaac-bag). Unpack them into
`./data`, which the containers see as `/root/data`:

```bash
unzip whycode_bench_bags.zip -d data && mv data/whycode_bench_bags/* data/
```

To record your own, start the simulation and follow
[whycode_sim's README](https://github.com/Adyansh04/whycode-sim/tree/isaac-sim#readme).

## Simulation

```bash
./scripts/manage.sh start isaac   # Isaac Sim 6.2.0.1, headless; loads the messages built above
```

The first start streams about 20 GB of assets, for 20-40 minutes with no output. Run
`./scripts/manage.sh clean` before playing a bag: it stops the sim and every ROS process.

## Demo

`scripts/demos/whycode.sh` opens a demo in split panes of one tilix window (a window per command in
other terminals): the detector's log on the left, RViz and the bag player or the simulator on the
right.

```bash
./scripts/benchmark.sh record demo_1lap    # once: a loop bag with Isaac Sim's view of the robot
./scripts/demos/whycode.sh replay          # replay it: space pauses, arrows step and change rate
./scripts/demos/whycode.sh replay bag:=/root/data/whycode_1lap config_file:=...
./scripts/demos/whycode.sh sim             # Isaac Sim live, its viewport following the robot
./scripts/demos/whycode.sh stop            # end whichever demo is running
```

`--print` lists the commands instead of running them. RViz's layout
(`whycode_sim/config/demo.rviz`) is for a maximized window on a screen 1600 px tall; its full
screen (F11) hides the panels.

## Benchmark

`scripts/benchmark.sh` records the comparison bags and scores every detector on them: WhyCode,
WhyCon, AprilTag 3 (`apriltag_ros`, at half and full resolution), NVIDIA's GPU AprilTag detector
(Isaac ROS, in the `isaac-ros` container) and OpenCV's ArUco.

```bash
./scripts/benchmark.sh record      # range, viewing-angle and loop bags, one Isaac run at a time
./scripts/benchmark.sh evaluate    # each detector on each bag, against the ground truth
./scripts/benchmark.sh report      # plots, tables and summary.svg in data/benchmark
```

Each step takes names to run part of it, such as `evaluate whycon` or `record range_whycode_640`.
CPU is measured with only the poses published, so WhyCode's image, debug, TF and RViz outputs are
off, and every detector replays slowly enough to take every frame.

## Scripts and containers

| Command | Does |
|---|---|
| `./scripts/manage.sh start`, `stop`, `restart`, `logs`, `exec` | the ROS container; add `isaac` for the simulator's |
| `./scripts/manage.sh recreate` | rebuilds the ROS container after a change to `.devcontainer/Dockerfile` |
| `./scripts/manage.sh clean` | stops the sim and every ROS process, then checks the graph is empty |

Compose runs three services: `ros-dev` builds and runs everything ROS-side, `isaac` is the stock
Isaac Sim image, and `isaac-ros` holds NVIDIA's AprilTag detector for the benchmark. Each mounts
`./workspace` as `/root/workspace` and `./data` as `/root/data`, uses the host network, and loads
`fastdds.xml`, whose large shared-memory segment keeps 2.8 MB images from stalling. VS Code can
attach through `.devcontainer/devcontainer.json`.

## Troubleshooting

* **RViz or Isaac's window does not open.** Run `xhost +local:docker` (`manage.sh start` does).
* **RViz flickers or crashes on a bag.** Two `/clock` sources are running; run
  `./scripts/manage.sh clean` first.
* **Isaac seems stuck on its first start.** It streams assets for 20-40 minutes without output.
* **The containers do not see each other's topics.** Both take `ROS_DOMAIN_ID` from `.env`
  (default 0).
* **A dependency is missing.** Add it to `.devcontainer/Dockerfile` and run
  `./scripts/manage.sh recreate`; anything installed by hand in the container is lost then.
