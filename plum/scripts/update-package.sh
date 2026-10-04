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

# pushd 失败时不会中止脚本，且错误被丢弃；此时 cwd 仍是调用方目录，
# 下面的 git_is_repo 会把外层工程误认成包仓库并对其执行 fetch/reset。
if ! pushd "${package_dir}" &> /dev/null; then
    echo $(warning 'WARNING:') "package dir not found: '${package_dir}', skipped"
    exit 1
fi

current_branch="$(git_current_branch)"
if [[ $? -gt 1 ]]; then
    echo $(warning 'WARNING:') "not a git repository, skipped updating '${package_dir}'"
    exit
fi
if [[ -z "${branch}" ]]; then
    target_branch="$(git_default_branch)"
    # 拿不到 origin/HEAD 时退回当前分支，而不是猜 master/main：
    # 仓库实际分支名可能是 trunk 等任意名字，猜错会让 git checkout 失败并中断安装。
    # detached HEAD 时 current_branch 为空，target_branch 随之留空，由下面的守卫跳过。
    if [[ -z "${target_branch}" ]]; then
        target_branch="${current_branch}"
    fi
else
    target_branch="${branch}"
fi
if [[ -z "${target_branch}" ]]; then
    # 既无默认分支又无当前分支名（如 detached HEAD 且无 origin/HEAD）：
    # 不做任何 git 操作，否则会拿空分支名拼出 "origin/" 这种非法 ref 而中断安装。
    echo $(warning 'WARNING:') "cannot determine branch of '${package_dir}', skipped updating"
elif [[ "${current_branch}" != "${target_branch}" ]]; then
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
