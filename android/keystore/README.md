# 서명 키 (GPG 암호화)

| 파일 | 용도 | 풀 때 쓰는 시크릿 |
|---|---|---|
| `sideload.jks.gpg` | 시험용 APK 서명 (app.yml) | `SIDELOAD_PASSPHRASE` |
| `upload.jks.gpg` | Play 업로드용 AAB 서명 (aab.yml) | `ANDROID_UPLOAD_PASSPHRASE` |

- 만들기: Actions → **Android signing key** 를 `sideload`, `upload` 로 한 번씩 실행. 키를 만들어 암호화한 뒤 이 폴더에 커밋하고, SHA-1/SHA-256 을 실행 요약에 찍는다.
- 키스토어 비밀번호 = 키 비밀번호 = 해당 패스프레이즈. 별칭은 `sideload`, `upload`. 인증서 이름 `CN=Mint and Friends <종류>`.
- 이미 있으면 덮어쓰지 않는다 (`replace` 옵션을 켜야만 교체. 교체하면 설치된 앱 업데이트·Play 업로드가 막힌다).
- 암호화되지 않은 `.jks` 는 저장소에 올리지 않는다.
- 업로드 키를 잃으면 Play Console 에서 업로드 키 재설정을 요청해야 한다. 패스프레이즈는 따로 안전하게 보관.
