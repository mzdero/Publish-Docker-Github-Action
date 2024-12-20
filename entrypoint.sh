#!/bin/sh
set -e

function main() {
  echo "" # see https://github.com/actions/toolkit/issues/168

  sanitize "${INPUT_NAME}" "name"
  sanitize "${INPUT_USERNAME}" "username"
  sanitize "${INPUT_PASSWORD}" "password"

  REGISTRY_NO_PROTOCOL=$(echo "${INPUT_REGISTRY}" | sed -e 's/^https:\/\///g')
  if uses "${INPUT_REGISTRY}" && ! isPartOfTheName "${REGISTRY_NO_PROTOCOL}"; then
    INPUT_NAME="${REGISTRY_NO_PROTOCOL}/${INPUT_NAME}"
  fi

  translateDockerTag
  DOCKERNAME="${INPUT_NAME}:${TAG}"
  echo "Building and pushing ${DOCKERNAME}"

  # check if we should do anything at all with this branch
  if { [ -z ${PUSH_BRANCH_TO_DOCKERHUB} ] || [ "${PUSH_BRANCH_TO_DOCKERHUB}" = "false" ]; } && [ "${TAG}" != "develop" ] && [ "${TAG}" != "develop-1.0" ] && [ "${TAG}" != "develop-2.0" ] && [ "${TAG}" != "master" ] &&  ! isReleaseBranch && ! isGitTag ; then
    echo "workflow environment PUSH_BRANCH_TO_DOCKERHUB is false or not set and this is no default branch -> stopping push gracefully -> no error"
    exit 0;
  fi

  if uses "${INPUT_WORKDIR}"; then
    changeWorkingDirectory
  fi

  if uses "${INPUT_DOCKERHUB_USERNAME}" && uses "${INPUT_DOCKERHUB_PASSWORD}"; then
    echo ${INPUT_DOCKERHUB_PASSWORD} | docker login -u ${INPUT_DOCKERHUB_USERNAME} --password-stdin
  fi

  echo ${INPUT_PASSWORD} | docker login -u ${INPUT_USERNAME} --password-stdin ${INPUT_REGISTRY}

  BUILDPARAMS=""

  if uses "${INPUT_DOCKERFILE}"; then
    useCustomDockerfile
  fi
  if uses "${INPUT_BUILDARGS}"; then
    addBuildArgs
  fi
  if uses "${INPUT_BUILDTARGET}"; then
    useBuildTarget
  fi
  if usesBoolean "${INPUT_CACHE}"; then
    useBuildCache
  fi

  if usesBoolean "${INPUT_SNAPSHOT}"; then
    pushWithSnapshot
  else
    pushWithoutSnapshot
  fi
  echo "tag=${TAG}" >> $GITHUB_OUTPUT

  docker logout
}

function sanitize() {
  if [ -z "${1}" ]; then
    >&2 echo "Unable to find the ${2}. Did you set with.${2}?"
    exit 1
  fi
}

function isPartOfTheName() {
  [ $(echo "${INPUT_NAME}" | sed -e "s/${1}//g") != "${INPUT_NAME}" ]
}

function translateDockerTag() {
  if isGitTag && usesBoolean "${INPUT_TAG_NAMES}"; then
    TAG=$(echo ${GITHUB_REF} | sed -e "s/refs\/tags\///g")
  else
    TAG="${GITHUB_SHA}"
  fi;
}

function hasCustomTag() {
  [ $(echo "${INPUT_NAME}" | sed -e "s/://g") != "${INPUT_NAME}" ]
}

function isOnMaster() {
  [ "${BRANCH}" = "master" ]
}

function isGitTag() {
  [ $(echo "${GITHUB_REF}" | sed -e "s/refs\/tags\///g") != "${GITHUB_REF}" ]
}

function isPullRequest() {
  [ $(echo "${GITHUB_REF}" | sed -e "s/refs\/pull\///g") != "${GITHUB_REF}" ]
}

function isReleaseBranch() {
  [ $(echo "${GITHUB_REF}" | sed -e "s/refs\/heads\/release\///g") != "${GITHUB_REF}" ]
}

function changeWorkingDirectory() {
  cd "${INPUT_WORKDIR}"
}

function useCustomDockerfile() {
  BUILDPARAMS="$BUILDPARAMS -f ${INPUT_DOCKERFILE}"
}

function addBuildArgs() {
  for arg in $(echo "${INPUT_BUILDARGS}" | tr ',' '\n'); do
    BUILDPARAMS="$BUILDPARAMS --build-arg ${arg}"
    echo "::add-mask::${arg}"
  done
}

function useBuildCache() {
  if docker pull ${DOCKERNAME} 2>/dev/null; then
    BUILDPARAMS="$BUILDPARAMS --cache-from ${DOCKERNAME}"
  fi
}

function useBuildTarget() {
  BUILDPARAMS="$BUILDPARAMS --target=${INPUT_BUILDTARGET}"
}

function uses() {
  [ ! -z "${1}" ]
}

function usesBoolean() {
  [ ! -z "${1}" ] && [ "${1}" = "true" ]
}

function pushWithSnapshot() {
  local TIMESTAMP=`date +%Y%m%d%H%M%S`
  local SHORT_SHA=$(echo "${GITHUB_SHA}" | cut -c1-6)
  local SNAPSHOT_TAG="${TIMESTAMP}${SHORT_SHA}"
  local SHA_DOCKER_NAME="${INPUT_NAME}:${SNAPSHOT_TAG}"
  docker build $BUILDPARAMS -t ${DOCKERNAME} -t ${SHA_DOCKER_NAME} .
  docker push ${DOCKERNAME}
  docker push ${SHA_DOCKER_NAME}
  echo "snapshot-tag=${SNAPSHOT_TAG}" >> $GITHUB_OUTPUT
}

function pushWithoutSnapshot() {
  docker build $BUILDPARAMS -t ${DOCKERNAME} .
  docker push ${DOCKERNAME}
}

main
