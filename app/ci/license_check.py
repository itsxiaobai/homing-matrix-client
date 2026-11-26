#!/usr/bin/env python3
# 任務：Phase 0 / 0.11 — CI 授權檢查的第一道閘門：
# 檢查 pubspec.lock 內所有「直接依賴」（direct main / direct dev）都已記錄於
# ../DEPENDENCIES.md，未記錄者讓 CI 失敗。
# 位置：app/ci/license_check.py（以 app 為工作目錄執行）
import re
import sys
from pathlib import Path

LOCK = Path("pubspec.lock")
DEPS_DOC = Path("../DEPENDENCIES.md")


def direct_dependencies(lock_text: str) -> list[str]:
    """擷取 direct main/dev 依賴；SDK 内建（source: sdk，如 flutter_test）不算第三方套件。"""
    direct: dict[str, bool] = {}
    current: str | None = None
    for line in lock_text.splitlines():
        m = re.match(r"^  ([a-zA-Z0-9_]+):\s*$", line)
        if m:
            current = m.group(1)
            continue
        m = re.match(r'^    dependency: "direct (?:main|dev)"\s*$', line)
        if m and current:
            direct[current] = True
            continue
        if current is not None and "source: sdk" in line and current in direct:
            # 依賴來源為 SDK（如 flutter_test），非第三方套件，不進入檢查
            del direct[current]
    return sorted(direct)



def main() -> int:
    lock_text = LOCK.read_text(encoding="utf-8")
    direct = direct_dependencies(lock_text)

    failures: list[str] = []
    if not direct:
        failures.append("pubspec.lock 內沒有任何第三方直接依賴？請人工檢查腳本。")

    deps_doc = DEPS_DOC.read_text(encoding="utf-8")
    for package in direct:
        # 嚴格比對：必須有以該套件名開頭的**獨立條目**（表格列或項目符號），
        # 避免 `image` 被 `image_picker` 之類的字樣誤判為「已記錄」。
        if re.search(rf"(?m)^\|\s*`{re.escape(package)}`", deps_doc):
            continue
        if re.search(rf"(?m)^\s*-\s*`{re.escape(package)}`", deps_doc):
            continue
        failures.append(f"未於 DEPENDENCIES.md 記錄：{package}")

    if failures:
        print("license_check：發現未記錄的依賴：")
        for f in failures:
            print(f"  - {f}")
        print("\n直接依賴清單：" + ", ".join(direct))
        print("規則：新增依賴須人類決定，並於 DEPENDENCIES.md 記錄 SPDX（藍圖 §一）。")
        return 1

    print("license_check 直接依賴皆已記錄：")
    for package in direct:
        print(f"  - {package}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
