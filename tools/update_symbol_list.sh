#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Update the arg symbol list and prepare a suitable commit
# message for AOSP submission.

readonly GKI_KERNEL_DIR="common"
readonly GKI_KERNEL_REMOTE="aosp"
readonly GKI_KERNEL_BRANCH=$(. ${GKI_KERNEL_DIR}/build.config.constants && echo ${BRANCH})
readonly SYMBOL_LIST="gki/aarch64/symbols/ti"
readonly SYMBOL_LIST_NAME="ti"

PREPARE_AOSP_SYMLIST="0"
BUG=""
COMMIT_TEXT=""
ARGS=()

function usage() {
  cat <<- EOF
    USAGE: $0 [-p|--prepare-aosp-symlist BUG_NUMBER] [-d|--device DEVICE_NAME] [-b|--build-path DEVICE_BUILD_PATH]
    -p | --prepare-aosp-symlist BUG_NUMBER   Update the AOSP symbol list in ${GKI_KERNEL_DIR}/
                                             and create a commit with the provided BUG_NUMBER.
    -d | --device DEVICE_NAME                Device to build kernel modules for (e.g. harriet).
    -b | --build-path DEVICE_BUILD_PATH      Directory to the device build path containing BUILD.bazel.
EOF
}

# Add a trap to remove the temporary files.
function cleanup_trap() {
  rm -f ${COMMIT_TEXT}
  exit $1
}
trap 'cleanup_trap' EXIT

function exit_if_error() {
  if [[ $1 -ne 0 ]]; then
    echo "ERROR: $2: retval=$1" >&2
    exit $1
  fi
}

function verify_aosp_tree {
  if [[ "${PREPARE_AOSP_SYMLIST}" = "0" ]]; then
    return
  fi

  pushd ${GKI_KERNEL_DIR} > /dev/null

  if ! git diff --quiet HEAD; then
    exit_if_error 1 \
    "Found uncommitted changes in ${GKI_KERNEL_DIR}/. Commit your changes before updating the symbol list"
  fi

  popd > /dev/null
}

function make_symbol_list_commit_text() {
  COMMIT_TEXT=$(mktemp -t symlist_commit_text.XXXXX)
  echo "ANDROID: GKI: Update symbol list for ${SYMBOL_LIST_NAME}" > ${COMMIT_TEXT}
  echo >> ${COMMIT_TEXT}
  echo "Bug: ${BUG}" >> ${COMMIT_TEXT}
}

function commit_symbol_list_update() {
  make_symbol_list_commit_text

  pushd ${GKI_KERNEL_DIR} > /dev/null

  if ! git cat-file -e \
          ${GKI_KERNEL_REMOTE}/${GKI_KERNEL_BRANCH}:${SYMBOL_LIST} \
          > /dev/null 2>&1; then
    git add ${SYMBOL_LIST}
  fi

  git commit --quiet -s -F ${COMMIT_TEXT} -- gki/
  rm -f ${COMMIT_TEXT}

  cat <<- EOF

    An ABI commit in ${GKI_KERNEL_DIR}/ was created for you.
    Please verify your commit(s) before pushing. Here are the steps to perform:

    cd ${GKI_KERNEL_DIR}
    git log --oneline HEAD
    git push ${GKI_KERNEL_REMOTE} HEAD:refs/for/${GKI_KERNEL_BRANCH}

    After your commit has been uploaded, please visit the Gerrit link that
    corresponds to your commit, and use the "Rebase" button to rebase to the
    tip of the ${GKI_KERNEL_BRANCH} branch.
EOF

  popd > /dev/null
}

function update_aosp_symlist() {
  local config_parameters="--config=fast --config=${DEVICE_NAME}"
  local build_target="//${DEVICE_KERNEL_BUILD_PATH}:ti_abi_update_symbol_list"

  tools/bazel run ${config_parameters} ${build_target}

  echo "========================================================"
  echo " The symbol list has been updated locally in ${GKI_KERNEL_DIR}/."
  echo " Compiling the common kernel is now required until"
  echo " the new symbol(s) are merged."
}

function read_args() {
  local next
  local device_build_path

  while [[ $# -gt 0 ]]; do
    next="$1"
    case ${next} in
      -p|--prepare-aosp-symlist)
        PREPARE_AOSP_SYMLIST="1"
        BUG="$2"
        if ! [[ "${BUG}" =~ ^[0-9]+$ ]]; then
          exit_if_error 1 "Bug numbers should be digits."
        fi
        shift
        ;;
      -d|--device)
        DEVICE_NAME="$2"
        shift
        ;;
      -b|--build-path)
        device_build_path="$2"
        if ! [[ -f "${device_build_path}/BUILD.bazel" ]]; then
          exit_if_error 1 "${device_build_path}/BUILD.bazel not found"
        fi
        DEVICE_KERNEL_BUILD_PATH="${device_build_path}"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        ARGS+=("$1")
        ;;
    esac
    shift
  done

  if [[ -z "${DEVICE_NAME}" ]]; then
    echo "ERROR: --device is a required argument" >&2
    usage
    exit 1
  fi

  if [[ -z "${DEVICE_KERNEL_BUILD_PATH}" ]]; then
    echo "ERROR: --build-path is a required argument" >&2
    usage
    exit 1
  fi

}

read_args "$@"

# read_args() will ensure to store any arguments that should be passed on
# to the build scripts into the $ARGS array. However, this must be done
# outside of read_args() to affect the positional arguments for the invocation
# of this script, and not just the invocation of read_args().
set -- "${ARGS[@]}"

# Verify the aosp tree is in a good state before compiling anything.
verify_aosp_tree

update_aosp_symlist

if [[ "${PREPARE_AOSP_SYMLIST}" != "0" ]]; then
  commit_symbol_list_update
fi
