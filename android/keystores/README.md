# 서명 키 (GPG 암호화)

| 파일 | 용도 | 풀 때 쓰는 시크릿 |
|---|---|---|
| `upload.jks.gpg` | Play 스토어 업로드용 AAB 서명 (업로드 키) | `ANDROID_UPLOAD_PASSPHRASE` |
| `sideload.jks.gpg` | 직접 배포용 APK 서명 | `SIDELOAD_PASSPHRASE` |

- 만들기: `tool/make_keystores.sh` 를 실행한다 (docs/RELEASE.md 참고).
- 키스토어 비밀번호와 키 비밀번호는 각 패스프레이즈와 같다. 별칭은 `upload`, `sideload`.
- 암호화되지 않은 `.jks` 는 저장소에 올리지 않는다 (`.gitignore`).
- 업로드 키를 잃어버리면 Play Console 에서 업로드 키 재설정을 요청해야 한다. 원본 `.jks` 는 안전한 곳에 따로 백업한다.
