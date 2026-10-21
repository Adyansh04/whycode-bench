#!/usr/bin/env bash
# Records the comparison bags and scores every detector on them, from the host.
#
#   ./scripts/benchmark.sh record [name...]     record bags, all by default; one Isaac at a time
#   ./scripts/benchmark.sh evaluate [name...]   run the detectors on the bags and score them; names
#                                               pick detectors or bags, all by default
#   ./scripts/benchmark.sh report               plots and tables from the scores
#   ./scripts/benchmark.sh list                 the recordings
#
# Each recording is a scene variant written to data/scenes/<name>.yaml: a packaged scene with
# the marker family and camera swapped. Bags land in data/<name>, scores in
# data/benchmark/<detector>/<bag>, logs in data/logs. A recording or replay that fails is
# reported and left out; the others carry on.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SCENES=/root/workspace/src/whycode_sim/whycode_sim/config
TOOLS=/root/workspace/src/whycode_sim/whycode_sim/scripts

# name, base scene, family, then optionally camera width, height and horizontal FOV. The range
# cameras are a RealSense D435's colour camera: fx 606.2 px at 640x480, 909.4 px at 1280x720
# and 1364.1 px at 1920x1080. The loops keep scene.yaml's camera, as the existing loop bags do;
# demo_1lap adds Isaac Sim's chase camera for the demo (scripts/demos/whycode.sh).
RECORDINGS=(
    "range_whycode_640    scene_range.yaml whycode  640  480 55.58"
    "range_whycode_1280   scene_range.yaml whycode  1280 720 70.26"
    "range_whycode_1920   scene_range.yaml whycode  1920 1080 70.26"
    "range_whycon_640     scene_range.yaml whycon   640  480 55.58"
    "range_whycon_1280    scene_range.yaml whycon   1280 720 70.26"
    "range_whycon_1920    scene_range.yaml whycon   1920 1080 70.26"
    "range_apriltag_640   scene_range.yaml apriltag 640  480 55.58"
    "range_apriltag_1280  scene_range.yaml apriltag 1280 720 70.26"
    "range_apriltag_1920  scene_range.yaml apriltag 1920 1080 70.26"
    "angle_whycode        scene_angle.yaml whycode"
    "angle_whycon         scene_angle.yaml whycon"
    "angle_apriltag       scene_angle.yaml apriltag"
    "whycon_1lap          scene.yaml       whycon"
    "apriltag_1lap        scene.yaml       apriltag"
    "demo_1lap            scene_demo.yaml  whycode"
)

# Detector, the marker family of the bags it reads (its range bags, angle bag and loop), and the
# playback rate: slow enough that it takes every frame. whycode_1lap is the original loop.
DETECTORS=(
    "whycode        whycode  1.0"
    "whycon         whycon   1.0"
    "apriltag       apriltag 0.5"
    "apriltag_full  apriltag 0.25"
    "aruco          apriltag 0.5"
    "isaac_apriltag apriltag 1.0"
)
RESULTS=/root/data/benchmark

usage() {
    sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p}' "$0"
    exit "${1:-1}"
}

in_ros() {
    docker compose exec -T ros-dev bash -c "source /root/workspace/install/setup.bash && $1"
}

stop_isaac() {
    docker compose --profile isaac stop isaac >/dev/null 2>&1 || true
    docker compose --profile isaac rm -f isaac >/dev/null 2>&1 || true
}

spec() {
    local entry
    for entry in "${RECORDINGS[@]}"; do
        read -r -a fields <<<"$entry"
        [[ "${fields[0]}" == "$1" ]] && return 0
    done
    echo "unknown recording: $1" >&2
    return 1
}

record_one() {
    local name=$1 log scene variant laps=""
    spec "$name" || return 1
    log="data/logs/$name.log"
    scene=$SCENES/${fields[1]}
    variant=/root/data/scenes/$name.yaml
    {
        printf 'extends: %s\nmarker:\n  family: %s\n' "$scene" "${fields[2]}"
        if ((${#fields[@]} > 3)); then
            printf 'camera:\n  width: %s\n  height: %s\n  hfov_deg: %s\n' \
                "${fields[3]}" "${fields[4]}" "${fields[5]}"
        fi
    } | docker compose exec -T ros-dev bash -c "mkdir -p /root/data/scenes /root/data/logs && cat > $variant"
    [[ "$name" == *_1lap ]] && laps="--laps 1"

    echo "== $name: $(date +%H:%M:%S)"
    ./scripts/manage.sh clean >/dev/null 2>&1
    stop_isaac
    SCENE_CONFIG=$variant ISAAC_HEADLESS=1 docker compose --profile isaac up -d --force-recreate isaac \
        >/dev/null 2>&1 || { echo "   Isaac did not start"; return 1; }

    # A first start compiles shaders for minutes; frames are the sign it is ready
    local waited=0
    until in_ros "python3 $TOOLS/check_camera.py --timeout 20" >>"$log" 2>&1; do
        waited=$((waited + 20))
        if ((waited > 900)); then
            echo "   no frames after 15 min"
            stop_isaac
            return 1
        fi
    done

    in_ros "ros2 launch whycode_sim sim.launch.py record:=true scene_config:=$variant \
        bag_prefix:=/root/data/raw_$name laps:=1" >>"$log" 2>&1
    stop_isaac
    in_ros "rm -rf /root/data/$name && python3 $TOOLS/retime_bag.py /root/data/raw_$name /root/data/$name \
        && python3 $TOOLS/check_bag.py /root/data/$name --scene $variant $laps" >>"$log" 2>&1
    local status=$?
    tail -n 12 "$log" | sed 's/^/   /'
    if ((status == 0)); then
        in_ros "rm -rf /root/data/raw_$name"
    else
        echo "   FAILED: kept /root/data/raw_$name"
    fi
    return $status
}

evaluate_one() {
    local detector=$1 bag=$2 rate=$3 scene=/root/data/scenes/$2.yaml match=id out
    in_ros "test -f $scene" || scene=$SCENES/scene.yaml
    [[ "$detector" == whycon ]] && match=position
    out=$RESULTS/$detector/$bag
    echo "== $detector on $bag: $(date +%H:%M:%S)"
    ./scripts/manage.sh clean >/dev/null 2>&1
    in_ros "test -d /root/data/$bag" || { echo "   no bag"; return 1; }
    if [[ "$detector" == isaac_apriltag ]]; then
        # NVIDIA's detector runs in its own container, on the GPU
        docker rm -f whycode_isaac_ros >/dev/null 2>&1
        docker compose --profile isaac-ros run -d --rm --name whycode_isaac_ros isaac-ros bash -c \
            "source /opt/ros/jazzy/setup.bash && ros2 launch \
            /root/workspace/src/whycode_sim/whycode_sim/launch/isaac_ros_apriltag.launch.py" \
            >/dev/null || { echo "   isaac-ros did not start"; return 1; }
    fi
    in_ros "python3 $TOOLS/replay_detector.py /root/data/$bag --detector $detector --scene $scene \
        --out $out --rate $rate && python3 $TOOLS/evaluate.py $out --scene $scene --match $match" \
        >>"data/logs/evaluate_${detector}_$bag.log" 2>&1
    local status=$?
    [[ "$detector" == isaac_apriltag ]] && docker rm -f whycode_isaac_ros >/dev/null 2>&1
    tail -n 4 "data/logs/evaluate_${detector}_$bag.log" | sed 's/^/   /'
    return $status
}

command=${1:-}
shift || true
case "$command" in
    list)
        printf '%s\n' "${RECORDINGS[@]}"
        ;;
    record)
        names=("$@")
        if ((${#names[@]} == 0)); then
            for entry in "${RECORDINGS[@]}"; do names+=("${entry%% *}"); done
        fi
        mkdir -p data/logs 2>/dev/null || true
        failed=()
        for name in "${names[@]}"; do
            record_one "$name" || failed+=("$name")
        done
        ./scripts/manage.sh clean >/dev/null 2>&1
        echo "recorded ${#names[@]} bags; failed: ${failed[*]:-none}"
        ((${#failed[@]} == 0))
        ;;
    evaluate)
        # Names are detectors or bags; each kind given narrows its own
        detectors=" " bags=" "
        for name in "$@"; do
            if printf '%s\n' "${DETECTORS[@]}" | grep -q "^$name "; then
                detectors+="$name "
            else
                bags+="$name "
            fi
        done
        failed=()
        for entry in "${DETECTORS[@]}"; do
            read -r detector family rate <<<"$entry"
            [[ "$detectors" == " " || "$detectors" == *" $detector "* ]] || continue
            for bag in range_${family}_640 range_${family}_1280 range_${family}_1920 \
                angle_$family ${family}_1lap; do
                [[ "$bags" == " " || "$bags" == *" $bag "* ]] || continue
                evaluate_one "$detector" "$bag" "$rate" || failed+=("$detector/$bag")
            done
        done
        ./scripts/manage.sh clean >/dev/null 2>&1
        echo "failed: ${failed[*]:-none}"
        ((${#failed[@]} == 0))
        ;;
    report)
        in_ros "python3 $TOOLS/benchmark_report.py $RESULTS"
        ;;
    -h | --help | help | "") usage 0 ;;
    *) usage ;;
esac
