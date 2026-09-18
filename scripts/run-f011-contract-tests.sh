#!/usr/bin/env bash
#
# 运行 F-011 契约回归用例（WaterDropTests/F011ContractAPITests.swift）。
#
# 为什么不直接按 ⌘U：
#   用例需要一个**真实登录态**（APIClient 只在有 token 时才带 Authorization 头），
#   而模拟器里拿不到 —— 阿里云融合认证的一键登录依赖真 SIM 卡，模拟器 keychain
#   又无法从外部写入。所以这里在宿主机上先走「短信验证码登录」把 token 换出来，
#   再作为环境变量注入测试进程，等价于用户已登录。
#   Android 侧的 AuthInjectTest.kt 用的是同一套思路。
#
# 用法：
#   scripts/run-f011-contract-tests.sh                 # 默认打本地 127.0.0.1:8080
#   F011_BASE_URL=http://192.168.1.37:8080/api/ scripts/run-f011-contract-tests.sh
#   F011_SKIP_SERVER_CHECK=1 scripts/run-f011-contract-tests.sh   # 服务端已在跑，跳过探测
#
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

# ---- 可调参数 ----------------------------------------------------------------
# 默认打本机 server（spring-boot:run -Dspring-boot.run.profiles=local）。
# 打真机/远程把 F011_BASE_URL 指到对应地址即可。
BASE_URL="${F011_BASE_URL:-http://127.0.0.1:8080/api/}"
# 末位 + 表示 URL 拼接；变量里已带结尾斜杠，这里统一去掉再拼，避免出现双斜杠。
BASE_URL="${BASE_URL%/}"

# 必须是 1[3-9]xxxxxxxxx，且服务端没见过的号会自动注册，所以随便挑一个专用测试号即可。
TEST_PHONE="${F011_PHONE:-13800000001}"

# 本地 Redis 口令。默认值与 wd_server 的 docker-compose.yml /
# application-local.yml 一致 —— 那两处是**已入库**的本地开发值，不是这里新泄露的，
# 脚本沿用同一个默认值只是省得每次手填。生产口令走环境变量覆盖，绝不进本文件。
REDIS_PASSWORD="${REDIS_PASSWORD:-123456}"

DEVICE_NAME="${F011_DEVICE:-iPhone 16 Pro}"
SCHEME="WaterDrop"
RESULT_LOG="${F011_RESULT_LOG:-/tmp/f011-contract-tests.log}"
# -only-testing 的格式是 <target>/<class>，只写类名会被判成「不属于本 scheme」。
ONLY_TESTING="${F011_ONLY_TESTING:-WaterDropTests/F011ContractAPITests}"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

# ---- 1. 确认服务端在跑 -------------------------------------------------------
# /version/check 是 permitAll（F-011 D-8），不需要 token，适合当探针。
# 注意：它只接受 POST。F-012 给 GET 加了显式 405 映射（缺陷 F），
# 所以这里必须用 POST —— 用 GET 探到的是 405，会把健康服务判成不可达。
if [[ -z "${F011_SKIP_SERVER_CHECK:-}" ]]; then
    say "探测服务端 $BASE_URL"
    code="$(curl -s --noproxy '*' -m 5 -o /dev/null -w '%{http_code}' \
        -X POST "$BASE_URL/version/check" \
        -H 'Content-Type: application/json' \
        -d '{"platform":"ios","currentVersion":"0.0.1"}' || true)"
    if [[ "$code" != "200" ]]; then
        die "服务端不可达（POST /version/check 返回 $code）。
    本机起服务：cd '$PROJECT_DIR/../../wd_server' && mvn -o spring-boot:run -Dspring-boot.run.profiles=local
    或设 F011_SKIP_SERVER_CHECK=1 跳过本探测。"
    fi
fi

# ---- 2. 发验证码 -------------------------------------------------------------
# 服务端目前没接真实短信通道（UserServiceImpl 里有 TODO），验证码只落在 Redis。
#
# 两个坑：
#   1. 发送限流 60 秒（SmsCodeUtil.SEND_INTERVAL_SECONDS），连着跑第二次会被挡；
#   2. 验证码是**一次性**的 —— 登录成功就删（SmsCodeUtil.verifyCode 里删 key），
#      所以上一轮发的码这一轮已经没有了，不能靠「上次的还在」蒙混过去。
# 因此这里循环重试：限流就等，取到码就往下走。
CODE_KEY="sms:code:$TEST_PHONE"
read_code() {
    redis-cli -a "$REDIS_PASSWORD" --no-auth-warning GET "$CODE_KEY" 2>/dev/null | tr -d '"\r\n'
}

SMS_CODE=""
for attempt in $(seq 1 25); do
    say "请求验证码 ${TEST_PHONE}（第 $attempt 次）"
    sms_resp="$(curl -s --noproxy '*' -X POST "$BASE_URL/users/sms/send" \
        -H 'Content-Type: application/json' \
        -d "{\"phone\":\"$TEST_PHONE\",\"type\":\"login\"}")"
    echo "    $sms_resp"

    # 每轮都探一次，覆盖「限流但 Redis 里其实已有码」的情况
    SMS_CODE="$(read_code || true)"
    [[ -n "$SMS_CODE" && "$SMS_CODE" != "(nil)" ]] && break

    if [[ "$sms_resp" == *"短信发送过于频繁"* ]]; then
        say "被 60 秒发送限流挡住，等 15 秒重试"
        sleep 15
    else
        sleep 1
    fi
done
[[ -n "$SMS_CODE" && "$SMS_CODE" != "(nil)" ]] \
    || die "Redis 里没有 ${CODE_KEY}。检查 Redis 是否在跑、口令是否正确（\${REDIS_PASSWORD}）。"
say "取到验证码 $SMS_CODE"

# ---- 4. 登录换 token ---------------------------------------------------------
say "登录"
login_json="$(curl -s --noproxy '*' -X POST "$BASE_URL/users/login" \
    -H 'Content-Type: application/json' \
    -d "{\"phone\":\"$TEST_PHONE\",\"smsCode\":\"$SMS_CODE\",\
\"deviceId\":\"f011-contract-runner\",\"platform\":\"ios\"}")"

# 登录响应是 {code,message,data:{accessToken,refreshToken,expiresAt,user:{id,...},authMethod}}，
# userId 嵌在 data.user.id 里，没有顶层 userId。
read -r ACCESS_TOKEN USER_ID <<<"$(
    python3 -c '
import json, sys
r = json.loads(sys.stdin.read())
if r.get("code") != 200:
    sys.stderr.write("登录失败: %s\n" % json.dumps(r, ensure_ascii=False)); sys.exit(1)
d = r["data"]
print(d["accessToken"], d["user"]["id"])
' <<<"$login_json"
)" || die "登录响应解析失败：$login_json"

[[ -n "$ACCESS_TOKEN" && -n "$USER_ID" ]] || die "没拿到 token/userId：$login_json"
say "拿到 token（${#ACCESS_TOKEN} 字符），userId=$USER_ID"

# ---- 5. 跑用例 ---------------------------------------------------------------
# 注入必须走 **xcodebuild 自己的环境变量**，且带 TEST_RUNNER_ 前缀 ——
# xcodebuild 会把前缀剥掉再交给测试进程。
#
# 两个都踩过：
#   - 写成命令行上的 `F011_ACCESS_TOKEN=...`（无前缀）：被当成普通构建设置，
#     测试进程读不到，7 个用例全被 XCTSkip，但 xcodebuild 仍报 TEST SUCCEEDED；
#   - 写成命令行上的 `TEST_RUNNER_F011_ACCESS_TOKEN=...`：同样只落到构建设置里，
#     还是会全 skip。必须 export 到 xcodebuild 的进程环境。
export TEST_RUNNER_F011_ACCESS_TOKEN="$ACCESS_TOKEN"
export TEST_RUNNER_F011_USER_ID="$USER_ID"
# 用例本身不拼 URL（APIClient 读的是 ServerConfig），所以覆盖得打在 App 读的那个键上：
# AppConfig.serverBaseURL 会优先取 SERVER_BASE_URL_OVERRIDE。
export TEST_RUNNER_SERVER_BASE_URL_OVERRIDE="$BASE_URL"

say "xcodebuild test（${DEVICE_NAME}）"
set +e
xcodebuild test \
    -project WaterDrop.xcodeproj \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,name=$DEVICE_NAME" \
    -only-testing:"$ONLY_TESTING" \
    "$@" 2>&1 | tee "$RESULT_LOG"
xcodebuild_status="${PIPESTATUS[0]}"
set -e

# ---- 6. 判定 -----------------------------------------------------------------
# 关键：跳过 ≠ 通过。注入失败时 7 个用例全 skip，xcodebuild 照样报 TEST SUCCEEDED。
# 所以这里额外要求「执行数 > 0 且跳过数 = 0」，否则以失败退出。
summary="$(grep -E 'Executed [0-9]+ tests?, with' "$RESULT_LOG" | tail -1 || true)"
[[ -n "$summary" ]] || die "没找到用例执行统计，xcodebuild 可能没跑起来。完整日志：$RESULT_LOG"

# 统计行形如：
#   Executed 7 tests, with 0 failures (0 unexpected) in 0.781 (0.787) seconds
#   Executed 7 tests, with 7 tests skipped and 0 failures (0 unexpected) in ...
#   Executed 7 tests, with 12 failures (3 unexpected) in 55.6 (55.6) seconds
executed="$(sed -E 's/.*Executed ([0-9]+) tests?.*/\1/' <<<"$summary")"
skipped=0
[[ "$summary" =~ with\ ([0-9]+)\ tests?\ skipped ]] && skipped="${BASH_REMATCH[1]}"
failures=0
[[ "$summary" =~ and\ ([0-9]+)\ failures|with\ ([0-9]+)\ failures ]] \
    && failures="${BASH_REMATCH[1]:-${BASH_REMATCH[2]}}"

echo
say "执行 ${executed} 个用例，跳过 ${skipped}，失败 ${failures}"

if (( xcodebuild_status != 0 )) || (( failures > 0 )); then
    die "用例失败。完整日志：$RESULT_LOG"
fi
if (( skipped > 0 )); then
    die "有 ${skipped} 个用例被跳过 —— 等同未验证。多半是登录态没注入进来，
    请确认上面「拿到 token」那一步成功。完整日志：$RESULT_LOG"
fi
if (( executed == 0 )); then
    die "-only-testing 没匹配到任何用例。完整日志：$RESULT_LOG"
fi

say "全部通过。完整日志：$RESULT_LOG"
