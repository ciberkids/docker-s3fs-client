#! /usr/bin/env sh
set -x
# Where are we going to mount the remote bucket resource in our container.
export DEST=${AWS_S3_MOUNT:-/opt/s3fs/bucket}

# Check variables and defaults
if [ -z "${AWS_S3_ACCESS_KEY_ID}" \
-a -z "${AWS_S3_SECRET_ACCESS_KEY}" \
-a -z "${AWS_S3_SECRET_ACCESS_KEY_FILE}" \
-a -z "${AWS_S3_AUTHFILE}" \
-a -z "${AWS_S3_SESSION_TOKEN}" \
-a -z "${AWS_IAM_ROLE}" \
]; then
    echo "You need to provide some credentials!!"
    exit
fi

export AWSACCESSKEYID=${AWS_S3_ACCESS_KEY_ID}
export AWSSECRETACCESSKEY=${AWS_S3_SECRET_ACCESS_KEY}
export AWSSESSIONTOKEN=${AWS_S3_SESSION_TOKEN}


if [ -z "${AWS_S3_BUCKET}" ]; then
    echo "No bucket name provided!"
    exit
fi
if [ -z "${AWS_S3_URL}" ]; then
    export AWS_S3_URL="https://s3.amazonaws.com"
fi

if [ -n "${AWS_S3_SECRET_ACCESS_KEY_FILE}" ]; then
    export AWS_S3_SECRET_ACCESS_KEY=$(read ${AWS_S3_SECRET_ACCESS_KEY_FILE})
fi

# Create or use authorisation file
if [ -z "${AWS_S3_AUTHFILE}" ]; then
    export AWS_S3_AUTHFILE=/opt/s3fs/passwd-s3fs
    echo "${AWS_S3_ACCESS_KEY_ID}:${AWS_S3_SECRET_ACCESS_KEY}" > ${AWS_S3_AUTHFILE}
    chmod 600 ${AWS_S3_AUTHFILE}
fi

if [ ${S3FS_DEBUG} = "1" ]; then
    cat ${AWS_S3_AUTHFILE}
fi

# forget about the password once done (this will have proper effects when the
# PASSWORD_FILE-version of the setting is used)
if [ -n "${AWS_S3_SECRET_ACCESS_KEY}" ]; then
    unset AWS_S3_SECRET_ACCESS_KEY
fi

# Create destination directory if it does not exist.
mkdir -p ${DEST}

export GROUP_NAME=$(getent group "${GID}" | cut -d":" -f1)

# Add a group
if [ $GID -gt 0 -a -z "${GROUP_NAME}" ]; then
    addgroup -g ${GID} -S ${GID}
    export GROUP_NAME=${GID}
fi

# Add a user
if [ ${UID} -gt 0 ]; then
    adduser -u ${UID} -D -G ${GROUP_NAME} ${UID}
    export RUN_AS=${UID}
    chown ${UID}:${GID} ${DEST}
    chown ${UID}:${GID} ${AWS_S3_AUTHFILE}
    chown ${UID}:${GID} /opt/s3fs

fi

echo "Testing mounting dir"
ls -la ${DEST}/../

ls -la ${DEST}


# Debug options
export DEBUG_OPTS=
if [ ${S3FS_DEBUG} = "1" ]; then
    export DEBUG_OPTS="-d -d"
fi

# Additional S3FS options
if [ -n "$S3FS_ARGS" ]; then
    export S3FS_ARGS="-o $S3FS_ARGS"
fi

# Mount and verify that something is present. davfs2 always creates a lost+found
# sub-directory, so we can use the presence of some file/dir as a marker to
# detect that mounting was a success. Execute the command on success.
if [ -z "${AWS_IAM_ROLE}" -a -z "${AWS_S3_SESSION_TOKEN}" ]; then
    echo "Using Credential"

    sudo -u ${RUN_AS} -E s3fs ${DEBUG_OPTS} ${S3FS_ARGS} \
        -o passwd_file=${AWS_S3_AUTHFILE} \
        -o url=${AWS_S3_URL} \
        -o uid=${UID} \
        -o gid=${GID} \
        ${AWS_S3_BUCKET} ${DEST}

elif [ -z "${AWS_IAM_ROLE}" -a -n "${AWS_S3_SESSION_TOKEN}" ]; then
    echo "Using session Token"
    echo "RUN AS: ${RUN_AS}"

    sudo -u ${RUN_AS} -E s3fs -o retries=20 \
    -o uid=${UID} \
    -o gid=${GID} \
    ${AWS_S3_BUCKET} ${DEST}

elif [ -n "${AWS_IAM_ROLE}" -a -z "${AWS_S3_SESSION_TOKEN}" ]; then
    echo "Using IAM ROLE"
    sudo -u ${RUN_AS} -E s3fs ${DEBUG_OPTS} ${S3FS_ARGS} \
        -o iam_role=${AWS_IAM_ROLE} \
        -o url=${AWS_S3_URL} \
        -o uid=${UID} \
        -o gid=${GID} \
        ${AWS_S3_BUCKET} ${AWS_S3_MOUNT}

else 
    echo "MOUNT FAILURE no credentials"
    exit 1
fi
# s3fs can claim to have a mount even though it didn't succeed.
# Doing an operation actually forces it to detect that and remove the mount.
ls -la "${DEST}"

ls -la "${DEST}/../"

sudo -u ${RUN_AS} ls -la "${DEST}/../"
sudo -u ${RUN_AS} ls -la "${DEST}"

mounted=$(mount | grep fuse.s3fs | grep "${DEST}")
if [ -n "${mounted}" ]; then

    echo "Mount line: ${mounted}"
    echo "Mounted bucket ${AWS_S3_BUCKET} onto ${DEST}"
    exec "$@"
else
    echo "Mount failure"
fi
