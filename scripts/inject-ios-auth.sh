#!/usr/bin/env bash
#
# 把宿主机换来的真实登录态注入 iOS 模拟器 keychain，让 App 以「已登录」状态启动，
# 以支撑 F-012 ③④⑤ 的 B-4.2 手工点按。
#
# 与 run-f011-contract-tests.sh 的关系：
#   那个脚本每次自己重新登录（验证码一次性、有 60 秒发送限流），跑完 7 个用例后
#   tearDown 会把登录态清掉。本脚本复用已经拿到的 token，只跑注入用例 ——
#   注入用例**没有** tearDown，keychain 条目会留到进程退出之后。
#
# 用法：
#   scripts/inject-ios-auth.sh                    # 用 /tmp/wd_tok_a.txt 里的账号 A
#   scripts/inject-ios-auth.sh /tmp/wd_tok_b.txt  # 换成账号 B
#   INJECT_DEVICE="iPhone 16 Pro" scripts/inject-ios-auth.sh
#
# 前置：token 文件两行 —— 第 1 行 accessToken，第 2 行 userId。
#       token 由 wd_login.sh（宿主机侧短信登录）产出。
#
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

TOKEN_FILE="${1:-/tmp/wd_tok_a.txt}"
DEVICE_NAME="${INJECT_DEVICE:-iPhone 16 Pro}"
RESULT_LOG="${INJECT_RESULT_LOG:-/tmp/ios-auth-inject.log}"
BASE_URL="${INJECT_BASE_URL:-http://127.0.0.1:8080/api/}"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

# project.yml 的 sources 是**目录**，xcodegen 在 generate 时枚举一次文件清单。
# 新加/删除测试文件后不重新 generate，新文件不会进 target ——
# 表现为 -only-testing 匹配不到、Executed 0 tests，且 xcodebuild 仍报 TEST SUCCEEDED。
if ! grep -q 'AuthInjectTest.swift' WaterDrop.xcodeproj/project.pbxproj; then
    say "AuthInjectTest.swift 尚未进入 target，重新 xcodegen generate"
    xcodegen generate >/dev/null
    grep -q 'AuthInjectTest.swift' WaterDrop.xcodeproj/project.pbxproj \
        || die "xcodegen 后仍未包含 AuthInjectTest.swift，检查 project.yml 的 WaterDropTests target"
fi

[[ -f "$TOKEN_FILE" ]] || die "token 文件不存在：${TOKEN_FILE}（先用 wd_login.sh 换 token）"
ACCESS_TOKEN="$(sed -n '1p' "$TOKEN_FILE" | tr -d ' \r\n')"
USER_ID="$(sed -n '2p' "$TOKEN_FILE" | tr -d ' \r\n')"
[[ -n "$ACCESS_TOKEN" && -n "$USER_ID" ]] || die "${TOKEN_FILE} 内容不完整（需要两行：token / userId）"

# 注入前先验证 token 在服务端确实有效。否则注入的会是一个「本地看着登录成功、
# 一请求就 401」的假登录态，点按时才暴露，排查成本高得多。
say "校验 token 在服务端是否有效"
profile_code="$(curl -s --noproxy '*' -m 10 -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer $ACCESS_TOKEN" "${BASE_URL%/}/users/profile" || true)"
[[ "$profile_code" == "200" ]] || die "token 无效（GET /users/profile 返回 $profile_code）。重新跑 wd_login.sh 换一个。"
say "token 有效，userId=${USER_ID}"

# 模拟器要开着 xcodebuild 才能装/跑。
# 变量名一律加花括号：macOS 自带 bash 3.2 在 C locale 下会把紧随其后的多字节字符
# （中文、全角括号）当成变量名的一部分，`$DEVICE_NAME」` 会被解析成名为
# "DEVICE_NAME」" 的变量并报 unbound variable。
say "确保模拟器「${DEVICE_NAME}」已启动"
if ! xcrun simctl list devices booted | grep -q "$DEVICE_NAME"; then
    xcrun simctl boot "$DEVICE_NAME" 2>/dev/null || true
    open -a Simulator
    for _ in $(seq 1 60); do
        xcrun simctl list devices booted | grep -q "$DEVICE_NAME" && break
        sleep 1
    done
fi
xcrun simctl list devices booted | grep -q "$DEVICE_NAME" || die "模拟器没能启动"
say "模拟器已就绪"

# TEST_RUNNER_ 前缀必须通过**环境变量**传，写在命令行上只会落到构建设置里，
# 测试进程读不到 —— 表现是用例全 skip 而 xcodebuild 仍报 TEST SUCCEEDED。
export TEST_RUNNER_F011_ACCESS_TOKEN="$ACCESS_TOKEN"
export TEST_RUNNER_F011_USER_ID="$USER_ID"
# 第 3 行（若存在）是 refreshToken。不传的话 App 一旦遇到 401 就会
# 因「无法刷新」清空登录态并踢回登录页。
export TEST_RUNNER_F011_REFRESH_TOKEN="$(sed -n '3p' "$TOKEN_FILE" | tr -d ' \r\n')"
export TEST_RUNNER_SERVER_BASE_URL_OVERRIDE="$BASE_URL"

say "xcodebuild test（只跑 AuthInjectTest）"
set +e
xcodebuild test \
    -project WaterDrop.xcodeproj \
    -scheme WaterDrop \
    -destination "platform=iOS Simulator,name=${DEVICE_NAME}" \
    -only-testing:WaterDropTests/AuthInjectTest \
    2>&1 | tee "$RESULT_LOG"
xcodebuild_status="${PIPESTATUS[0]}"
set -e

# 跳过 ≠ 通过：注入失败时用例会 XCTSkip，xcodebuild 照样报 TEST SUCCEEDED。
summary="$(grep -E 'Executed [0-9]+ tests?, with' "$RESULT_LOG" | tail -1 || true)"
[[ -n "$summary" ]] || die "没找到用例执行统计。完整日志：${RESULT_LOG}"
echo "$summary"

if (( xcodebuild_status != 0 )) || [[ "$summary" == *"failure"* && "$summary" != *"0 failures"* ]]; then
    die "注入失败。完整日志：${RESULT_LOG}"
fi
if [[ "$summary" == *"skipped"* ]]; then
    die "用例被跳过 —— 登录态没注入进去。完整日志：${RESULT_LOG}"
fi
if [[ "$summary" == *"Executed 0 tests"* ]]; then
    die "-only-testing 没匹配到任何用例（多半是新文件没进 target）。完整日志：${RESULT_LOG}"
fi

say "登录态已注入。现在启动 App："
say "  xcrun simctl launch booted com.yjqi.waterdrop.ios"
say "（App 会读到刚写入的 keychain 条目，直接进已登录界面）"
