#!/bin/bash

#astra pentest trigger variables
ASTRA_SCAN_START_URL="https://api3.getastra.dev/webhooks/integrations/ci-cd"
ASTRA_SCAN_STATUS_URL="https://api3.getastra.dev/webhooks/integrations/ci-cd/scan-status"
ASTRA_AUDIT_MODE="${ASTRA_AUDIT_MODE:-automated}"
ASTRA_SCAN_TYPE="${ASTRA_SCAN_TYPE:-lightning}"
ASTRA_JOB_EXIT_STRATEGY="${ASTRA_JOB_EXIT_STRATEGY:-always_pass}"
ASTRA_JOB_EXIT_REFETCH_INTERVAL="${ASTRA_JOB_EXIT_REFETCH_INTERVAL:-30}"
ASTRA_JOB_EXIT_REFETCH_MAX_RETRIES="${ASTRA_JOB_EXIT_REFETCH_MAX_RETRIES:-20}"
ASTRA_JOB_EXIT_CRITERION="${ASTRA_JOB_EXIT_CRITERION:-severityCount[\\\"high\\\"] > 0 or severityCount[\\\"critical\\\"] > 0}"
ASTRA_SCAN_INVENTORY_COVERAGE="${ASTRA_SCAN_INVENTORY_COVERAGE:-full}"

#astra secret scan variables
ASTRA_SECRET_LATEST_BINARY_VERSION="8.27.2"
ASTRA_SECRET_SCAN_BINARY_VERSION="${ASTRA_SECRET_SCAN_BINARY_VERSION}"
ASTRA_SECRET_SCAN_REPORT_URL="https://api3.getastra.dev/webhooks/integrations/ci-cd/gitleaks"
ASTRA_SECRET_SCAN_CONFIG_PATH="${ASTRA_SECRET_SCAN_CONFIG_PATH:-}"
ASTRA_SECRET_SCAN_GIT_ROOT="${ASTRA_SECRET_SCAN_GIT_ROOT:-}"

# Initialize git metadata variables
if command -v git &> /dev/null; then
    ASTRA_BRANCH_NAME="$(git branch --show-current 2>/dev/null || echo "${CI_COMMIT_REF_NAME:-${GITHUB_REF_NAME:-${ASTRA_BRANCH_NAME}}}")"
    ASTRA_COMMIT_HASH=$(git rev-parse HEAD 2>/dev/null || echo "")
    ASTRA_COMMIT_MESSAGE=$(git log -1 --pretty=%B 2>/dev/null || echo "")
    ASTRA_AUTHOR_NAME=$(git log -1 --pretty=%an 2>/dev/null || echo "")
    ASTRA_AUTHOR_EMAIL=$(git log -1 --pretty=%ae 2>/dev/null || echo "")
    ASTRA_COMMIT_DATE=$(git log -1 --pretty=%ad 2>/dev/null || echo "")
    
    # Only fetch git root if ASTRA_SECRET_SCAN_GIT_ROOT is not provided
    if [ -z "$ASTRA_SECRET_SCAN_GIT_ROOT" ]; then
        ASTRA_GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
        [ -z "$ASTRA_GIT_ROOT" ] && echo "⚠️ Warning: Unable to get git repository root"
    else
        ASTRA_GIT_ROOT="$ASTRA_SECRET_SCAN_GIT_ROOT"
        echo "Using provided git root directory: $ASTRA_GIT_ROOT"
    fi

    # Print warnings for missing data
    [ -z "$ASTRA_BRANCH_NAME" ] && echo "⚠️ Warning: Unable to get branch name"
    [ -z "$ASTRA_COMMIT_HASH" ] && echo "⚠️ Warning: Unable to get commit hash"

    # Prepare vcsMetadata JSON string
    ASTRA_VCS_METADATA=$(cat <<EOF
    {
        "branchName": "$ASTRA_BRANCH_NAME",
        "commitHash": "$ASTRA_COMMIT_HASH",
        "commitMessage": "$ASTRA_COMMIT_MESSAGE",
        "authorName": "$ASTRA_AUTHOR_NAME",
        "authorEmail": "$ASTRA_AUTHOR_EMAIL",
        "date": "$ASTRA_COMMIT_DATE"
    }
EOF
    )
    echo "VCS Metadata prepared: $ASTRA_VCS_METADATA"
else
    echo "⚠️ Warning: git command not found"
    ASTRA_BRANCH_NAME=""
    ASTRA_COMMIT_HASH=""
    ASTRA_COMMIT_MESSAGE=""
    ASTRA_AUTHOR_NAME=""
    ASTRA_AUTHOR_EMAIL=""
    ASTRA_COMMIT_DATE=""
    
    # If git command not found but ASTRA_SECRET_SCAN_GIT_ROOT is provided, use it
    if [ -n "$ASTRA_SECRET_SCAN_GIT_ROOT" ]; then
        ASTRA_GIT_ROOT="$ASTRA_SECRET_SCAN_GIT_ROOT"
        echo "Using provided git root directory: $ASTRA_GIT_ROOT"
    else
        ASTRA_GIT_ROOT=""
        echo "⚠️ Warning: No git root directory available"
    fi

    #keep vcsMetadata as empty json object
    ASTRA_VCS_METADATA="{}"
fi

function runAstraSecretScan() {
    # Where to stash the binary
    BIN_PATH="${HOME}/.astra"    

    # Check if we have a valid git root
    if [ -z "$ASTRA_GIT_ROOT" ]; then
        echo "❌ Error: Could not determine git repository root directory"
        return 0
    fi

    # Detect OS & ARCH for the release asset
    OS="$(uname | tr '[:upper:]' '[:lower:]')"
    ARCH="$(uname -m)"
    if [[ "$ARCH" == "x86_64" ]]; then ARCH="x64"; fi
    if [[ "$ARCH" == "aarch64" ]]; then ARCH="arm64"; fi

    # Handle version logic
    if [[ -z "$ASTRA_SECRET_SCAN_BINARY_VERSION" || "$ASTRA_SECRET_SCAN_BINARY_VERSION" == "latest" ]]; then
        # If empty, use default version
        DOWNLOAD_VERSION="$ASTRA_SECRET_LATEST_BINARY_VERSION"
        BINARY_NAME="astra-secret-scan-latest"
    else
        # Use the specific version provided
        DOWNLOAD_VERSION="$ASTRA_SECRET_SCAN_BINARY_VERSION"
        BINARY_NAME="astra-secret-scan-$ASTRA_SECRET_SCAN_BINARY_VERSION"
    fi

    # Download & unpack on cache miss
    if [[ ! -x "$BIN_PATH/$BINARY_NAME" ]]; then
        echo "Cache miss, Downloading $BINARY_NAME for $OS/$ARCH…"
        DOWNLOAD_URL="https://github.com/gitleaks/gitleaks/releases/download/v${DOWNLOAD_VERSION}/gitleaks_${DOWNLOAD_VERSION}_${OS}_${ARCH}.tar.gz"
        echo "Download URL: $DOWNLOAD_URL"
        
        # Create directory with error handling
        if ! mkdir -p "$BIN_PATH"; then
            echo "❌ Error: Failed to create directory $BIN_PATH"
            return 0
        fi
        
        # Download and extract with error handling
        if ! curl -fsSL "$DOWNLOAD_URL" | tar -xz -C "$BIN_PATH" 2>/dev/null; then
            echo "❌ Error: Failed to download or extract astra-secret-scan binary from $DOWNLOAD_URL"
            return 0
        fi

        # Rename the binary to the appropriate name
        mv "$BIN_PATH/gitleaks" "$BIN_PATH/$BINARY_NAME"

        # Verify the binary exists and is executable
        if [[ ! -x "$BIN_PATH/$BINARY_NAME" ]]; then
            echo "❌ Error: Binary not found or not executable at $BIN_PATH/$BINARY_NAME"
            return 0
        fi
    else
        echo "Cache hit, using cached $BINARY_NAME for $OS/$ARCH"
    fi

    # Run the scan against the current directory
    echo "Running astra-secret-scan detect…"
    echo "Binary location: $BIN_PATH"
    
    if ! ls -ltr "$BIN_PATH" 2>/dev/null; then
        echo "⚠️ Warning: Unable to list binary directory contents"
    fi

    # If ASTRA_SECRET_SCAN_CONFIG is not set, invoke the scan without a config file
    if [ -z "$ASTRA_SECRET_SCAN_CONFIG_PATH" ]; then
        echo "No config file provided, invoking astra-secret-scan without a config file"
        echo "Scanning git repository at: $ASTRA_GIT_ROOT"
        $BIN_PATH/$BINARY_NAME dir "$ASTRA_GIT_ROOT" --report-format=json --report-path=astra-secret-scan-report.json
        #error_output=$("$BIN_PATH/$BINARY_NAME" dir "$ASTRA_GIT_ROOT" --report-format=json --no-banner --max-target-megabytes=1 --exit-code=0 --max-decode-depth=1 --report-path=astra-secret-scan-report.json -v)
        exit_code=$?
        if [ $exit_code -ne 0 ]; then
            echo "❌ Error: Astra Secret Scan without config file failed to complete. Exit code: $exit_code"
            echo "Error details: $error_output"
            return 0
        fi
    else
        echo "Using config file: $ASTRA_SECRET_SCAN_CONFIG_PATH"
        echo "Scanning git repository at: $ASTRA_GIT_ROOT"
        error_output=$("$BIN_PATH/$BINARY_NAME" dir "$ASTRA_GIT_ROOT" --config="$ASTRA_SECRET_SCAN_CONFIG_PATH" --report-format=json --no-banner --max-target-megabytes=1 --exit-code=0 --max-decode-depth=1 --report-path=astra-secret-scan-report.json)
        exit_code=$?
        if [ $exit_code -ne 0 ]; then
            echo "❌ Error: Astra Secret Scan with config file failed to complete. Exit code: $exit_code"
            echo "Error details: $error_output"
            return 0
        fi
    fi

    if [[ ! -f "astra-secret-scan-report.json" ]]; then
        echo "⚠️ Warning: Scan report file not found"
        return 0
    fi

    # Read the report content
    local REPORT_CONTENT
    REPORT_CONTENT=$(cat "astra-secret-scan-report.json")
    if [[ $? -ne 0 ]]; then
        echo "❌ Error: Failed to read scan report"
        return 0
    fi

    # Check if report was generated
    echo "✅ Scan complete. Report at astra-secret-scan-report.json"
    cat astra-secret-scan-report.json

    #Send scan report to Astra Dashboard
    #Use temporary file to avoid "Argument list too long" error with large JSON payloads
    astra_temp_file=$(mktemp)
    cat > "$astra_temp_file" <<EOF
{"version":"1.0.0","accessToken":"$ASTRA_ACCESS_TOKEN","projectId":"$ASTRA_PROJECT_ID", "mode":"$ASTRA_AUDIT_MODE", "automatedScanType":"$ASTRA_SCAN_TYPE", "vcsMetadata":$ASTRA_VCS_METADATA, "report":$REPORT_CONTENT}
EOF
   
    response=$(curl -s -o webhook_response.txt -w "%{http_code}" \
    --user-agent "Astra Pentest Trigger Script/1.1" \
    --header "Content-Type: application/json" \
    --header "Accept: application/json" \
    --request POST \
    --data @"$astra_temp_file" \
    "$ASTRA_SECRET_SCAN_REPORT_URL")
    status_code=$(tail -n1 <<< "$response")

    if [[ "$status_code" == "200" ]]; then
        echo "✅ The Astra Secret Scan report has been successfully sent to Astra Dashboard."
        echo ""
        audit_id=$(awk '/"auditId"/{print $2}' RS=, FS=: webhook_response.txt | tr -d '"' | cut -d'}' -f1)
        echo "Webhook response:"
        echo ""
        cat webhook_response.txt
        echo ""
        cat "vulnerabilitesPageLink: https://my.getastra.com/scans/$audit_id"
        rm -f astra-secret-scan-report.json
    else
        echo "🟡 Astra Secret Scan report sending failed. HTTP status code: $status_code"
        echo ""
        echo "Webhook response:"
        echo ""
        cat webhook_response.txt
        echo ""
        rm -f astra-secret-scan-report.json
        # Clean up temporary file
        rm -f "$astra_temp_file"
        return 0
    fi

    # Clean up temporary file
    rm -f "$astra_temp_file"
    return 0
}

function astraPentestTrigger() {
    if [[ "$ASTRA_JOB_EXIT_STRATEGY" == "wait_for_completion" ]]; then
        # Check if ASTRA_SCAN_TYPE is either 'lightning' or 'emerging' using case
        case "$ASTRA_SCAN_TYPE" in
            "lightning" | "emerging")
                # Valid scan types; do nothing
                ;;
            *)
                # Invalid scan type
                echo "Error: wait_for_completion exit job strategy only supports 'lightning' and 'emerging' scan types."
                exit 1
                ;;
        esac
        if (( ASTRA_JOB_EXIT_REFETCH_INTERVAL * ASTRA_JOB_EXIT_REFETCH_MAX_RETRIES > 900 )); then
            echo "❗ Warning: The pipeline might run for more than 15 minutes due to the current settings of ASTRA_JOB_EXIT_REFETCH_INTERVAL and ASTRA_JOB_EXIT_REFETCH_MAX_RETRIES."
        fi
    fi

    # Send request with vcsMetadata
    response=$(curl -s -o response.txt -w "%{http_code}" --user-agent "Astra Pentest Trigger Script/1.1" --header "Content-Type: application/json" --header "Accept: application/json" --request POST --data "{\"accessToken\":\"$ASTRA_ACCESS_TOKEN\",\"projectId\":\"$ASTRA_PROJECT_ID\", \"mode\":\"$ASTRA_AUDIT_MODE\", \"inventoryCoverage\":\"$ASTRA_SCAN_INVENTORY_COVERAGE\", \"automatedScanType\":\"$ASTRA_SCAN_TYPE\", \"targetScopeUri\":\"$ASTRA_TARGET_SCOPE_URI\", \"vcsMetadata\":$ASTRA_VCS_METADATA}" "$ASTRA_SCAN_START_URL")
    status_code=$(tail -n1 <<< "$response")

    if [[ "$status_code" == "200" ]]; then
        echo "✅ The Astra scan has been successfully initiated."
        audit_id=$(awk '/"auditId"/{print $2}' RS=, FS=: response.txt | tr -d '"' | cut -d'}' -f1)
        vulnerabilities_page_link=$(awk '/"vulnerabilitesPageLink"/{print $2}' RS=, FS=: response.txt | tr -d '"' | cut -d'}' -f1)
        echo ""
        echo "Webhook response:"
        echo ""
        cat response.txt
        echo ""
    else
        echo "🟡 Scan initiation failed. HTTP status code: $status_code"
        echo ""
        echo "Webhook response:"
        echo ""
        cat response.txt
        echo ""
        exit 1
    fi

    if [[ "$ASTRA_JOB_EXIT_STRATEGY" == "always_pass" ]]; then
        echo "The scan is currently in progress, and you can review any detected vulnerabilities in the Astra dashboard. As the ASTRA_JOB_EXIT_STRATEGY is set to always_pass, this job will not be blocked."
        exit 0
    fi

    json_data="{\"accessToken\":\"$ASTRA_ACCESS_TOKEN\",\"auditId\":\"$audit_id\",\"jobExitCriterion\":\"$ASTRA_JOB_EXIT_CRITERION\"}"

    for ((retry=0; retry<ASTRA_JOB_EXIT_REFETCH_MAX_RETRIES; retry++)); do

        scan_status=$(curl -s -o scan_status_response.txt -w "%{http_code}" \
        --user-agent "Astra Pentest Trigger Script/1.1" \
        --header "Content-Type: application/json" \
        --request POST \
        --data "$json_data" \
        "$ASTRA_SCAN_STATUS_URL")

        if [[ "$scan_status" == "200" ]]; then

            audit_progress=$(awk '/"auditProgress"/{print $2}' RS=, FS=: scan_status_response.txt | tr -d '"' | cut -d'}' -f1)
            exit_criteria_evaluation=$(awk '/"exitCriteriaEvaluation"/{print $2}' RS=, FS=: scan_status_response.txt | tr -d '"' | cut -d'}' -f1)

            if [[ "$ASTRA_JOB_EXIT_STRATEGY" == "fail_when_vulnerable" ]]; then
                if [[ "$exit_criteria_evaluation" == "true" ]]; then
                    echo "⛔ Vulnerabilities have been detected according to the criteria defined in ASTRA_JOB_EXIT_CRITERION. Please review the Astra dashboard for a detailed list of vulnerabilities. Exiting the CI/CD job now..."
                    exit 1
                fi
            fi

            if [[ "$audit_progress" == "reported" || "$audit_progress" == "reaudit" || "$audit_progress" == "completed" ]]; then
                echo "✅ The scan has been successfully completed, without matching the exit criteria."
                exit 0
            fi

            echo "🔍 The scan is currently in progress, and its status has just been refreshed."
        else
            echo "🟡 Unable to retrieve scan status. Retrying at the next interval..."
        fi
        sleep "$ASTRA_JOB_EXIT_REFETCH_INTERVAL"
    done

    echo "🔵 The scan is currently underway, but we are exiting this job as the ASTRA_JOB_EXIT_REFETCH_MAX_RETRIES limit has been reached."
}

# Check ASTRA_SCAN_TYPE to determine which scan to run
if [ "${ASTRA_SCAN_TYPE}" = "secret_scanning" ]; then
    echo "ASTRA_SCAN_TYPE is set to 'secret_scanning', running secret scan with version ${ASTRA_SECRET_SCAN_BINARY_VERSION}..."
    runAstraSecretScan
else
    # For any other scan type, run the pentest trigger
    echo "Starting Astra DAST scan with type: ${ASTRA_SCAN_TYPE}..."
    astraPentestTrigger
fi

exit 0