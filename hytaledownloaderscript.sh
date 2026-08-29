#!/bin/bash
# This script requires curl, jq, and shasum
# Currently, the only supported CLI flags are:
# -download-path, -patchline, and -print-version

# Dependency checks
for DEP in curl jq shasum; do
    if ! command -v "$DEP" &> /dev/null; then
        echo "Please install the \"$DEP\" package" >&2
        exit 1
    fi
done

# Parse args
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

# Set up error messages
ERR_PRINT_VERSION="error printing version"
ERR_FETCHING_MANIFEST="error fetching manifest: could not get signed URL for manifest: could not get signed URL"
ERR_FORBIDDEN="$ERR_FETCHING_MANIFEST: HTTP status: 403 Forbidden"
ERR_OAUTH="$ERR_FETCHING_MANIFEST: Get \"https://account-data.hytale.com/game-assets/version/$PATCHLINE.json\": oauth2"

# Prepend -print-version error
if [[ $PRINT_VERSION = "true" ]]; then
    ERR_FORBIDDEN="$ERR_PRINT_VERSION: $ERR_FORBIDDEN"
    ERR_OAUTH="$ERR_PRINT_VERSION: $ERR_OAUTH"
fi


if [ -f .hytale-downloader-credentials.json ]; then
    CREDENTIALS=$(cat .hytale-downloader-credentials.json)

    # Default to 0 if expires_at is not present (as Golang would)
    EXPIRES_AT=$(jq .expires_at <<< $CREDENTIALS)
    if [[ $? -ne 0 || $EXPIRES_AT = "null" || -z $EXPIRES_AT ]]; then
        EXPIRES_AT=0
    fi

    # Check expires_at and ensure refresh token is still valid
    if [ $EXPIRES_AT -lt `date +%s` ]; then
        # Throw OAuth error if refresh token is empty or not present
        CRED_REFRESH_TOKEN=$(jq -r .refresh_token <<< $CREDENTIALS)
        if [[ $? -ne 0 || $CRED_REFRESH_TOKEN = "null" || -z $CRED_REFRESH_TOKEN ]]; then
            echo "$ERR_OAUTH: token expired and refresh token is not set" >&2
            exit 1
        fi

        REFRESH_RESPONSE=$(
            curl -s -X POST "https://oauth.accounts.hytale.com/oauth2/token" \
                -H "Content-Type: application/x-www-form-urlencoded" \
                -d "client_id=hytale-downloader" \
                -d "grant_type=refresh_token" \
                -d "refresh_token=$CRED_REFRESH_TOKEN"
        )
        
        # Check response for errors
        if [[ $REFRESH_RESPONSE == *"\"error\":"* ]]; then
            ERROR=$(jq -r .error <<< $REFRESH_RESPONSE)
            ERROR_DESCRIPTION=$(jq -r .error_description <<< $REFRESH_RESPONSE)
            echo "$ERR_OAUTH: \"$ERROR\" \"$ERROR_DESCRIPTION\"" >&2
            exit 1
        fi

        CREDENTIALS=$(jq -c -n "{
            \"access_token\": \"$(jq -r .access_token <<< $REFRESH_RESPONSE)\",
            \"refresh_token\": \"$(jq -r .refresh_token <<< $REFRESH_RESPONSE)\",
            \"expires_at\": $(( `date +%s` + `jq -r .expires_in <<< $REFRESH_RESPONSE` )),
            \"branch\": \"$PATCHLINE\"
        }")
        
        # Fallback if error wasn't caught
        if [[ $? -ne 0 ]]; then
            echo "Error occured while parsing refresh response" >&2
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
    RESPONSE="\"error\":\"authorization_pending\""
    while [[ $RESPONSE == *"\"error\":\"authorization_pending\""* ]]; do
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

    # Check response for errors
    if [[ $RESPONSE == *"\"error\":"* ]]; then
        ERROR=$(jq -r .error <<< $RESPONSE)
        ERROR_DESCRIPTION=$(jq -r .error_description <<< $RESPONSE)
        echo "$ERR_OAUTH: \"$ERROR\" \"$ERROR_DESCRIPTION\"" >&2
        exit 1
    fi
    

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

# Throw early if access_token cannot be read
# TODO: attempt a refresh and return ERR_FORBIDDEN if that still doesn't work
if [[ $? -ne 0 || -z $ACCESS_TOKEN ]]; then
    echo $ERR_FORBIDDEN >&2
    exit 1
fi


# Get URL to version manifest
VERSION_URL_RES=$(
    curl -s -X GET "https://account-data.hytale.com/game-assets/version/$PATCHLINE.json" \
        -H "Authorization: Bearer $ACCESS_TOKEN"
)

# Check response for invalid access_token or invalid patchline responses
if [[ $VERSION_URL_RES == "invalid token" || $VERSION_URL_RES == "no access to patchline" ]]; then
    echo $ERR_FORBIDDEN >&2
    exit 1
fi


# Parse patchline JSON URL
PATCHLINE_JSON_URL=$(jq -r .url <<< $VERSION_URL_RES)
if [[ $? -ne 0 ]]; then
    echo "\"url\" property not found in patchline URL query" >&2
    exit 1
fi

# Grab patchline JSON
PATCHLINE_JSON=$(curl -s -X GET $PATCHLINE_JSON_URL)

VERSION=$(jq -r .version <<< $PATCHLINE_JSON)

# If the version parse fails, the others probably will as well
if [[ $? -ne 0 ]]; then
    echo "\"version\" property not found in patchline JSON." >&2
    echo "Request response for debugging purposes:"
    echo $PATCHLINE_JSON
    exit 1
fi

DOWNLOAD_URL=$(jq -r .download_url <<< $PATCHLINE_JSON)
SHA256=$(jq -r .sha256 <<< $PATCHLINE_JSON)


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

if [[ $ZIP_DOWNLOAD_URL == "invalid token" ]]; then
    echo $ERR_FORBIDDEN >&2
    exit 1
fi


FILENAME="$VERSION.zip"

# Check if -download-path was set
if [[ -v FILENAME_OVERRIDE ]]; then
    FILENAME=$FILENAME_OVERRIDE
fi

# Check to see if the SHA already matches
if [ -f $FILENAME ]; then
    echo "Validating the checksum of the existing file, $FILENAME"
    if shasum -sc -a 256 <<< "$SHA256  $FILENAME"; then
        echo "Latest Hytale $PATCHLINE version $VERSION already installed. Skipping"
        exit 0
    fi
    echo "File checksum doesn't match, continuing download"
fi

echo "downloading latest (\"$PATCHLINE\" patchline) to \"$FILENAME\""

curl --progress-bar --stderr /dev/stdout -o "$FILENAME" -X GET $ZIP_DOWNLOAD_URL

echo validating checksum...
if ! shasum -sc -a 256 <<< "$SHA256  $FILENAME"; then
    echo "SHA256 of the downloaded file does not match!" >&2
    rm $FILENAME
    exit 1
fi

echo "successfully downloaded \"$PATCHLINE\" patchline (version $VERSION)"

exit 0

