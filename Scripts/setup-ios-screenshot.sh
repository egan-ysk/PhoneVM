#!/usr/bin/env bash
set -euo pipefail

# 工具独立安装在用户目录，不打包进 PhoneVM.app，也不修改系统 Python。
PHONEVM_TOOL_ENV="$HOME/Library/Application Support/PhoneVM/tools/pymobiledevice3"
PHONEVM_PYTHON="${PHONEVM_PYTHON:-python3}"

"$PHONEVM_PYTHON" -m venv "$PHONEVM_TOOL_ENV"
"$PHONEVM_TOOL_ENV/bin/python" -m pip install --timeout 120 --retries 10 'pymobiledevice3==11.12.5'
"$PHONEVM_TOOL_ENV/bin/pymobiledevice3" version
echo "iOS 截屏工具已安装。打开 PhoneVM 并刷新设备列表即可使用。"
