#!/bin/bash
# This script requires curl, jq, and sha256sum
# Currently, the only supported CLI flags are:
# -download-path, -patchline, and -print-version

PATCHLINE="release"
while [ "$#" -gt 0 ]; do
    ARG=$1
    VAL=$2

    if [ $ARG = -print-version ]; then
        PRINT_VERSION="true"
        break
    fi

    if [ $ARG = -download-path ]; then
        FILENAME_OVERRIDE=$VAL
    elif [ $ARG = -patchline ]; then
        PATCHLINE=$VAL
    fi

    shift
    shift
done


if [ -f .hytale-downloader-credentials.json ]; then
    CREDENTIALS=$(cat .hytale-downloader-credentials.json)

    # Check expires_at and ensure refresh token is still valid
    if [ `jq -r .expires_at <<< $CREDENTIALS` -lt `date +%s` ]; then
        REFRESH_RESPONSE=$(
            curl -s -X POST "https://oauth.accounts.hytale.com/oauth2/token" \
                -H "Content-Type: application/x-www-form-urlencoded" \
                -d "client_id=hytale-downloader" \
                -d "grant_type=refresh_token" \
                -d "refresh_token=$(jq -r .refresh_token <<< $CREDENTIALS)"
        )
        CREDENTIALS=$(jq -c -n "{
            \"access_token\": \"$(jq -r .access_token <<< $REFRESH_RESPONSE)\",
            \"refresh_token\": \"$(jq -r .refresh_token <<< $REFRESH_RESPONSE)\",
            \"expires_at\": $(( `date +%s` + `jq -r .expires_in <<< $REFRESH_RESPONSE` )),
            \"branch\": \"$PATCHLINE\"
        }")
        
        # Exit if things went sideways with jq
        if [[ $? -ne 0 ]]; then
            echo "Error occured while parsing refresh response" >&2
            rm .hytale-downloader-credentials.json
            exit 1
        fi
    fi
else
    # Request Device Code
    DEVICE_AUTH=$(
        curl -s -X POST "https://oauth.accounts.hytale.com/oauth2/device/auth" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "client_id=hytale-downloader" \
            -d "scope=offline+auth:downloader"
    )

    DEVICE_CODE=$(jq -r .device_code <<< $DEVICE_AUTH)
    USER_CODE=$(jq -r .user_code <<< $DEVICE_AUTH)
    VERIFICATION_URI=$(jq -r .verification_uri <<< $DEVICE_AUTH)
    VERIFICATION_URI_COMPLETE=$(jq -r .verification_uri_complete <<< $DEVICE_AUTH)
    EXPIRES_IN=$(jq -r .expires_in <<< $DEVICE_AUTH)
    INTERVAL=$(jq -r .interval <<< $DEVICE_AUTH)

    # Display Instructions to User
    echo Please visit the following URL to authenticate:
    echo $VERIFICATION_URI_COMPLETE
    echo Or visit the following URL and enter the code:
    echo $VERIFICATION_URI
    echo Authorization code: $USER_CODE

    # Poll for Token
    TRIES=0
    RESPONSE="error"
    while [[ $RESPONSE == *"error"* ]]; do
        sleep $INTERVAL
        RESPONSE=$(
            curl -s -X POST "https://oauth.accounts.hytale.com/oauth2/token" \
                -H "Content-Type: application/x-www-form-urlencoded" \
                -d "client_id=hytale-downloader" \
                -d "grant_type=urn:ietf:params:oauth:grant-type:device_code" \
                -d "device_code=$DEVICE_CODE"
        )
        TRIES=$((TRIES+1))
        if (( $TRIES >= $EXPIRES_IN / $INTERVAL)); then
            echo "error obtaining token: context deadline exceeded" >&2
            exit 1
        fi
    done

    # Convert credentials to downloader's format
    CREDENTIALS=$(jq -c -n "{
        \"access_token\": \"$(jq -r .access_token <<< $RESPONSE)\",
        \"refresh_token\": \"$(jq -r .refresh_token <<< $RESPONSE)\",
        \"expires_at\": $(( `date +%s` + `jq -r .expires_in <<< $RESPONSE` )),
        \"branch\": \"$PATCHLINE\"
    }")

    # Exit if things went sideways with jq
    if [[ $? -ne 0 ]]; then
        echo "Error occured while parsing response" >&2
        exit 1
    fi
fi

# Save credentials to file
echo $CREDENTIALS > .hytale-downloader-credentials.json

ACCESS_TOKEN=$(jq -r .access_token <<< $CREDENTIALS)

# Get Version Info
VERSION_URL=$(
    curl -s -X GET "https://account-data.hytale.com/game-assets/version/$PATCHLINE.json" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        | jq -r .url
)
VERSION_INFO=$(curl -s -X GET $VERSION_URL)

VERSION=$(jq -r .version <<< $VERSION_INFO)
DOWNLOAD_URL=$(jq -r .download_url <<< $VERSION_INFO)
SHA256=$(jq -r .sha256 <<< $VERSION_INFO)

# Check if the downloader should exit early and print the version
if [[ $PRINT_VERSION = "true" ]]; then
    echo $VERSION
    exit 0
fi

# Get Download URL
ZIP_DOWNLOAD_URL=$(
    curl -s -X GET "https://account-data.hytale.com/game-assets/$DOWNLOAD_URL" \
        -H "Authorization: Bearer $ACCESS_TOKEN" | jq -r .url
)


FILENAME="$VERSION.zip"

# Check if -download-path was set
if [[ -v FILENAME_OVERRIDE ]]; then
    FILENAME=$FILENAME_OVERRIDE
fi

# Check to see if the SHA already matches
if [ -f $FILENAME ]; then
    echo "$SHA256 $FILENAME" | sha256sum --check --status
    if [[ $? -eq 0 ]]; then
        echo "Latest Hytale $PATCHLINE version $VERSION already installed. Skipping"
        exit 0
    fi
fi

echo "downloading latest (\"$PATCHLINE\" patchline) to \"$FILENAME\""

curl -o "$FILENAME" -X GET $ZIP_DOWNLOAD_URL

echo validating checksum...
echo "$SHA256 $FILENAME" | sha256sum --check --status
if [[ $? -ne 0 ]]; then
    echo "SHA256 of the downloaded file does not match!" >&2
    rm $FILENAME
    exit 1
fi

echo "successfully downloaded \"$PATCHLINE\" patchline (version $VERSION)"

exit 0

