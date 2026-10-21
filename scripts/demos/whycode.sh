#!/usr/bin/env bash
# The detector with its debug panels, the markers and their ground truth, and Isaac Sim's view
# of the robot, in RViz (whycode_sim's config/demo.rviz).
#
#   ./scripts/demos/whycode.sh <variant> [name:=value...] [--print]
#
#   replay     a recorded bag, played in its own pane: space pauses it, the arrow keys step it
#              and change its rate. bag:=<path> picks it (default /root/data/demo_1lap, the loop
#              with Isaac Sim's chase camera: ./scripts/benchmark.sh record demo_1lap)
#   sim        Isaac Sim live, its viewer following the robot round the loop.
#              scene:=<path> picks the scene (default config/scene.yaml)
#   stop       end whichever demo is running
#
# Other name:=value arguments go to the detector's launch, whycon_debug.launch.py, such as
# config_file:=... or use_composition:=true. --print lists the commands instead of opening them.
source "$(dirname "$0")/../lib/panes.sh"

BAG=/root/data/demo_1lap
SCENE=/root/workspace/src/whycode_sim/whycode_sim/config/scene.yaml
args=()
for arg in "$@"; do
    case "$arg" in
        bag:=*) BAG=${arg#bag:=} ;;
        scene:=*) SCENE=${arg#scene:=} ;;
        *) args+=("$arg") ;;
    esac
done
parse_args "${args[@]}"

DETECTOR="ros2 launch whycode_vision whycon_debug.launch.py use_sim_time:=true rviz:=false"
RVIZ='rviz2 -d $(ros2 pkg prefix --share whycode_sim)/config/demo.rviz --ros-args -p use_sim_time:=true'

case "$VARIANT" in
    replay)
        container detector "$DETECTOR$LAUNCH_ARGS"
        container rviz "wait_for_node /whycon && $RVIZ"
        container bag "wait_for_node /whycon && ros2 bag play $BAG --clock --loop"
        ;;
    sim)
        container detector "wait_for_topic /camera/image_raw && $DETECTOR$LAUNCH_ARGS"
        host isaac "SCENE_CONFIG=$SCENE ISAAC_HEADLESS=0 docker compose --profile isaac up --force-recreate isaac"
        container robot "wait_for_topic /camera/image_raw && ros2 launch whycode_sim sim.launch.py scene_config:=$SCENE laps:=0"
        container rviz "wait_for_node /whycon && $RVIZ"
        ;;
    *) usage ;;
esac
open_panes "WhyCode: $VARIANT"
