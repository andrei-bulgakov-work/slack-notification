#!/usr/bin/env bash

set -euo pipefail

# Send a Slack notification about a failed workflow
# Usage: ./notify_slack.sh --webhook=URL --workflow-name=NAME --conclusion=CONCLUSION --run-id=RUN_ID --workflow-path=PATH [--pr-number=PR] [--branch-name=BRANCH]

# Initialize variables
WEBHOOK_URL=""
WORKFLOW_NAME=""
CONCLUSION=""
TRIGGERED_WORKFLOW_RUN_ID=""
WORKFLOW_PATH=""
PR_NUMBER=""
BRANCH_NAME=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
    -w | --webhook)
        WEBHOOK_URL="$2"
        shift 2
        ;;
    --webhook=*)
        WEBHOOK_URL="${1#*=}"
        shift
        ;;
    -n | --workflow-name)
        WORKFLOW_NAME="$2"
        shift 2
        ;;
    --workflow-name=*)
        WORKFLOW_NAME="${1#*=}"
        shift
        ;;
    -c | --conclusion)
        CONCLUSION="$2"
        shift 2
        ;;
    --conclusion=*)
        CONCLUSION="${1#*=}"
        shift
        ;;
    -r | --run-id)
        TRIGGERED_WORKFLOW_RUN_ID="$2"
        shift 2
        ;;
    --run-id=*)
        TRIGGERED_WORKFLOW_RUN_ID="${1#*=}"
        shift
        ;;
    -p | --workflow-path)
        WORKFLOW_PATH="$2"
        shift 2
        ;;
    --workflow-path=*)
        WORKFLOW_PATH="${1#*=}"
        shift
        ;;
    --pr-number)
        PR_NUMBER="$2"
        shift 2
        ;;
    --pr-number=*)
        PR_NUMBER="${1#*=}"
        shift
        ;;
    -b | --branch-name)
        BRANCH_NAME="$2"
        shift 2
        ;;
    --branch-name=*)
        BRANCH_NAME="${1#*=}"
        shift
        ;;
    -h | --help)
        cat <<EOF
Usage: $0 [OPTIONS]

Required arguments:
  -w, --webhook=URL                 Slack webhook URL
  -n, --workflow-name=NAME          Workflow display name
  -c, --conclusion=CONCLUSION       Workflow conclusion (failure/timed_out/cancelled)
  -r, --run-id=RUN_ID              Workflow run ID
  -p, --workflow-path=PATH          Path to workflow file

Optional arguments:
  --pr-number=NUMBER                Pull request number (if PR event)
  -b, --branch-name=NAME            Branch name (if push event)
  -h, --help                        Show this help message

Examples:
  $0 --webhook=https://hooks.slack.com/... --workflow-name="CI/CD Pipeline" \\
     --conclusion=failure --run-id=12345 --workflow-path=.github/workflows/main.yaml

  $0 -w https://hooks.slack.com/... -n "CI/CD Pipeline" -c failure \\
     -r 12345 -p .github/workflows/main.yaml --pr-number=42
EOF
        exit 0
        ;;
    *)
        echo "Error: Unknown option: $1" >&2
        echo "Use --help for usage information" >&2
        exit 1
        ;;
    esac
done

# Validate required arguments
ERRORS=()
[[ -z "$WEBHOOK_URL" ]] && ERRORS+=("--webhook is required")
[[ -z "$WORKFLOW_NAME" ]] && ERRORS+=("--workflow-name is required")
[[ -z "$CONCLUSION" ]] && ERRORS+=("--conclusion is required")
[[ -z "$TRIGGERED_WORKFLOW_RUN_ID" ]] && ERRORS+=("--run-id is required")
[[ -z "$WORKFLOW_PATH" ]] && ERRORS+=("--workflow-path is required")

if [[ ${#ERRORS[@]} -gt 0 ]]; then
    echo "Error: Missing required arguments:" >&2
    for error in "${ERRORS[@]}"; do
        echo "  - $error" >&2
    done
    echo "" >&2
    echo "Use --help for usage information" >&2
    exit 1
fi

# Determine title and icon based on conclusion
case "${CONCLUSION,,}" in
failure)
    STATUS="failed"
    ICON="❌"
    ;;
timed_out)
    STATUS="timed out"
    ICON="⌛"
    ;;
cancelled)
    STATUS="cancelled"
    ICON="🚫"
    ;;
*)
    STATUS="failed (${CONCLUSION})"
    ICON="🔴"
    ;;
esac

# Extract workflow filename from path (e.g., ".github/workflows/main.yaml" -> "main.yaml")
WORKFLOW_FILENAME=$(basename "$WORKFLOW_PATH")

# Construct workflow runs URL
WORKFLOW_RUNS_URL="https://github.com/${GITHUB_REPOSITORY}/actions/workflows/${WORKFLOW_FILENAME}"

# Build title with clickable workflow name
TITLE="Workflow ${STATUS}"

# Extract repository name from GITHUB_REPOSITORY (format: owner/repo)
REPO_NAME="${GITHUB_REPOSITORY#*/}"
REPO_URL="https://github.com/${GITHUB_REPOSITORY}"

# Construct workflow run URL
# Format: https://github.com/{owner}/{repo}/actions/runs/{run_id}
WORKFLOW_RUN_URL="https://github.com/${GITHUB_REPOSITORY}/actions/runs/${TRIGGERED_WORKFLOW_RUN_ID}"
WORKFLOW_RUN_ID="$TRIGGERED_WORKFLOW_RUN_ID"

# Build the message text with repository and workflow run info
MESSAGE_TEXT="${ICON} *${TITLE}: <${WORKFLOW_RUNS_URL}|${WORKFLOW_NAME}>*"
MESSAGE_TEXT="${MESSAGE_TEXT}\nRepository: <${REPO_URL}|${REPO_NAME}>"
MESSAGE_TEXT="${MESSAGE_TEXT}\nWorkflow Run: <${WORKFLOW_RUN_URL}|${WORKFLOW_RUN_ID}>"

# Add PR or Branch information if available
if [[ -n "$PR_NUMBER" ]]; then
    PR_URL="https://github.com/${GITHUB_REPOSITORY}/pull/${PR_NUMBER}"
    MESSAGE_TEXT="${MESSAGE_TEXT}\nPull Request: <${PR_URL}|#${PR_NUMBER}>"
elif [[ -n "$BRANCH_NAME" ]]; then
    BRANCH_URL="https://github.com/${GITHUB_REPOSITORY}/tree/${BRANCH_NAME}"
    MESSAGE_TEXT="${MESSAGE_TEXT}\nBranch: <${BRANCH_URL}|${BRANCH_NAME}>"
fi

# Create Slack message payload with blocks
# Using mrkdwn format for markdown support
MESSAGE_PAYLOAD=$(
    cat <<EOF
{
  "blocks": [
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "${MESSAGE_TEXT}"
      }
    }
  ]
}
EOF
)

# Send the notification to Slack
HTTP_STATUS=$(curl \
    -w "\n%{http_code}" \
    -X POST \
    -H 'Content-type: application/json' \
    --data "$MESSAGE_PAYLOAD" \
    "$WEBHOOK_URL" \
    -s -o /tmp/slack_response.txt)

RESPONSE_CODE=$(echo "$HTTP_STATUS" | tail -1)
RESPONSE_BODY=$(cat /tmp/slack_response.txt)

if [[ "$RESPONSE_CODE" == "200" ]]; then
    echo "✓ Slack notification sent successfully"
    exit 0
else
    echo "✗ Failed to send Slack notification" >&2
    echo "HTTP Status: $RESPONSE_CODE" >&2
    echo "Response: $RESPONSE_BODY" >&2
    exit 1
fi
