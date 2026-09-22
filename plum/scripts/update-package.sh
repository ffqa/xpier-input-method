#!/usr/bin/env bash

script_dir="$(dirname "$0")"
package_dir="$1"
branch="$2"

option_no_update="${no_update:+1}"

source "${script_dir}"/bootstrap.sh
require 'styles'

if [[ -z "${package_dir}" ]]; then
    echo "Usage: $(basename "$0") <package-dir> [<branch>]"
    exit 1
fi

git_is_repo() {
    # 确保当前目录自身就是独立 git 仓库（有 .git），避免误识别外层工程的 .git
    if ! [[ -e .git ]]; then
        return 1
    fi
    command git rev-parse --git-dir > /dev/null 2>&1
}

git_current_branch() {
    if ! git_is_repo; then
        # not a git repository
        return 2
    fi
    local ref="$(command git symbolic-ref HEAD 2> /dev/null)"
    if [[ -n "$ref" ]]
    then
        echo "${ref#refs/heads/}"
        return 0
    else
        return 1
    fi
}

git_default_branch() {
    if ! git_is_repo; then
        return 2
    fi
    local ref="$(command git symbolic-ref refs/remotes/origin/HEAD 2> /dev/null)"
    if [[ -n "$ref" ]]
    then
        echo "${ref#refs/remotes/origin/}"
        return 0
    else
        return 1
    fi
}

fetch_all_branches() {
    local fetch_all_pattern='\+refs/heads/\*:'
    if ! [[ "$(git config --get remote.origin.fetch)" =~ $fetch_all_pattern ]]; then
        if [[ -n "${option_no_update}" ]]; then
            echo $(warning 'WARNING:') 'forced update for switching branch to' $(print_option "${target_branch}")
        fi
        git config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
    elif [[ -n "${option_no_update}" ]]; then
        return
    fi
    git fetch origin --depth 1
}

switch_branch() {
    local target_branch="$1"
    if [[ -z "${target_branch}" ]]; then
        return 0
    fi
    if [[ -z "${branch}" ]]; then
        echo $(warning 'WARNING:') "'${package_dir}' was on" \
             $(print_option "${current_branch:-(detached HEAD)}") 'instead of' $(print_option "${target_branch}")
    fi
    fetch_all_branches
    git checkout "${target_branch}" || exit 1
}

pushd "${package_dir}" &> /dev/null

current_branch="$(git_current_branch)"
if [[ $? -gt 1 ]]; then
    echo $(warning 'WARNING:') "not a git repository, skipped updating '${package_dir}'"
    exit
fi
if [[ -z "${branch}" ]]; then
    target_branch="$(git_default_branch)"
    if [[ -z "${target_branch}" ]]; then
        target_branch="${current_branch:-master}"
    fi
else
    target_branch="${branch}"
fi
if [[ "${current_branch}" != "${target_branch}" ]]; then
    switch_branch "${target_branch}"
elif [[ -z "${option_no_update}" ]]; then
    git fetch --recurse-submodules && (
        git merge --ff-only "origin/${target_branch}" || (
            echo $(warning 'WARNING:') 'fast-forward failed;' \
                 'doing a hard reset to' $(print_option "origin/${target_branch}")
            git reset --hard "origin/${target_branch}"
        )
    ) || exit 1
fi

popd &> /dev/null
