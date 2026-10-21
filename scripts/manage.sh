#!/bin/bash
#
# Unified script for managing the ROS development Docker container lifecycle.
#
# Usage: ROS_DISTRO=jazzy ./scripts/manage.sh [start|stop|restart|recreate|logs|exec] [service]
#

set -euo pipefail

# --- Configuration ---
ENV_FILE="$(cd "$(dirname "$0")/.." && pwd)/.env"

# Isaac Sim caches live in external volumes so other projects reuse them by name
# instead of re-downloading ~20 GB of assets and shader cache.
ISAAC_VOLUMES=(
    isaac-sim-cache-kit
    isaac-sim-cache-ov
    isaac-sim-cache-pip
    isaac-sim-cache-glcache
    isaac-sim-cache-compute
    isaac-sim-cache-hub
    isaac-sim-logs
    isaac-sim-config
    isaac-sim-data
    isaac-sim-documents
)

# Load .env first so it wins over any inherited shell values.
if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
else
    echo "Warning: no .env file found at $ENV_FILE; falling back to shell environment and Compose defaults." >&2
fi

# --- Helper Functions ---
function print_usage() {
    echo "Usage: ROS_DISTRO=<humble|jazzy|...> $0 [start|stop|restart|recreate|logs|exec] [service]"
    echo "Note: .env is loaded first when present; otherwise shell environment and Compose defaults are used."
    echo "  start     - Build and start the container in detached mode."
    echo "  stop      - Stop the running container."
    echo "  restart   - Restart the container."
    echo "  recreate  - Stop, remove, and rebuild the container from scratch."
    echo "  logs      - Follow the container's log output."
    echo "  exec      - Attach a bash shell to the running container."
    echo "  clean     - Stop the sim and every replay process, then verify the ROS graph"
    echo "              is empty. Run this before replaying a bag."
    echo
    echo "Services: ros-dev (default), isaac"
    echo "  $0 start isaac   - Start Isaac Sim (first run downloads ~20 GB, allow 20-40 min)"
    echo "  $0 exec isaac    - Shell inside the Isaac Sim container"
}

# Creates the external Isaac volumes if absent. A no-op when they already exist.
function ensure_isaac_volumes() {
    for volume in "${ISAAC_VOLUMES[@]}"; do
        docker volume create "$volume" >/dev/null
    done
}

# --- Main Logic ---
ACTION=${1:-"help"}
SERVICE_NAME=${2:-"ros-dev"}

# The isaac service sits behind a Compose profile and has no build context.
COMPOSE_ARGS=()
BUILD_ARGS=(--build)
if [[ "$SERVICE_NAME" == "isaac" ]]; then
    COMPOSE_ARGS=(--profile isaac)
    BUILD_ARGS=()
    ensure_isaac_volumes
fi

case "$ACTION" in
    start)
    echo "Starting service '${SERVICE_NAME}' for ROS_DISTRO='${ROS_DISTRO:-<from defaults>}'..."
    echo "Granting GUI access (X11)..."
    xhost +local:docker 2>/dev/null || true
    docker compose "${COMPOSE_ARGS[@]}" up -d "${BUILD_ARGS[@]}" "${SERVICE_NAME}"
    echo
    echo "Active services:"
    docker compose "${COMPOSE_ARGS[@]}" ps
    echo
    echo "Service '${SERVICE_NAME}' started. Use './scripts/manage.sh exec ${SERVICE_NAME}' to open a shell."
        ;;
    stop)
        echo "Stopping container..."
        docker compose "${COMPOSE_ARGS[@]}" stop
        echo "Stopped."
        ;;
    restart)
        echo "Restarting container..."
        docker compose "${COMPOSE_ARGS[@]}" restart
        echo "Restarted."
        ;;
    recreate)
    echo "Recreating service '${SERVICE_NAME}' for ROS_DISTRO='${ROS_DISTRO:-<from defaults>}'..."
    echo "Code and data on host are preserved: ./workspace, ./data"
    echo "Granting GUI access (X11)..."
    xhost +local:docker 2>/dev/null || true
    docker compose "${COMPOSE_ARGS[@]}" rm -sf "${SERVICE_NAME}"
    docker compose "${COMPOSE_ARGS[@]}" up -d "${BUILD_ARGS[@]}" "${SERVICE_NAME}"
    echo
    echo "Active services:"
    docker compose "${COMPOSE_ARGS[@]}" ps
    echo "Recreated."
        ;;
    clean)
        # Stops the sim container, then every ROS process in ros-dev, then verifies the
        # graph is empty -- leftovers publishing /clock make a bag replay flicker and RViz
        # crash. Non-zero if anything survives, so it can gate a replay.
        echo "Stopping the Isaac Sim container..."
        docker compose --profile isaac stop isaac 2>/dev/null || true
        ROS_CONTAINER="${CONTAINER_PREFIX:-ros_dev}_${ROS_DISTRO:-jazzy}" \
            ./workspace/src/whycode_sim/whycode_sim/scripts/clean_stack.sh
        ;;
    logs)
        echo "Following container logs (Ctrl+C to exit)..."
        docker compose "${COMPOSE_ARGS[@]}" logs -f "${SERVICE_NAME}"
        ;;
    exec)
        echo "Attaching bash to Compose service '${SERVICE_NAME}'..."
        docker compose "${COMPOSE_ARGS[@]}" exec "${SERVICE_NAME}" bash
        ;;
    *)
        print_usage
        exit 1
        ;;
esac
