#!/usr/bin/env python3
"""CI: GOOGLE_SERVICES_JSON · KAKAO_NATIVE_APP_KEY 시크릿 → --dart-define 줄 (표준출력).
google-services.json 의 값은 공개값이라 앱에 들어가도 된다. google-services Gradle 플러그인 없이 쓴다."""
import json
import os
import sys

PKG = "io.github.graviton94.mintandfriends"
g = json.loads(os.environ.get("GSJ") or "{}")
if g:
    c = next((c for c in g["client"] if c["client_info"]["android_client_info"]["package_name"] == PKG), None)
    if c is None:
        print(f"::warning::google-services.json 에 {PKG} 앱이 없습니다 (Firebase 콘솔에서 Android 앱 추가)", file=sys.stderr)
    else:
        print(f"--dart-define=FB_API_KEY={c['api_key'][0]['current_key']}")
        print(f"--dart-define=FB_APP_ID={c['client_info']['mobilesdk_app_id']}")
        print(f"--dart-define=FB_PROJECT_ID={g['project_info']['project_id']}")
        print(f"--dart-define=FB_SENDER_ID={g['project_info']['project_number']}")
        if g['project_info'].get('storage_bucket'):
            # 앱 리소스(google_storage_bucket)와 같은 값이어야 Firebase 기본 앱 옵션이 일치한다
            print(f"--dart-define=FB_STORAGE_BUCKET={g['project_info']['storage_bucket']}")
        # 안드로이드 리소스 값 (google-services 플러그인이 만드는 것과 같음): Firebase Analytics 는
        # 이 google_app_id 리소스가 없으면 'Missing google_app_id' 로 꺼진다 (1.0.8 까지 지표가 0 이었던 원인)
        res = os.path.join(os.path.dirname(__file__), '..', 'android', 'app', 'src', 'main', 'res', 'values')
        os.makedirs(res, exist_ok=True)
        vals = {
            'google_app_id': c['client_info']['mobilesdk_app_id'],
            'gcm_defaultSenderId': g['project_info']['project_number'],
            'google_api_key': c['api_key'][0]['current_key'],
            'google_crash_reporting_api_key': c['api_key'][0]['current_key'],
            'project_id': g['project_info']['project_id'],
        }
        if g['project_info'].get('storage_bucket'):
            vals['google_storage_bucket'] = g['project_info']['storage_bucket']
        with open(os.path.join(res, 'firebase_ci.xml'), 'w') as f:
            f.write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n')
            for k, v in vals.items():
                f.write(f'    <string name="{k}" translatable="false">{v}</string>\n')
            f.write('</resources>\n')
        print(f"Firebase resource values: {', '.join(vals)}", file=sys.stderr)
        oauth = [o for cl in g["client"] for o in cl.get("oauth_client", [])]
        # 웹 클라이언트는 oauth_client 또는 services.appinvite_service.other_platform_oauth_client 에 들어 있다.
        others = [o for cl in g["client"]
                  for o in cl.get("services", {}).get("appinvite_service", {}).get("other_platform_oauth_client", [])]
        web = next((o["client_id"] for o in oauth + others if o.get("client_type") == 3), None)
        # json 에 없으면 GOOGLE_WEB_CLIENT_ID 시크릿 (Google Cloud → 사용자 인증 정보 → 웹 클라이언트)
        web = web or (os.environ.get("WEB") or "").strip() or None
        if web:
            print(f"--dart-define=GOOGLE_WEB_CLIENT_ID={web}")
        print(f"Google sign-in: web client {'found' if web else 'MISSING'}, Android clients {sum(o.get('client_type') == 1 for o in oauth)}", file=sys.stderr)
k = (os.environ.get("KAKAO") or "").strip()
print(f"Kakao: {'set' if k else 'missing'}", file=sys.stderr)
if k:
    print(f"--dart-define=KAKAO_NATIVE_APP_KEY={k}")

# AdMob 광고 단위 (스토어 빌드만 시크릿을 넘긴다. 없으면 앱 안의 테스트 ID)
for env, name in (("ADMOB_REWARDED", "ADMOB_REWARDED"), ("ADMOB_INTERSTITIAL", "ADMOB_INTERSTITIAL"), ("ADMOB_BANNER", "ADMOB_BANNER")):
    v = (os.environ.get(env) or "").strip()
    if v:
        print(f"--dart-define={name}={v}")
print("AdMob units: " + ", ".join(n for n in ("ADMOB_REWARDED", "ADMOB_INTERSTITIAL") if (os.environ.get(n) or "").strip()) or "AdMob units: test", file=sys.stderr)
